import AppKit
import ApplicationServices
import CoreGraphics

struct HintTarget {
    let label: String
    let frame: CGRect
    let elementHandle: AXElementHandle
    let description: String
}

struct DisplayHintTarget {
    let label: String
    let frame: CGRect
}

final class AXElementHandle {
    private let storage: AXUIElement

    init(_ element: AXUIElement) {
        storage = Unmanaged.passRetained(element).takeUnretainedValue()
    }

    deinit {
        Unmanaged.passUnretained(storage).release()
    }

    var element: AXUIElement {
        storage
    }
}

@MainActor
final class AccessibilityService {
    func requestTrustIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hintTargets(for application: NSRunningApplication) -> [HintTarget] {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedWindow = focusedWindow(for: appElement)
        let windowFrame = focusedWindow.flatMap(frame(for:))
        let elements = actionableElements(startingAt: appElement, constrainedTo: windowFrame)
        let labels = HintLabelGenerator.labels(count: elements.count)

        return zip(labels, elements).compactMap { label, element in
            guard let frame = frame(for: element), frame.width > 0, frame.height > 0 else {
                return nil
            }

            return HintTarget(
                label: label,
                frame: frame,
                elementHandle: AXElementHandle(element),
                description: elementDescription(for: element)
            )
        }
    }

    func activate(_ target: HintTarget) -> Bool {
        for action in preferredActions(for: target.elementHandle.element) {
            if AXUIElementPerformAction(target.elementHandle.element, action as CFString) == .success {
                return true
            }
        }

        return false
    }

    private func focusedWindow(for appElement: AXUIElement) -> AXUIElement? {
        AXHelpers.value(appElement, attribute: kAXFocusedWindowAttribute) as AXUIElement?
    }

    private func actionableElements(startingAt root: AXUIElement, constrainedTo frameConstraint: CGRect?) -> [AXUIElement] {
        var queue = [root]
        var actionable: [AXUIElement] = []
        var visited = Set<CFHashCode>()
        var seenFrames = Set<String>()

        while let element = queue.popLast() {
            let identifier = CFHash(element)
            if visited.contains(identifier) {
                continue
            }
            visited.insert(identifier)

            if let frame = frame(for: element),
               isInsideConstraint(frame, frameConstraint: frameConstraint),
               isActionable(element) {
                let key = dedupeKey(for: frame)
                if !seenFrames.contains(key) {
                    seenFrames.insert(key)
                    actionable.append(element)
                }
            }

            queue.append(contentsOf: relatedElements(for: element))
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
        let actions = supportedActions(for: element)
        if actions.contains(kAXPressAction as String) ||
            actions.contains("AXConfirm") ||
            actions.contains("AXPick") ||
            actions.contains("AXShowMenu") {
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
            "AXToolbarButton",
            "AXPopUpButton",
            "AXMenuButton",
            "AXDisclosureTriangle",
            "AXIncrementor",
            "AXValueIndicator",
            "AXTab",
        ].contains(role)
    }

    private func supportedActions(for element: AXUIElement) -> [String] {
        AXHelpers.value(element, attribute: "AXActions") ?? []
    }

    private func preferredActions(for element: AXUIElement) -> [String] {
        let supported = Set(supportedActions(for: element))
        return [
            kAXPressAction as String,
            "AXConfirm",
            "AXPick",
            "AXShowMenu",
        ].filter { supported.contains($0) }
    }

    private func relatedElements(for element: AXUIElement) -> [AXUIElement] {
        let attributeNames = copyAttributeNames(for: element)
        var results: [AXUIElement] = []

        for attributeName in attributeNames {
            guard let rawValue = copyAttributeValue(for: element, attribute: attributeName) else {
                continue
            }

            results.append(contentsOf: extractElements(from: rawValue))
        }

        return results
    }

    private func copyAttributeNames(for element: AXUIElement) -> [String] {
        var namesRef: CFArray?
        guard AXUIElementCopyAttributeNames(element, &namesRef) == .success,
              let names = namesRef as? [String] else {
            return []
        }

        return names
    }

    private func copyAttributeValue(for element: AXUIElement, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func extractElements(from value: CFTypeRef) -> [AXUIElement] {
        AXHelpers.elements(from: value)
    }

    private func isInsideConstraint(_ frame: CGRect, frameConstraint: CGRect?) -> Bool {
        guard let frameConstraint else {
            return true
        }

        return frame.intersects(frameConstraint.insetBy(dx: -24, dy: -24))
    }

    private func dedupeKey(for frame: CGRect) -> String {
        let x = Int(frame.origin.x.rounded())
        let y = Int(frame.origin.y.rounded())
        let width = Int(frame.width.rounded())
        let height = Int(frame.height.rounded())
        return "\(x):\(y):\(width):\(height)"
    }

    private func elementDescription(for element: AXUIElement) -> String {
        let role = (AXHelpers.value(element, attribute: kAXRoleAttribute) as String?) ?? "unknown-role"
        let title = (AXHelpers.value(element, attribute: kAXTitleAttribute) as String?) ?? ""
        let description = (AXHelpers.value(element, attribute: kAXDescriptionAttribute) as String?) ?? ""
        let value = (AXHelpers.value(element, attribute: kAXValueAttribute) as String?) ?? ""

        let text = [title, description, value]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "untitled"

        return "\(role): \(text)"
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
