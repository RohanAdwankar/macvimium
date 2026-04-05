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

        switch arguments[0].lowercased() {
        case "open":
            openApplication(arguments.dropFirst())
        default:
            handleWindowCommand(arguments)
        }
    }

    private static func handleWindowCommand(_ arguments: [String]) {
        guard let windowQuery = arguments.first else {
            printUsage()
            exit(EXIT_FAILURE)
        }

        guard let app = resolveApplication(query: windowQuery) else {
            fputs("maclick: could not find a running app matching '\(windowQuery)'\n", stderr)
            exit(EXIT_FAILURE)
        }

        let service = AccessibilityService()
        guard service.requestTrustIfNeeded() else {
            fputs("maclick: accessibility permission not granted\n", stderr)
            exit(EXIT_FAILURE)
        }

        let hints = service.hintTargets(for: app)
        guard !hints.isEmpty else {
            fputs("maclick: no actionable targets found for \(app.localizedName ?? windowQuery)\n", stderr)
            exit(EXIT_FAILURE)
        }

        if arguments.count == 2 && arguments[1] == "--help" {
            printHints(app: app, hints: hints)
            return
        }

        if arguments.count == 2 && arguments[1] == "--recenter" {
            recenter(app: app, service: service)
            return
        }

        if arguments.count == 2 {
            click(label: arguments[1], app: app, hints: hints, service: service)
            return
        }

        if arguments.count == 3 && arguments[2].lowercased() == "hover" {
            hover(label: arguments[1], app: app, hints: hints)
            return
        }

        if arguments.count == 4 && arguments[2].lowercased() == "to" {
            drag(from: arguments[1], to: arguments[3], app: app, hints: hints)
            return
        }

        printUsage()
        exit(EXIT_FAILURE)
    }

    private static func click(label: String, app: NSRunningApplication, hints: [HintTarget], service: AccessibilityService) {
        guard let target = hint(matching: label, in: hints) else {
            fputs("maclick: unknown hint '\(label)'\n", stderr)
            exit(EXIT_FAILURE)
        }

        app.activate()
        Thread.sleep(forTimeInterval: 0.08)
        let didActivate: Bool
        if app.bundleIdentifier == "com.apple.Chess" {
            didActivate = PointerAutomation.click(at: interactionPoint(for: target))
        } else {
            didActivate = service.activate(target)
        }
        if !didActivate {
            fputs("maclick: failed to activate \(target.label) (\(target.description))\n", stderr)
            exit(EXIT_FAILURE)
        }
        print("maclick: activated \(target.label) -> \(target.description)")
    }

    private static func drag(from sourceLabel: String, to destinationLabel: String, app: NSRunningApplication, hints: [HintTarget]) {
        guard let source = hint(matching: sourceLabel, in: hints) else {
            fputs("maclick: unknown source hint '\(sourceLabel)'\n", stderr)
            exit(EXIT_FAILURE)
        }
        guard let destination = hint(matching: destinationLabel, in: hints) else {
            fputs("maclick: unknown destination hint '\(destinationLabel)'\n", stderr)
            exit(EXIT_FAILURE)
        }

        app.activate()
        Thread.sleep(forTimeInterval: 0.08)
        let didCompleteMove: Bool
        if app.bundleIdentifier == "com.apple.Chess" && ProcessInfo.processInfo.environment["MACLICK_FORCE_DRAG"] == "1" {
            didCompleteMove = PointerAutomation.drag(
                from: interactionPoint(for: source),
                to: interactionPoint(for: destination),
                steps: 40
            )
        } else if app.bundleIdentifier == "com.apple.Chess" {
            didCompleteMove =
                PointerAutomation.click(at: interactionPoint(for: source)) &&
                { Thread.sleep(forTimeInterval: 0.12); return true }() &&
                PointerAutomation.click(at: interactionPoint(for: destination))
        } else {
            didCompleteMove = PointerAutomation.drag(from: source.frame.center, to: destination.frame.center)
        }

        if !didCompleteMove {
            fputs("maclick: failed to drag \(source.label) to \(destination.label)\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("maclick: dragged \(source.label) -> \(destination.label)")
    }

    private static func hover(label: String, app: NSRunningApplication, hints: [HintTarget]) {
        guard let target = hint(matching: label, in: hints) else {
            fputs("maclick: unknown hint '\(label)'\n", stderr)
            exit(EXIT_FAILURE)
        }

        app.activate()
        Thread.sleep(forTimeInterval: 0.08)
        let didMove = PointerAutomation.move(to: interactionPoint(for: target))
        if !didMove {
            fputs("maclick: failed to move to \(target.label)\n", stderr)
            exit(EXIT_FAILURE)
        }

        print("maclick: hovered \(target.label) -> \(target.description)")
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

    private static func printHints(app: NSRunningApplication, hints: [HintTarget]) {
        let debugFrames = ProcessInfo.processInfo.environment["MACLICK_DEBUG"] == "1"
        print("maclick: showing \(hints.count) hints for \(app.localizedName ?? "unknown app")")
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

    private static func recenter(app: NSRunningApplication, service: AccessibilityService) {
        let origin = CGPoint(x: 80, y: 80)
        guard service.moveFocusedWindow(of: app, to: origin) else {
            fputs("maclick: failed to recenter \(app.localizedName ?? "app")\n", stderr)
            exit(EXIT_FAILURE)
        }

        app.activate()
        print("maclick: recentered \(app.localizedName ?? "app")")
    }

    private static func resolveApplication(query: String) -> NSRunningApplication? {
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

            return candidates.contains(where: { $0 == normalizedQuery || $0.contains(normalizedQuery) })
        }

        return runningApps.sorted { lhs, rhs in
            (lhs.isActive ? 0 : 1) < (rhs.isActive ? 0 : 1)
        }.first
    }

    private static func hint(matching label: String, in hints: [HintTarget]) -> HintTarget? {
        let normalized = label.uppercased()
        return hints.first(where: { $0.label == normalized })
    }

    private static func interactionPoint(for target: HintTarget) -> CGPoint {
        guard target.bundleIdentifier == "com.apple.Chess",
              let square = boardSquare(in: target.description),
              let rank = Int(String(square.last!)) else {
            return target.frame.center
        }

        let upwardOffset = CGFloat((9 - rank) * 8)
        return CGPoint(x: target.frame.midX, y: target.frame.midY + upwardOffset)
    }

    private static func boardSquare(in description: String) -> String? {
        let pattern = #"[a-h][1-8]"#
        guard let range = description.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(description[range])
    }

    private static func printUsage() {
        let usage = """
        Usage:
          maclick open <AppName|/path/to/App.app>
          maclick <window> --help
          maclick <window> --recenter
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
