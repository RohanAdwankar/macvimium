import AppKit
import Carbon

@MainActor
final class HintCoordinator {
    private let accessibilityService = AccessibilityService()
    private let overlayController = HintOverlayController()
    private let calculatorBundleIdentifier = "com.apple.calculator"
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
            print("macvimium: accessibility permission not granted")
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            print("macvimium: no eligible frontmost app")
            return
        }

        enterHintMode(for: frontmostApp)
    }

    func runCalculatorSelfTest() {
        guard accessibilityService.requestTrustIfNeeded() else {
            print("macvimium: accessibility permission not granted")
            return
        }

        let launched = NSWorkspace.shared.launchApplication(withBundleIdentifier: calculatorBundleIdentifier, options: [.default], additionalEventParamDescriptor: nil, launchIdentifier: nil)
        guard launched else {
            print("macvimium: failed to open Calculator")
            return
        }

        print("macvimium: running Calculator self-test")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: self.calculatorBundleIdentifier).first else {
                print("macvimium: Calculator did not return a running application")
                return
            }

            app.activate()
            self.enterHintMode(for: app)
            self.activateCalculatorSafeTarget()
        }
    }

    private func enterHintMode(for frontmostApp: NSRunningApplication) {
        let targets = accessibilityService.hintTargets(for: frontmostApp)
        guard !targets.isEmpty else {
            print("macvimium: no hint targets found for \(frontmostApp.localizedName ?? "unknown app")")
            NSSound.beep()
            return
        }

        print("macvimium: showing \(targets.count) hints for \(frontmostApp.localizedName ?? "unknown app")")
        for target in targets {
            print("macvimium: hint \(target.label) -> \(target.description)")
        }
        self.targets = targets
        self.targetApplication = frontmostApp
        query = ""
        overlayController.show(targets: displayTargets(from: targets), query: query)
        inputInterceptor.start()
    }

    private func activateCalculatorSafeTarget() {
        guard let target = targets.first(where: { $0.description.contains("All Clear") }) else {
            print("macvimium: Calculator self-test could not find All Clear")
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.activate(target)
        }
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
        print("macvimium: activating hint \(target.label)")
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
                let didActivate = self.accessibilityService.activate(selectedTarget)
                print("macvimium: AX action \(didActivate ? "succeeded" : "failed") for \(selectedTarget.label)")
            }
        }
    }

    private func exitHintMode() {
        print("macvimium: exiting hint mode")
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
