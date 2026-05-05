import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

private let axWindowNumberAttribute = "AXWindowNumber"

struct WindowIdentity: Equatable {
    let windowNumber: Int?
    let fallbackTitle: String
}

struct WindowInfo: Equatable {
    let element: AXUIElement
    let title: String
    let isFocused: Bool
    let isMinimized: Bool
    let windowNumber: Int?

    var identity: WindowIdentity {
        WindowIdentity(windowNumber: windowNumber, fallbackTitle: title)
    }
}

enum WindowSwitcherError: LocalizedError {
    case accessibilityDenied
    case noFrontmostApplication
    case applicationUnavailable(String)
    case noWindows
    case axFailure(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility permission is required to inspect and focus windows."
        case .noFrontmostApplication:
            return "No frontmost application could be determined."
        case .applicationUnavailable(let appName):
            return "\(appName) is no longer running."
        case .noWindows:
            return "No titled windows were found for the frontmost application."
        case .axFailure(let message):
            return message
        }
    }
}

final class AccessibilityPermissionManager {
    static func ensureTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

final class WindowSwitcherService {
    func fetchWindowsForFrontmostApp() throws -> (app: NSRunningApplication, windows: [WindowInfo]) {
        guard AccessibilityPermissionManager.ensureTrusted(prompt: true) else {
            throw WindowSwitcherError.accessibilityDenied
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowSwitcherError.noFrontmostApplication
        }

        return try fetchWindows(for: app)
    }

