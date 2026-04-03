import AppKit
import Carbon

@MainActor
final class HintCoordinator {
    private let accessibilityService = AccessibilityService()
    private let overlayController = HintOverlayController()
    private var hotKeyMonitor: HotKeyMonitor?
    private var localKeyMonitor: Any?
    private var targets: [HintTarget] = []
    private var query = ""
    private weak var targetApplication: NSRunningApplication?

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

        let targets = accessibilityService.hintTargets(for: frontmostApp)
        guard !targets.isEmpty else {
            NSSound.beep()
            return
        }

        self.targets = targets
        self.targetApplication = frontmostApp
        query = ""
        NSApp.activate(ignoringOtherApps: true)
        overlayController.show(targets: targets, query: query)
        installKeyMonitor()
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
        overlayController.show(targets: targets, query: query)
    }

    private func activate(_ target: HintTarget) {
        overlayController.hide()
        uninstallKeyMonitor()
        query = ""
        targets = []
        targetApplication?.activate()
        accessibilityService.activate(target)
    }

    private func exitHintMode() {
        overlayController.hide()
        uninstallKeyMonitor()
        query = ""
        targets = []
        targetApplication?.activate()
    }
}
