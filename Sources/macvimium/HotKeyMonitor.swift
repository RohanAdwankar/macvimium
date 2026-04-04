import Carbon
import Foundation

@MainActor
final class HotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        register()
    }

    private func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event else { return noErr }

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

            guard status == noErr, hotKeyID.id == 1, let userData else {
                return noErr
            }

            let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            print("macvimium: hotkey pressed")
            DispatchQueue.main.async {
                monitor.handler()
            }
            return noErr
        }

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
        if installStatus != noErr {
            print("macvimium: failed to install hotkey handler (\(installStatus))")
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D56494D), id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_Semicolon),
            UInt32(controlKey + optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus == noErr {
            print("macvimium: registered hotkey Control+Option+;")
        } else {
            print("macvimium: failed to register hotkey (\(registerStatus))")
        }
    }
}
