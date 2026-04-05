import ApplicationServices
import AppKit
import CoreGraphics

public enum PointerAutomation {
    private static let tapLocation: CGEventTapLocation = .cgSessionEventTap

    public static func move(to point: CGPoint, pid: pid_t? = nil) -> Bool {
        let point = screenPoint(forAccessibilityPoint: point)
        guard
            let source = eventSource(),
            let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        else {
            return false
        }
        post(move, pid: pid)
        return true
    }

    public static func click(at point: CGPoint, pid: pid_t? = nil) -> Bool {
        let point = screenPoint(forAccessibilityPoint: point)
        guard
            let source = eventSource(),
            let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            return false
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.setIntegerValueField(.mouseEventPressure, value: 1)
        up.setIntegerValueField(.mouseEventPressure, value: 0)

        post(move, pid: pid)
        usleep(16_000)
        post(down, pid: pid)
        usleep(20_000)
        post(up, pid: pid)
        return true
    }

    public static func drag(from start: CGPoint, to end: CGPoint, pid: pid_t? = nil, steps: Int = 24) -> Bool {
        let start = screenPoint(forAccessibilityPoint: start)
        let end = screenPoint(forAccessibilityPoint: end)
        guard
            let source = eventSource(),
            let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left),
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        else {
            return false
        }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        down.setIntegerValueField(.mouseEventPressure, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventPressure, value: 0)

        post(move, pid: pid)
        usleep(16_000)
        post(down, pid: pid)
        usleep(24_000)

        let safeSteps = max(steps, 2)
        for step in 1...safeSteps {
            let progress = CGFloat(step) / CGFloat(safeSteps)
            let point = CGPoint(
                x: start.x + ((end.x - start.x) * progress),
                y: start.y + ((end.y - start.y) * progress)
            )

            guard let drag = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) else {
                return false
            }
            drag.setIntegerValueField(.mouseEventClickState, value: 1)
            drag.setIntegerValueField(.mouseEventPressure, value: 1)

            post(drag, pid: pid)
            usleep(12_000)
        }

        post(up, pid: pid)
        return true
    }

    public static func screenPoint(forAccessibilityPoint point: CGPoint) -> CGPoint {
        return point
    }

    private static func post(_ event: CGEvent, pid: pid_t?) {
        if let pid {
            event.postToPid(pid)
        } else {
            event.post(tap: tapLocation)
        }
    }

    private static func eventSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.localEventsSuppressionInterval = 0
        return source
    }
}
