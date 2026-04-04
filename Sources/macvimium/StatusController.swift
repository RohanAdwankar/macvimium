import AppKit

@MainActor
final class StatusController {
    private let statusItem: NSStatusItem
    private let onShowHints: () -> Void
    private let onRunSelfTest: () -> Void

    init(onShowHints: @escaping () -> Void, onRunSelfTest: @escaping () -> Void) {
        self.onShowHints = onShowHints
        self.onRunSelfTest = onRunSelfTest
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MV"
        statusItem.button?.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let showHintsItem = NSMenuItem(title: "Show Hints", action: #selector(showHints), keyEquivalent: "")
        showHintsItem.target = self
        menu.addItem(showHintsItem)
        let selfTestItem = NSMenuItem(title: "Self-Test Calculator", action: #selector(runSelfTest), keyEquivalent: "")
        selfTestItem.target = self
        menu.addItem(selfTestItem)
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

    @objc
    private func runSelfTest() {
        onRunSelfTest()
    }
}
