import ApplicationServices
import AppKit
import CoreGraphics

public enum PointerAutomation {
    public static func move(to point: CGPoint) -> Bool {
        let point = quartzPoint(forAccessibilityPoint: point)
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }

        move.post(tap: .cghidEventTap)
        return true
    }

    public static func click(at point: CGPoint) -> Bool {
        let point = quartzPoint(forAccessibilityPoint: point)
        guard
            let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else {
            return false
        }

        move.post(tap: .cghidEventTap)
        down.post(tap: .cghidEventTap)
        usleep(12_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    public static func drag(from start: CGPoint, to end: CGPoint, steps: Int = 24) -> Bool {
        let start = quartzPoint(forAccessibilityPoint: start)
        let end = quartzPoint(forAccessibilityPoint: end)
        guard
            let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: start, mouseButton: .left),
            let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: start, mouseButton: .left),
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: end, mouseButton: .left)
        else {
            return false
        }

        move.post(tap: .cghidEventTap)
        usleep(8_000)
        down.post(tap: .cghidEventTap)
        usleep(20_000)

        let safeSteps = max(steps, 2)
        for step in 1...safeSteps {
            let progress = CGFloat(step) / CGFloat(safeSteps)
            let point = CGPoint(
                x: start.x + ((end.x - start.x) * progress),
                y: start.y + ((end.y - start.y) * progress)
            )

            guard let drag = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: point, mouseButton: .left) else {
                return false
            }

            drag.post(tap: .cghidEventTap)
            usleep(12_000)
        }

        up.post(tap: .cghidEventTap)
        return true
    }

    private static func quartzPoint(forAccessibilityPoint point: CGPoint) -> CGPoint {
        for screen in NSScreen.screens {
            let candidate = CGPoint(x: point.x, y: screen.frame.maxY - point.y)
            if screen.frame.contains(candidate) {
                return candidate
            }
        }

        if let mainScreen = NSScreen.main {
            return CGPoint(x: point.x, y: mainScreen.frame.maxY - point.y)
        }

        return point
    }
}
