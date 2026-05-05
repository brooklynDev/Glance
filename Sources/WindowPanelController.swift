import AppKit

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
    var orderedWindowIdentities: [WindowIdentity] {
        windows.map(\.identity)
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
        let previousSelectionIndex = selectedRowIndex
        self.currentApp = app
        self.windows = windows
        reloadSelection(cycleSelection: cycleSelection, previousSelectionIndex: previousSelectionIndex)
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

    func advanceSelection() {
        guard !windows.isEmpty else { return }

        let currentIndex = selectedRowIndex ?? -1
        let nextIndex = (currentIndex + 1) % windows.count
        tableView.selectRowIndexes(IndexSet(integer: nextIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(nextIndex)
    }

    private var selectedRowIndex: Int? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < windows.count else { return nil }
        return tableView.selectedRow
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

    private func reloadSelection(cycleSelection: Bool, previousSelectionIndex: Int?) {
        tableView.reloadData()

        guard !windows.isEmpty else { return }

        let nextIndex: Int

        if cycleSelection,
           window?.isVisible == true,
           let previousIndex = previousSelectionIndex {
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
