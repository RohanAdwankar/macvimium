import AppKit
import CoreGraphics

public enum HintScreenshotRenderer {
    @discardableResult
    public static func capture(windowTarget: WindowTarget, hints: [HintTarget], to outputURL: URL) -> Bool {
        let captureRect = windowTarget.frame.integral.insetBy(dx: -4, dy: -4)
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return false
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(size: size)
        image.lockFocus()

        let destinationRect = CGRect(origin: .zero, size: size)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cgImage, size: size).draw(in: destinationRect)

        for hint in hints {
            drawTag(for: hint, in: captureRect, imageSize: size)
        }

        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            return false
        }

        do {
            try png.write(to: outputURL)
            return true
        } catch {
            return false
        }
    }

    private static func drawTag(for target: HintTarget, in captureRect: CGRect, imageSize: NSSize) {
        let width: CGFloat = max(28, CGFloat(target.label.count) * 11 + 10)
        let height: CGFloat = 18
        let x = min(max(target.frame.minX - captureRect.minX, 0), max(imageSize.width - width, 0))
        let flippedY = min(
            max(target.frame.minY - captureRect.minY - 20, 0),
            max(imageSize.height - height, 0)
        )
        let y = max(imageSize.height - flippedY - height, 0)
        let rect = CGRect(x: x, y: y, width: width, height: height)

        NSColor.black.withAlphaComponent(0.9).setFill()
        NSBezierPath(rect: rect).fill()

        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.stroke()

        let text = NSAttributedString(
            string: target.label,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        text.draw(at: CGPoint(x: rect.minX + 5, y: rect.minY + 2))
    }
}