    func fetchWindows(for app: NSRunningApplication) throws -> (app: NSRunningApplication, windows: [WindowInfo]) {
        guard AccessibilityPermissionManager.ensureTrusted(prompt: true) else {
            throw WindowSwitcherError.accessibilityDenied
        }

        guard !app.isTerminated else {
            throw WindowSwitcherError.applicationUnavailable(app.localizedName ?? "The selected application")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedWindow = copyElementAttribute(kAXFocusedWindowAttribute, from: appElement)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success else {
            throw WindowSwitcherError.axFailure("Unable to fetch windows for \(app.localizedName ?? "the frontmost app").")
        }

        let windowElements = (windowsValue as? [AXUIElement]) ?? []
        let windows = reorderWindows(
            windowElements.compactMap { makeWindowInfo(from: $0, focusedWindow: focusedWindow) },
            for: app
        )

        guard !windows.isEmpty else {
            throw WindowSwitcherError.noWindows
        }

        return (app, windows)
    }

    func focusWindow(_ window: WindowInfo, for app: NSRunningApplication) throws {
        guard AccessibilityPermissionManager.ensureTrusted(prompt: false) else {
            throw WindowSwitcherError.accessibilityDenied
        }

        if window.isMinimized {
            _ = AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        _ = app.activate(options: [])

        var errorMessages: [String] = []

        let mainResult = AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        if mainResult != .success {
            errorMessages.append("setting main window failed")
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let focusedResult = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window.element)
        if focusedResult != .success {
            errorMessages.append("setting focused window failed")
        }

        let raiseResult = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        if raiseResult != .success {
            errorMessages.append("raising window failed")
        }

        if mainResult != .success && focusedResult != .success && raiseResult != .success {
            throw WindowSwitcherError.axFailure("Unable to focus the selected window: \(errorMessages.joined(separator: ", ")).")
        }
    }

    private func makeWindowInfo(from element: AXUIElement, focusedWindow: AXUIElement?) -> WindowInfo? {
        guard let title = copyStringAttribute(kAXTitleAttribute, from: element)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }

        let isFocused = focusedWindow.map { CFEqual($0, element) } ?? (copyBoolAttribute(kAXFocusedAttribute, from: element) ?? false)
        let isMinimized = copyBoolAttribute(kAXMinimizedAttribute, from: element) ?? false
        let windowNumber = copyIntAttribute(axWindowNumberAttribute, from: element)
        return WindowInfo(element: element, title: title, isFocused: isFocused, isMinimized: isMinimized, windowNumber: windowNumber)
    }

    private func copyStringAttribute(_ key: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func copyBoolAttribute(_ key: String, from element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success else { return nil }
        return (value as? Bool)
    }

    private func copyElementAttribute(_ key: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let value else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyIntAttribute(_ key: String, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard result == .success, let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    private func reorderWindows(_ windows: [WindowInfo], for app: NSRunningApplication) -> [WindowInfo] {
        let sortedWindows = sortByWindowStack(windows, pid: app.processIdentifier)

        guard let focusedIndex = sortedWindows.firstIndex(where: \.isFocused) else {
            return sortedWindows
        }

        var reordered = sortedWindows
        let focusedWindow = reordered.remove(at: focusedIndex)
        reordered.append(focusedWindow)
        return reordered
    }

    private func sortByWindowStack(_ windows: [WindowInfo], pid: pid_t) -> [WindowInfo] {
        guard
            let cgWindowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: AnyObject]]
        else {
            return windows
        }

        let orderedWindowNumbers = cgWindowList.compactMap { entry -> Int? in
            guard
                let ownerPID = entry[kCGWindowOwnerPID as String] as? NSNumber,
                ownerPID.intValue == pid,
                let layer = entry[kCGWindowLayer as String] as? NSNumber,
                layer.intValue == 0,
                let windowNumber = entry[kCGWindowNumber as String] as? NSNumber
            else {
                return nil
            }

            return windowNumber.intValue
        }

        var orderMap: [Int: Int] = [:]
        for (offset, windowNumber) in orderedWindowNumbers.enumerated() where orderMap[windowNumber] == nil {
            orderMap[windowNumber] = offset
        }

        return windows.sorted { lhs, rhs in
            let lhsRank = lhs.windowNumber.flatMap { orderMap[$0] } ?? Int.max
            let rhsRank = rhs.windowNumber.flatMap { orderMap[$0] } ?? Int.max

            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
}

protocol WindowListViewDelegate: AnyObject {
    func windowListDidConfirmSelection()
    func windowListDidCancel()
}

final class WindowListTableView: NSTableView {
    weak var keyDelegate: WindowListViewDelegate?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            keyDelegate?.windowListDidConfirmSelection()
        case 53:
            keyDelegate?.windowListDidCancel()
        default:
            super.keyDown(with: event)
        }
    }
}

final class WindowRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        let insetRect = bounds.insetBy(dx: 6, dy: 2)
        let selectionPath = NSBezierPath(roundedRect: insetRect, xRadius: 10, yRadius: 10)
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.9).setFill()
        selectionPath.fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }
}

final class WindowCellView: NSTableCellView {
    let shortcutLabel = NSTextField(labelWithString: "")
    let statusImageView = NSImageView(frame: .zero)
    let titleLabel = NSTextField(labelWithString: "")
}

final class WindowPanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, WindowListViewDelegate {
    private enum Layout {
        static let width: CGFloat = 420
        static let headerHeight: CGFloat = 56
        static let rowHeight: CGFloat = 34
        static let minVisibleRows: CGFloat = 1
        static let maxVisibleRows: CGFloat = 8
        static let panelPadding: CGFloat = 12
        static let interSectionSpacing: CGFloat = 10
    }

    private let tableView = WindowListTableView(frame: .zero)
    private let scrollView = NSScrollView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private let appIconView = NSImageView(frame: .zero)
    private let visualEffectView = NSVisualEffectView(frame: .zero)
    private let separatorView = NSView(frame: .zero)

