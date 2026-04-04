import AppKit

@MainActor
final class HintOverlayController {
    private var windows: [HintOverlayWindow] = []

    func show(targets: [DisplayHintTarget], query: String) {
        let screens = NSScreen.screens
        ensureWindows(for: screens)

        for (window, screen) in zip(windows, screens) {
            let view: HintOverlayView
            if let existingView = window.contentView as? HintOverlayView {
                view = existingView
                view.frame = CGRect(origin: .zero, size: screen.frame.size)
            } else {
                view = HintOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
                window.contentView = view
            }

            window.setFrame(screen.frame, display: false)
            view.targets = targets.filter { $0.frame.intersects(screen.frame) }
            view.query = query
            window.orderFrontRegardless()
        }
    }

    func hide() {
        windows.forEach { window in
            (window.contentView as? HintOverlayView)?.targets = []
            window.orderOut(nil)
        }
    }

    private func ensureWindows(for screens: [NSScreen]) {
        guard windows.count < screens.count else {
            return
        }

        for screen in screens.dropFirst(windows.count) {
            windows.append(HintOverlayWindow(screen: screen))
        }
    }
}

@MainActor
final class HintOverlayView: NSView {
    var targets: [DisplayHintTarget] = [] {
        didSet { needsDisplay = true }
    }

    var query = "" {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for target in targets where query.isEmpty || target.label.hasPrefix(query) {
            drawTag(for: target)
        }
    }

    private func drawTag(for target: DisplayHintTarget) {
        guard let screenFrame = window?.screen?.frame else {
            return
        }

        let width: CGFloat = max(28, CGFloat(target.label.count) * 11 + 10)
        let x = min(max(target.frame.minX - screenFrame.minX, 0), max(bounds.width - width, 0))
        let y = min(max(target.frame.minY - screenFrame.minY - 20, 0), max(bounds.height - 18, 0))
        let rect = CGRect(
            x: x,
            y: y,
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
