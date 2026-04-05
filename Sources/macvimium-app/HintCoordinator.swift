import AppKit
import Carbon
import MacVimiumCore

@MainActor
final class HintCoordinator {
    private let accessibilityService = AccessibilityService()
    private let overlayController = HintOverlayController()
    private var hotKeyMonitor: HotKeyMonitor?
    private var targets: [HintTarget] = []
    private var query = ""
    private var targetApplication: NSRunningApplication?
    private lazy var inputInterceptor = HintInputInterceptor { [weak self] input in
        self?.handle(input: input)
    }

    init() {
        hotKeyMonitor = HotKeyMonitor { [weak self] in
            self?.enterHintMode()
        }
    }

    func enterHintMode() {
        guard accessibilityService.requestTrustIfNeeded() else {
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        enterHintMode(for: frontmostApp)
    }

    private func enterHintMode(for frontmostApp: NSRunningApplication) {
        let targets = accessibilityService.hintTargets(for: frontmostApp)
        guard !targets.isEmpty else {
            NSSound.beep()
            return
        }

        self.targets = targets
        self.targetApplication = frontmostApp
        query = ""
        overlayController.show(targets: displayTargets(from: targets), query: query)
        inputInterceptor.start()
    }

    private func handle(input: HintKeyInput) {
        switch input.keyCode {
        case UInt16(kVK_Escape):
            exitHintMode()
            return
        case UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
            guard !query.isEmpty else { return }
            query.removeLast()
            refresh()
            return
        default:
            break
        }

        let characters = input.characters.uppercased()
        guard
              characters.count == 1,
              let character = characters.first,
              character.isLetter else {
            return
        }

        query.append(character)
        let matches = targets.filter { $0.label.hasPrefix(query) }

        switch matches.count {
        case 0:
            NSSound.beep()
            query.removeLast()
            refresh()
        case 1 where matches[0].label == query:
            activate(matches[0])
        default:
            refresh()
        }
    }

    private func refresh() {
        overlayController.show(targets: displayTargets(from: targets), query: query)
    }

    private func activate(_ target: HintTarget) {
        let targetApplication = self.targetApplication
        let selectedTarget = target
        query = ""
        targets = []
        self.targetApplication = nil
        DispatchQueue.main.async {
            self.overlayController.hide()
            self.inputInterceptor.stop()
            if let targetApplication {
                targetApplication.activate()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                _ = self.accessibilityService.activate(selectedTarget)
            }
        }
    }

    private func exitHintMode() {
        query = ""
        targets = []
        let targetApplication = self.targetApplication
        self.targetApplication = nil
        DispatchQueue.main.async {
            self.overlayController.hide()
            self.inputInterceptor.stop()
            targetApplication?.activate()
        }
    }

    private func displayTargets(from targets: [HintTarget]) -> [DisplayHintTarget] {
        targets.map { target in
            DisplayHintTarget(label: target.label, frame: target.frame)
        }
    }
}
