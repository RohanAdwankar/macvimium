import AppKit
import Foundation
import MacVimiumCore

@MainActor
enum MacClickCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        guard !arguments.isEmpty else {
            printUsage()
            exit(EXIT_FAILURE)
        }

        if arguments.count == 1 && ["--help", "-h", "help"].contains(arguments[0].lowercased()) {
            printUsage()
            return
        }

        switch arguments[0].lowercased() {
        case "open":
            openApplication(arguments.dropFirst())
        default:
            handleTargetCommand(arguments)
        }
    }

    private static func handleTargetCommand(_ arguments: [String]) {
        guard let targetQuery = arguments.first else {
            printUsage()
            exit(EXIT_FAILURE)
        }

        let service = AccessibilityService()
        guard service.requestTrustIfNeeded() else {
            fputs("maclick: accessibility permission not granted\n", stderr)
            exit(EXIT_FAILURE)
        }

        guard let windowTarget = resolveWindowTarget(query: targetQuery, service: service) else {
            fputs("maclick: could not find a running window matching '\(targetQuery)'\n", stderr)
            exit(EXIT_FAILURE)
        }

        let hints = service.hintTargets(for: windowTarget)
        guard !hints.isEmpty else {
            fputs("maclick: no actionable targets found for \(windowTarget.title)\n", stderr)
            exit(EXIT_FAILURE)
        }

        if arguments.count == 2 && arguments[1] == "--help" {
            printHints(windowTarget: windowTarget, hints: hints)
            return
        }

        if arguments.count == 2 && arguments[1] == "--recenter" {
            recenter(windowTarget: windowTarget, service: service)
            return
        }

        if arguments.count == 2 {
            click(label: arguments[1], windowTarget: windowTarget, hints: hints, service: service)
            return
        }

        if arguments.count == 3 && arguments[2].lowercased() == "hover" {
            hover(label: arguments[1], windowTarget: windowTarget, hints: hints)
            return
        }

        if arguments.count >= 2 && arguments[1].lowercased() == "screenshot" {
            screenshot(windowTarget: windowTarget, hints: hints, outputPath: arguments.count >= 3 ? arguments[2] : nil)
            return
        }

        if arguments.count == 4 && arguments[2].lowercased() == "to" {
            drag(from: arguments[1], to: arguments[3], windowTarget: windowTarget, hints: hints)
            return
        }

        printUsage()
        exit(EXIT_FAILURE)
    }

    private static func click(
        label: String,
        windowTarget: WindowTarget,
        hints: [HintTarget],
        service: AccessibilityService
    ) {
        guard let target = hint(matching: label, in: hints) else {
            fputs("maclick: unknown hint '\(label)'\n", stderr)
            exit(EXIT_FAILURE)
        }

        activate(windowTarget.application)
        let didActivate = service.activate(target)
        if !didActivate {
            fputs("maclick: failed to activate \(target.label) (\(target.description))\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("maclick: activated \(target.label) -> \(target.description)")
    }

    private static func drag(
        from sourceLabel: String,
        to destinationLabel: String,
        windowTarget: WindowTarget,
        hints: [HintTarget]
    ) {
        guard let source = hint(matching: sourceLabel, in: hints) else {
            fputs("maclick: unknown source hint '\(sourceLabel)'\n", stderr)
            exit(EXIT_FAILURE)
        }
        guard let destination = hint(matching: destinationLabel, in: hints) else {
            fputs("maclick: unknown destination hint '\(destinationLabel)'\n", stderr)
            exit(EXIT_FAILURE)
        }

        activate(windowTarget.application)
        let didCompleteMove = PointerAutomation.drag(
            from: source.frame.center,
            to: destination.frame.center,
            pid: windowTarget.application.processIdentifier
        )

        if !didCompleteMove {
            fputs("maclick: failed to drag \(source.label) to \(destination.label)\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("maclick: dragged \(source.label) -> \(destination.label)")
    }

    private static func hover(label: String, windowTarget: WindowTarget, hints: [HintTarget]) {
        guard let target = hint(matching: label, in: hints) else {
            fputs("maclick: unknown hint '\(label)'\n", stderr)
            exit(EXIT_FAILURE)
        }

        activate(windowTarget.application)
        let point = target.frame.center
        let didMove = PointerAutomation.move(
            to: point,
            pid: windowTarget.application.processIdentifier
        )
        if !didMove {
            fputs("maclick: failed to move to \(target.label)\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("maclick: hovered \(target.label) -> \(target.description)")
    }

    private static func screenshot(windowTarget: WindowTarget, hints: [HintTarget], outputPath: String?) {
        let destination = outputURL(for: outputPath, title: windowTarget.title)
        let didCapture = HintScreenshotRenderer.capture(
            windowTarget: windowTarget,
            hints: hints,
            to: destination
        )

        if !didCapture {
            fputs("maclick: failed to capture screenshot for \(windowTarget.title)\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("maclick: screenshot \(destination.path)")
    }

    private static func openApplication(_ arguments: ArraySlice<String>) {
        let rawTarget = arguments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTarget.isEmpty else {
            fputs("maclick: missing application name or .app path\n", stderr)
            exit(EXIT_FAILURE)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if rawTarget.contains("/") {
            process.arguments = [rawTarget]
        } else {
            process.arguments = ["-a", rawTarget]
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fputs("maclick: failed to open \(rawTarget): \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }

        if process.terminationStatus != 0 {
            fputs("maclick: open failed for \(rawTarget)\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("maclick: opened \(rawTarget)")
    }

    private static func printHints(windowTarget: WindowTarget, hints: [HintTarget]) {
        let debugFrames = ProcessInfo.processInfo.environment["MACLICK_DEBUG"] == "1"
        print(
            "maclick: showing \(hints.count) hints for " +
            "\(windowTarget.application.localizedName ?? "unknown app") | \(windowTarget.title)"
        )
        for hint in hints {
            if debugFrames {
                let frame = hint.frame
                print(
                    "maclick: hint \(hint.label) -> \(hint.description) @ " +
                    "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))"
                )
            } else {
                print("maclick: hint \(hint.label) -> \(hint.description)")
            }
        }
    }

    private static func recenter(windowTarget: WindowTarget, service: AccessibilityService) {
        let origin = CGPoint(x: 80, y: 80)
        guard service.moveWindow(windowTarget, to: origin) else {
            fputs("maclick: failed to recenter \(windowTarget.title)\n", stderr)
            exit(EXIT_FAILURE)
        }

        activate(windowTarget.application)
        print("maclick: recentered \(windowTarget.title)")
    }

    private static func resolveWindowTarget(query: String, service: AccessibilityService) -> WindowTarget? {
        let normalizedQuery = query
            .replacingOccurrences(of: ".app", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy != .prohibited else {
                return false
            }

            let candidates = [
                app.localizedName?.lowercased(),
                app.bundleIdentifier?.lowercased(),
            ].compactMap { $0 }

            if candidates.contains(where: { $0 == normalizedQuery || $0.contains(normalizedQuery) }) {
                return true
            }

            let windows = service.windowTargets(for: app)
            return windows.contains { target in
                target.title.lowercased().contains(normalizedQuery)
            }
        }.sorted { lhs, rhs in
            (lhs.isActive ? 0 : 1) < (rhs.isActive ? 0 : 1)
        }

        var matches: [WindowTarget] = []
        for app in runningApps {
            let targets = service.windowTargets(for: app)
            let exactTitleMatches = targets.filter {
                $0.title.lowercased() == normalizedQuery
            }
            if !exactTitleMatches.isEmpty {
                matches.append(contentsOf: exactTitleMatches)
                continue
            }

            let partialTitleMatches = targets.filter {
                $0.title.lowercased().contains(normalizedQuery)
            }
            if !partialTitleMatches.isEmpty {
                matches.append(contentsOf: partialTitleMatches)
                continue
            }

            let appMatches = [app.localizedName?.lowercased(), app.bundleIdentifier?.lowercased()]
                .compactMap { $0 }
                .contains { $0 == normalizedQuery || $0.contains(normalizedQuery) }
            if appMatches, let focused = targets.first(where: \.isFocused) ?? targets.first {
                matches.append(focused)
            }
        }

        return matches.sorted { lhs, rhs in
            if lhs.isFocused != rhs.isFocused {
                return lhs.isFocused && !rhs.isFocused
            }

            if lhs.application.isActive != rhs.application.isActive {
                return lhs.application.isActive && !rhs.application.isActive
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }.first
    }

    private static func hint(matching label: String, in hints: [HintTarget]) -> HintTarget? {
        let normalized = label.uppercased()
        return hints.first(where: { $0.label == normalized })
    }

    private static func outputURL(for outputPath: String?, title: String) -> URL {
        if let outputPath, !outputPath.isEmpty {
            return URL(fileURLWithPath: outputPath)
        }

        let slug = title
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" {
                    return
                }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let filename = slug.isEmpty ? "maclick-window" : slug
        return URL(fileURLWithPath: "/tmp/\(filename)-hints.png")
    }

    private static func activate(_ application: NSRunningApplication) {
        _ = application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        Thread.sleep(forTimeInterval: 0.18)
    }

    private static func printUsage() {
        let usage = """
        Usage:
          maclick open <AppName|/path/to/App.app>
          maclick <window> --help
          maclick <window> --recenter
          maclick <window> screenshot [output.png]
          maclick <window> <hint>
          maclick <window> <hint> hover
          maclick <window> <from_hint> to <to_hint>
        """
        print(usage)
    }
}

@MainActor
private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

MacClickCLI.main()
