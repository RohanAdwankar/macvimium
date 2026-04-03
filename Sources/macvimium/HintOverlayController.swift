import AppKit

@MainActor
final class HintOverlayController {
    private var windows: [HintOverlayWindow] = []

    func show(targets: [HintTarget], query: String) {
        hide()

        for screen in NSScreen.screens {
            let window = HintOverlayWindow(screen: screen)
            let view = HintOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.targets = targets.filter { $0.frame.intersects(screen.frame) }
            view.query = query
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func hide() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }
}

@MainActor
final class HintOverlayView: NSView {
    var targets: [HintTarget] = [] {
        didSet { needsDisplay = true }
    }

    var query = "" {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for target in targets where query.isEmpty || target.label.hasPrefix(query) {
            drawTag(for: target)
        }
    }

    private func drawTag(for target: HintTarget) {
        guard let screenFrame = window?.screen?.frame else {
            return
        }

        let width: CGFloat = max(28, CGFloat(target.label.count) * 11 + 10)
        let rect = CGRect(
            x: target.frame.minX - screenFrame.minX,
            y: target.frame.maxY - screenFrame.minY - 20,
            width: width,
            height: 18
        )

        let background = NSBezierPath(rect: rect)
        NSColor.black.withAlphaComponent(0.9).setFill()
        background.fill()

        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.lineWidth = 1
        border.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: target.label.hasPrefix(query) && !query.isEmpty ? NSColor.systemYellow : NSColor.white,
        ]
        let text = NSAttributedString(string: target.label, attributes: attributes)
        text.draw(at: CGPoint(x: rect.minX + 5, y: rect.minY + 2))
    }
}
