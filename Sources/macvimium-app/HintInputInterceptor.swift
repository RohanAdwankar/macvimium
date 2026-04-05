import AppKit

struct HintKeyInput {
    let keyCode: UInt16
    let characters: String
}

@MainActor
final class HintInputInterceptor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let handler: (HintKeyInput) -> Void

    init(handler: @escaping (HintKeyInput) -> Void) {
        self.handler = handler
    }

    func start() {
        guard eventTap == nil else {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
            return
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard
                type == .keyDown,
                let userInfo
            else {
                return Unmanaged.passUnretained(event)
            }

            let interceptor = Unmanaged<HintInputInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            let input = HintKeyInput(
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                characters: event.characters()
            )

            DispatchQueue.main.async {
                interceptor.handler(input)
            }

            return nil
        }

        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            print("macvimium: failed to create key interceptor")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.eventTap = eventTap
        self.runLoopSource = source
    }

    func stop() {
        guard let eventTap, let runLoopSource else {
            return
        }

        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.eventTap = nil
        self.runLoopSource = nil
    }
}

private extension CGEvent {
    func characters() -> String {
        var count: Int = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &count, unicodeString: nil)
        guard count > 0 else {
            return ""
        }

        var buffer = Array(repeating: UniChar(0), count: count)
        keyboardGetUnicodeString(maxStringLength: count, actualStringLength: &count, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: count)
    }
}
