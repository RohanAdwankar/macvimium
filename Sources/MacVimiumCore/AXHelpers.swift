import ApplicationServices
import CoreGraphics

enum AXHelpers {
    static func value<T>(_ element: AXUIElement, attribute: String, as type: T.Type = T.self) -> T? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard result == .success, let rawValue else {
            return nil
        }

        return rawValue as? T
    }

    static func cgPoint(from value: CFTypeRef?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    static func cgSize(from value: CFTypeRef?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }

    static func axValue(point: CGPoint) -> AXValue? {
        var point = point
        return AXValueCreate(.cgPoint, &point)
    }

    static func element(from value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return (value as! AXUIElement)
    }

    static func elements(from value: CFTypeRef) -> [AXUIElement] {
        if let element = element(from: value) {
            return [element]
        }

        guard let array = value as? [Any] else {
            return []
        }

        return array.compactMap { item in
            let cfValue = item as CFTypeRef
            return element(from: cfValue)
        }
    }
}
