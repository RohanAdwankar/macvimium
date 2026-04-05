import AppKit
import ApplicationServices
import CoreGraphics

public struct HintTarget {
    public let label: String
    public let frame: CGRect
    public let elementHandle: AXElementHandle
    public let role: String
    public let bundleIdentifier: String?
    public let description: String
}

public struct DisplayHintTarget {
    public let label: String
    public let frame: CGRect

    public init(label: String, frame: CGRect) {
        self.label = label
        self.frame = frame
    }
}

public final class AXElementHandle {
    private let storage: AXUIElement

    public init(_ element: AXUIElement) {
        storage = Unmanaged.passRetained(element).takeUnretainedValue()
    }

    deinit {
        Unmanaged.passUnretained(storage).release()
    }

    public var element: AXUIElement {
        storage
    }
}

@MainActor
public final class AccessibilityService {
    public init() {}

    public func requestTrustIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func hintTargets(for application: NSRunningApplication) -> [HintTarget] {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedWindow = focusedWindow(for: appElement)
        let windowFrame = focusedWindow.flatMap(frame(for:))
        let elements = filteredElements(
            from: actionableElements(startingAt: appElement, constrainedTo: windowFrame),
            constrainedTo: windowFrame
        )
        let labels = HintLabelGenerator.labels(count: elements.count)

        return zip(labels, elements).compactMap { label, element in
            guard
                let frame = frame(for: element),
                frame.width > 0,
                frame.height > 0,
                let role = role(for: element)
            else {
                return nil
            }

            return HintTarget(
                label: label,
                frame: frame,
                elementHandle: AXElementHandle(element),
                role: role,
                bundleIdentifier: application.bundleIdentifier,
                description: elementDescription(for: element)
            )
        }
    }

    public func activate(_ target: HintTarget) -> Bool {
        var didActivate = false
        for action in preferredActions(for: target.elementHandle.element) {
            if AXUIElementPerformAction(target.elementHandle.element, action as CFString) == .success {
                didActivate = true
                break
            }
        }

        if shouldUseMouseFallback(for: target) {
            return syntheticClick(at: target.frame.center)
        }

        return didActivate
    }

    public func moveFocusedWindow(of application: NSRunningApplication, to origin: CGPoint) -> Bool {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard
            let window = focusedWindow(for: appElement),
            let value = AXHelpers.axValue(point: origin)
        else {
            return false
        }

        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) == .success
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
        guard let role = role(for: element), !ignoredRoles.contains(role) else {
            return false
        }

        let actions = supportedActions(for: element)
        if actions.contains(kAXPressAction as String) ||
            actions.contains("AXConfirm") ||
            actions.contains("AXPick") ||
            actions.contains("AXShowMenu") {
            return true
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

    private var ignoredRoles: Set<String> {
        [
            "AXToolbar",
            "AXGroup",
            "AXLayoutArea",
            "AXScrollArea",
            "AXSplitGroup",
            "AXBrowser",
        ]
    }

    private func supportedActions(for element: AXUIElement) -> [String] {
        var actionNames: CFArray?
        guard AXUIElementCopyActionNames(element, &actionNames) == .success,
              let actionNames = actionNames as? [String] else {
            return []
        }

        return actionNames
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

    private func filteredElements(from elements: [AXUIElement], constrainedTo frameConstraint: CGRect?) -> [AXUIElement] {
        let candidates = elements.compactMap { element -> Candidate? in
            guard
                let frame = frame(for: element),
                let role = role(for: element),
                isInsideConstraint(frame, frameConstraint: frameConstraint),
                frame.width >= 8,
                frame.height >= 8
            else {
                return nil
            }

            return Candidate(
                element: element,
                frame: frame,
                role: role,
                description: elementDescription(for: element)
            )
        }

        let sorted = candidates.sorted { lhs, rhs in
            let lhsScore = candidateScore(lhs)
            let rhsScore = candidateScore(rhs)
            if lhsScore == rhsScore {
                return lhs.frame.area < rhs.frame.area
            }
            return lhsScore > rhsScore
        }

        var chosen: [Candidate] = []

        for candidate in sorted {
            if chosen.contains(where: { overlapsStrongly(candidate.frame, $0.frame) }) {
                continue
            }

            chosen.append(candidate)
        }

        return chosen
            .map(\.element)
            .sorted { lhs, rhs in
                let lhsOrigin = frame(for: lhs)?.origin ?? .zero
                let rhsOrigin = frame(for: rhs)?.origin ?? .zero
                if lhsOrigin.y == rhsOrigin.y {
                    return lhsOrigin.x < rhsOrigin.x
                }
                return lhsOrigin.y > rhsOrigin.y
            }
    }

    private func candidateScore(_ candidate: Candidate) -> Int {
        var score = 0
        if candidate.role == kAXButtonRole as String || candidate.role == "AXLink" {
            score += 5
        }
        if !candidate.description.contains("untitled") {
            score += 3
        }
        if candidate.frame.area < 40_000 {
            score += 2
        }
        if candidate.frame.area > 200_000 {
            score -= 4
        }
        return score
    }

    private func overlapsStrongly(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return false
        }

        let overlapArea = intersection.width * intersection.height
        let smallerArea = min(lhs.area, rhs.area)
        guard smallerArea > 0 else {
            return false
        }

        if overlapArea / smallerArea > 0.7 {
            return true
        }

        return lhs.center.distance(to: rhs.center) < 12
    }

    private func shouldUseMouseFallback(for target: HintTarget) -> Bool {
        let buttonLikeRoles: Set<String> = [
            kAXButtonRole as String,
            "AXLink",
            kAXCheckBoxRole as String,
            kAXRadioButtonRole as String,
            "AXMenuButton",
            "AXPopUpButton",
            "AXToolbarButton",
            "AXTab",
        ]

        if target.bundleIdentifier == "com.docker.docker" {
            return true
        }

        return buttonLikeRoles.contains(target.role)
    }

    private func syntheticClick(at point: CGPoint) -> Bool {
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
        let role = role(for: element) ?? "unknown-role"
        let title = (AXHelpers.value(element, attribute: kAXTitleAttribute) as String?) ?? ""
        let description = (AXHelpers.value(element, attribute: kAXDescriptionAttribute) as String?) ?? ""
        let value = (AXHelpers.value(element, attribute: kAXValueAttribute) as String?) ?? ""

        let text = [title, description, value]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "untitled"

        return "\(role): \(text)"
    }

    private func role(for element: AXUIElement) -> String? {
        AXHelpers.value(element, attribute: kAXRoleAttribute) as String?
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

private struct Candidate {
    let element: AXUIElement
    let frame: CGRect
    let role: String
    let description: String
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
