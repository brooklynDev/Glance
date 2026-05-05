import AppKit
import Carbon

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
