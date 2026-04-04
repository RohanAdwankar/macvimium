import AppKit

@MainActor
final class StatusController {
    private let statusItem: NSStatusItem
    private let onShowHints: () -> Void

    init(onShowHints: @escaping () -> Void) {
        self.onShowHints = onShowHints
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MV"
        statusItem.button?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let showHintsItem = NSMenuItem(title: "Show Hints (Option+Command+F)", action: #selector(showHints), keyEquivalent: "")
        showHintsItem.target = self
        menu.addItem(showHintsItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return menu
    }

    @objc
    private func showHints() {
        onShowHints()
    }
}
