import AppKit
import ApplicationServices
import CoreGraphics

private let axWindowNumberAttribute = "AXWindowNumber"

final class WindowSwitcherService {
    func fetchWindowsForFrontmostApp() throws -> (app: NSRunningApplication, windows: [WindowInfo]) {
        guard AccessibilityPermissionManager.ensureTrusted(prompt: false) else {
            throw WindowSwitcherError.accessibilityDenied
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowSwitcherError.noFrontmostApplication
        }

        return try fetchWindows(for: app)
    }

    func fetchWindows(for app: NSRunningApplication) throws -> (app: NSRunningApplication, windows: [WindowInfo]) {
        guard AccessibilityPermissionManager.ensureTrusted(prompt: false) else {
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
