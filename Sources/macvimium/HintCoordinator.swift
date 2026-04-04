import AppKit
import Carbon

@MainActor
final class HintCoordinator {
    private let accessibilityService = AccessibilityService()
    private let overlayController = HintOverlayController()
    private let calculatorBundleIdentifier = "com.apple.calculator"
    private var hotKeyMonitor: HotKeyMonitor?
    private var localKeyMonitor: Any?
    private var targets: [HintTarget] = []
    private var query = ""
    private var targetApplication: NSRunningApplication?

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
        NSApp.activate(ignoringOtherApps: true)
        overlayController.show(targets: displayTargets(from: targets), query: query)
        installKeyMonitor()
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

    private func installKeyMonitor() {
        uninstallKeyMonitor()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event: event) ? nil : event
        }
    }

    private func uninstallKeyMonitor() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    private func handle(event: NSEvent) -> Bool {
        switch event.keyCode {
        case UInt16(kVK_Escape):
            exitHintMode()
            return true
        case UInt16(kVK_Delete), UInt16(kVK_ForwardDelete):
            guard !query.isEmpty else { return true }
            query.removeLast()
            refresh()
            return true
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1,
              let character = characters.first,
              character.isLetter else {
            return true
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

        return true
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
            self.uninstallKeyMonitor()
            if let targetApplication {
                targetApplication.activate(options: [.activateIgnoringOtherApps])
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
            self.uninstallKeyMonitor()
            targetApplication?.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func displayTargets(from targets: [HintTarget]) -> [DisplayHintTarget] {
        targets.map { target in
            DisplayHintTarget(label: target.label, frame: target.frame)
        }
    }
}
