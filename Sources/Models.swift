import AppKit
import ApplicationServices

struct WindowIdentity: Equatable, Hashable {
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
