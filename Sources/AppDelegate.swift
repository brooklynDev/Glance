import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = WindowSwitcherService()
    private let hotKeyController = HotKeyController()
    private let panelController = WindowPanelController()
    private var statusItemController: StatusItemController?

    private var lastCycleState: CycleState?

    private struct CycleState {
        let appPID: pid_t
        let orderedIdentities: [WindowIdentity]
        let focusedIdentity: WindowIdentity
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController()

        panelController.onSelectWindow = { [weak self] window, app in
            self?.focus(window: window, in: app)
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

        _ = AccessibilityPermissionManager.ensureTrusted(prompt: false)
    }

    private func handleHotKey() {
        do {
            if panelController.window?.isVisible == true {
                panelController.advanceSelection()
                return
            }

            let result = try service.fetchWindowsForFrontmostApp()
            let windows = windowsContinuingLastCycleIfPossible(result.windows, for: result.app)
            panelController.present(app: result.app, windows: windows, cycleSelection: false)
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
            rememberCycleFocus(window, in: app)
            panelController.dismissPanel()
        } catch {
            panelController.dismissPanel()
            presentErrorAlert(error)
        }
    }

    private func windowsContinuingLastCycleIfPossible(_ windows: [WindowInfo], for app: NSRunningApplication) -> [WindowInfo] {
        guard
            let lastCycleState,
            lastCycleState.appPID == app.processIdentifier,
            windows.contains(where: { $0.isFocused && $0.identity == lastCycleState.focusedIdentity })
        else {
            return windows
        }

        let windowsByIdentity = Dictionary(grouping: windows, by: \.identity)
        var usedIdentities = Set<WindowIdentity>()
        var reorderedWindows: [WindowInfo] = []

        for identity in lastCycleState.orderedIdentities {
            guard
                usedIdentities.insert(identity).inserted,
                let matchingWindow = windowsByIdentity[identity]?.first
            else {
                continue
            }

            reorderedWindows.append(matchingWindow)
        }

        for window in windows where !usedIdentities.contains(window.identity) {
            reorderedWindows.append(window)
        }

        guard
            reorderedWindows.count == windows.count,
            let focusedIndex = reorderedWindows.firstIndex(where: { $0.identity == lastCycleState.focusedIdentity })
        else {
            return windows
        }

        return Array(reorderedWindows[(focusedIndex + 1)...]) + Array(reorderedWindows[...focusedIndex])
    }

    private func rememberCycleFocus(_ window: WindowInfo, in app: NSRunningApplication) {
        lastCycleState = CycleState(
            appPID: app.processIdentifier,
            orderedIdentities: panelController.orderedWindowIdentities,
            focusedIdentity: window.identity
        )
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
        if case WindowSwitcherError.accessibilityDenied = error {
            presentAccessibilityPermissionAlert(requestSystemPrompt: true)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Glance"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentAccessibilityPermissionAlert(requestSystemPrompt: Bool) {
        if requestSystemPrompt {
            _ = AccessibilityPermissionManager.ensureTrusted(prompt: true)
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Glance Needs Accessibility Access"
        alert.informativeText = """
        Enable Glance in System Settings > Privacy & Security > Accessibility.

        If Glance is already enabled but this message keeps appearing, remove Glance from that list, add the copy in /Applications again, and turn it on. macOS can keep a stale permission entry after replacing an unsigned development build.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermissionManager.openSettings()
        }
    }
}
