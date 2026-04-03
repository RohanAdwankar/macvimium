import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusController?
    private var hintCoordinator: HintCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hintCoordinator = HintCoordinator()
        statusController = StatusController(
            onShowHints: { [weak self] in
                self?.hintCoordinator?.enterHintMode()
            }
        )
    }
}