    private var windows: [WindowInfo] = []
    private var currentApp: NSRunningApplication?
    var onSelectWindow: ((WindowInfo, NSRunningApplication) -> Void)?
    var onDismiss: (() -> Void)?
    var displayedApp: NSRunningApplication? { currentApp }
    var selectedWindow: WindowInfo? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < windows.count else { return nil }
        return windows[tableView.selectedRow]
    }

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: 220),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        super.init(window: panel)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(app: NSRunningApplication, windows: [WindowInfo], cycleSelection: Bool) {
        let previousSelectionIdentity = selectedWindow?.identity
        self.currentApp = app
        self.windows = windows
        reloadSelection(cycleSelection: cycleSelection, previousSelectionIdentity: previousSelectionIdentity)
        statusLabel.stringValue = app.localizedName ?? "Unknown App"
        appIconView.image = app.icon

        guard let window else { return }
        resizePanel(for: windows.count)
        position(panel: window)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(tableView)
    }

    func dismissPanel() {
        window?.orderOut(nil)
        onDismiss?()
    }

    func window(atShortcutIndex shortcutIndex: Int) -> WindowInfo? {
        guard shortcutIndex >= 0, shortcutIndex < min(windows.count, 10) else { return nil }
        return windows[shortcutIndex]
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        windows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("WindowCell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? WindowCellView) ?? makeCell(identifier: identifier)
        let windowInfo = windows[row]
        let selected = row == tableView.selectedRow
        let foregroundColor: NSColor = selected ? .alternateSelectedControlTextColor : .labelColor
        let secondaryColor: NSColor = selected ? .alternateSelectedControlTextColor.withAlphaComponent(0.92) : .secondaryLabelColor

        cell.shortcutLabel.stringValue = shortcutText(for: row)
        cell.shortcutLabel.textColor = row < 10 ? secondaryColor : secondaryColor.withAlphaComponent(0.45)
        cell.titleLabel.stringValue = windowInfo.title
        cell.titleLabel.textColor = foregroundColor
        cell.titleLabel.font = windowInfo.isFocused ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13)
        cell.statusImageView.contentTintColor = selected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        cell.statusImageView.image = windowInfo.isFocused ? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Current window") : NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        WindowRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard tableView.selectedRow >= 0 else { return }
        tableView.scrollRowToVisible(tableView.selectedRow)
    }

    func windowListDidConfirmSelection() {
        guard
            let app = currentApp,
            tableView.selectedRow >= 0,
            tableView.selectedRow < windows.count
        else {
            dismissPanel()
            return
        }

        onSelectWindow?(windows[tableView.selectedRow], app)
    }

    func windowListDidCancel() {
        dismissPanel()
    }

    private func setupUI() {
        guard let panel = window else { return }

        let contentView = NSView(frame: panel.contentView?.bounds ?? .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = contentView

        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        appIconView.translatesAutoresizingMaskIntoConstraints = false
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appIconView.wantsLayer = true
        appIconView.layer?.cornerRadius = 9
        appIconView.layer?.masksToBounds = true

        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.wantsLayer = true
        separatorView.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = Layout.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.backgroundColor = .clear
        tableView.gridStyleMask = []
        tableView.keyDelegate = self

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = tableView

        contentView.addSubview(visualEffectView)
        visualEffectView.addSubview(appIconView)
        visualEffectView.addSubview(statusLabel)
        visualEffectView.addSubview(separatorView)
        visualEffectView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            visualEffectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            visualEffectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            appIconView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 16),
            appIconView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 16),
            appIconView.widthAnchor.constraint(equalToConstant: 28),
            appIconView.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.centerYAnchor.constraint(equalTo: appIconView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: appIconView.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -16),

            separatorView.topAnchor.constraint(equalTo: appIconView.bottomAnchor, constant: 12),
            separatorView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 12),
            separatorView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -12),
            separatorView.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: separatorView.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -8)
        ])
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> WindowCellView {
        let cell = WindowCellView(frame: .zero)
        cell.identifier = identifier

        cell.shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        cell.shortcutLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        cell.shortcutLabel.alignment = .right
        cell.shortcutLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        cell.statusImageView.translatesAutoresizingMaskIntoConstraints = false
        cell.statusImageView.imageScaling = .scaleProportionallyUpOrDown
        cell.statusImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)

        cell.titleLabel.font = .systemFont(ofSize: 13)
        cell.titleLabel.lineBreakMode = .byTruncatingTail
        cell.titleLabel.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(cell.shortcutLabel)
        cell.addSubview(cell.statusImageView)
        cell.addSubview(cell.titleLabel)
        cell.imageView = cell.statusImageView
        cell.textField = cell.titleLabel

        NSLayoutConstraint.activate([
            cell.shortcutLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            cell.shortcutLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            cell.shortcutLabel.widthAnchor.constraint(equalToConstant: 32),

            cell.statusImageView.leadingAnchor.constraint(equalTo: cell.shortcutLabel.trailingAnchor, constant: 10),
            cell.statusImageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            cell.statusImageView.widthAnchor.constraint(equalToConstant: 10),
            cell.statusImageView.heightAnchor.constraint(equalToConstant: 10),

            cell.titleLabel.leadingAnchor.constraint(equalTo: cell.statusImageView.trailingAnchor, constant: 10),
            cell.titleLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
            cell.titleLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])

        return cell
    }

    private func reloadSelection(cycleSelection: Bool, previousSelectionIdentity: WindowIdentity?) {
        tableView.reloadData()

        guard !windows.isEmpty else { return }

        let nextIndex: Int

        if cycleSelection,
           window?.isVisible == true,
           let previousSelectionIdentity,
           let previousIndex = windows.firstIndex(where: { $0.identity == previousSelectionIdentity }) {
            nextIndex = (previousIndex + 1) % windows.count
        } else {
            nextIndex = 0
        }

        tableView.selectRowIndexes(IndexSet(integer: nextIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(nextIndex)
    }

    private func position(panel: NSWindow) {
        guard let screen = NSScreen.main ?? NSApp.keyWindow?.screen else { return }

        let size = panel.frame.size
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - (size.width / 2),
            y: visible.midY - (size.height / 2)
        )
        panel.setFrameOrigin(origin)
    }

    private func resizePanel(for windowCount: Int) {
        guard let panel = window else { return }

        let visibleRows = min(max(CGFloat(windowCount), Layout.minVisibleRows), Layout.maxVisibleRows)
        let rowsHeight = (visibleRows * Layout.rowHeight) + (max(visibleRows - 1, 0) * tableView.intercellSpacing.height)
        let panelHeight = Layout.headerHeight + Layout.interSectionSpacing + rowsHeight + (Layout.panelPadding * 2)

        scrollView.hasVerticalScroller = CGFloat(windowCount) > Layout.maxVisibleRows
        let newFrame = NSRect(origin: panel.frame.origin, size: NSSize(width: Layout.width, height: panelHeight))
        panel.setFrame(newFrame, display: false)
    }

    private func shortcutText(for row: Int) -> String {
        guard row < 10 else { return "" }
        let number = row == 9 ? "0" : "\(row + 1)"
        return "⌘\(number)"
    }
}

