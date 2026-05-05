import AppKit

final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    override init() {
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        if let button = statusItem.button {
            button.image = makeStatusImage()
            button.image?.isTemplate = true
            button.toolTip = "Glance"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Glance", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Glance", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func makeStatusImage() -> NSImage? {
        if let image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Glance") {
            return image
        }

        return NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Glance")
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermissionManager.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
