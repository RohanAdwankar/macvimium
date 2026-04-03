import AppKit
import ApplicationServices
import CoreGraphics

struct HintTarget {
    let label: String
    let frame: CGRect
    let element: AXUIElement
}

@MainActor
final class AccessibilityService {
    func requestTrustIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hintTargets(for application: NSRunningApplication) -> [HintTarget] {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let rootElement = focusedWindow(for: appElement) ?? appElement
        let elements = actionableElements(startingAt: rootElement)
        let labels = HintLabelGenerator.labels(count: elements.count)

        return zip(labels, elements).compactMap { label, element in
            guard let frame = frame(for: element), frame.width > 0, frame.height > 0 else {
                return nil
            }

            return HintTarget(label: label, frame: frame, element: element)
        }
    }

    func activate(_ target: HintTarget) {
        AXUIElementPerformAction(target.element, kAXPressAction as CFString)
    }

    private func focusedWindow(for appElement: AXUIElement) -> AXUIElement? {
        AXHelpers.value(appElement, attribute: kAXFocusedWindowAttribute) as AXUIElement?
    }

    private func actionableElements(startingAt root: AXUIElement) -> [AXUIElement] {
        var queue = [root]
        var actionable: [AXUIElement] = []
        var visited = Set<CFHashCode>()

        while let element = queue.popLast() {
            let identifier = CFHash(element)
            if visited.contains(identifier) {
                continue
            }
            visited.insert(identifier)

            if isActionable(element) {
                actionable.append(element)
            }

            if let children: [AXUIElement] = AXHelpers.value(element, attribute: kAXChildrenAttribute) {
                queue.append(contentsOf: children)
            }
        }

        return actionable.sorted { lhs, rhs in
            let lhsOrigin = frame(for: lhs)?.origin ?? .zero
            let rhsOrigin = frame(for: rhs)?.origin ?? .zero
            if lhsOrigin.y == rhsOrigin.y {
                return lhsOrigin.x < rhsOrigin.x
            }
            return lhsOrigin.y > rhsOrigin.y
        }
    }

    private func isActionable(_ element: AXUIElement) -> Bool {
        if let actions: [String] = AXHelpers.value(element, attribute: "AXActions"),
           actions.contains(kAXPressAction) {
            return true
        }

        guard let role: String = AXHelpers.value(element, attribute: kAXRoleAttribute) else {
            return false
        }

        return [
            kAXButtonRole as String,
            "AXLink",
            kAXMenuItemRole as String,
            kAXCheckBoxRole as String,
            kAXRadioButtonRole as String,
        ].contains(role)
    }

    private func frame(for element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let origin = AXHelpers.cgPoint(from: positionValue),
            let size = AXHelpers.cgSize(from: sizeValue)
        else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }
}