final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    var onHotKeyPressed: (() -> Void)?
    var onCommandReleased: (() -> Void)?
    var onCommandNumberPressed: ((Int) -> Void)?
    private var globalMonitor: Any?
    private var localKeyMonitor: Any?
    var shouldInterceptLocalCycling: (() -> Bool)?

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    func register() throws {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if status == noErr, hotKeyID.id == 1 {
                    controller.onHotKeyPressed?()
                }

                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            nil
        )

        guard installStatus == noErr else {
            throw WindowSwitcherError.axFailure("Unable to install the global hotkey handler.")
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x57534B59), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Grave),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registerStatus == noErr else {
            throw WindowSwitcherError.axFailure("Unable to register Command + ` as a global hotkey.")
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            if !event.modifierFlags.contains(.command) {
                self.onCommandReleased?()
            }
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }

            if event.type == .flagsChanged, !event.modifierFlags.contains(.command) {
                self.onCommandReleased?()
                return event
            }

            let isCommandGrave = event.type == .keyDown &&
                event.modifierFlags.contains(.command) &&
                event.keyCode == UInt16(kVK_ANSI_Grave)

            if isCommandGrave, self.shouldInterceptLocalCycling?() == true {
                self.onHotKeyPressed?()
                return nil
            }

            if event.type == .keyDown,
               event.modifierFlags.contains(.command),
               self.shouldInterceptLocalCycling?() == true,
               let shortcutIndex = Self.shortcutIndex(for: event) {
                self.onCommandNumberPressed?(shortcutIndex)
                return nil
            }

            return event
        }
    }

    private static func shortcutIndex(for event: NSEvent) -> Int? {
        guard let characters = event.charactersIgnoringModifiers, characters.count == 1 else {
            return nil
        }

        switch characters {
        case "1": return 0
        case "2": return 1
        case "3": return 2
        case "4": return 3
        case "5": return 4
        case "6": return 5
        case "7": return 6
        case "8": return 7
        case "9": return 8
        case "0": return 9
        default: return nil
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = WindowSwitcherService()
    private let hotKeyController = HotKeyController()
    private let panelController = WindowPanelController()

    private var lastPresentedAppPID: pid_t?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController.onSelectWindow = { [weak self] window, app in
            self?.focus(window: window, in: app)
        }

        panelController.onDismiss = { [weak self] in
            self?.lastPresentedAppPID = nil
        }

        hotKeyController.onHotKeyPressed = { [weak self] in
            self?.handleHotKey()
        }

        hotKeyController.onCommandReleased = { [weak self] in
            self?.commitSelectionIfNeeded()
        }

        hotKeyController.onCommandNumberPressed = { [weak self] shortcutIndex in
            self?.commitShortcutSelection(shortcutIndex: shortcutIndex)
        }

        hotKeyController.shouldInterceptLocalCycling = { [weak self] in
            self?.panelController.window?.isVisible == true
        }

        do {
            try hotKeyController.register()
        } catch {
            presentErrorAlert(error)
        }

        _ = AccessibilityPermissionManager.ensureTrusted(prompt: true)
    }

    private func handleHotKey() {
        do {
            if panelController.window?.isVisible == true, let displayedApp = panelController.displayedApp {
                let result = try service.fetchWindows(for: displayedApp)
                lastPresentedAppPID = result.app.processIdentifier
                panelController.present(app: result.app, windows: result.windows, cycleSelection: true)
                return
            }

            let result = try service.fetchWindowsForFrontmostApp()
            let shouldCycle = panelController.window?.isVisible == true && lastPresentedAppPID == result.app.processIdentifier
            lastPresentedAppPID = result.app.processIdentifier
            panelController.present(app: result.app, windows: result.windows, cycleSelection: shouldCycle)
        } catch {
            panelController.dismissPanel()
            presentErrorAlert(error)
        }
    }

    private func commitSelectionIfNeeded() {
        guard
            panelController.window?.isVisible == true,
            let app = panelController.displayedApp,
            let selectedWindow = panelController.selectedWindow
        else {
            return
        }

        focus(window: selectedWindow, in: app)
    }

    private func focus(window: WindowInfo, in app: NSRunningApplication) {
        do {
            try service.focusWindow(window, for: app)
            panelController.dismissPanel()
        } catch {
            panelController.dismissPanel()
            presentErrorAlert(error)
        }
    }

    private func commitShortcutSelection(shortcutIndex: Int) {
        guard
            panelController.window?.isVisible == true,
            let app = panelController.displayedApp,
            let window = panelController.window(atShortcutIndex: shortcutIndex)
        else {
            return
        }

        focus(window: window, in: app)
    }

    private func presentErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Window Switcher"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
