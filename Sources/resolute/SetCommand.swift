import ArgumentParser
import Foundation
import ResoluteKit

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Switch a display to another mode.",
        discussion: """
            Examples:
              resolute set 1512x982          keep the refresh rate, pick the resolution
              resolute set 1920x1200@1x      a low-resolution (1×) mode
              resolute set --refresh 60      keep the resolution, change the refresh rate
              resolute set --mode-id 55      an exact mode from `resolute modes --raw`
              resolute set --default         the display's default mode
            """
    )

    @Argument(help: "WIDTHxHEIGHT in points, optionally followed by @2x or @1x and @<Hz>.")
    var resolution: String?

    @OptionGroup var target: DisplayOptions

    @Option(help: "2 for HiDPI, 1 for low resolution.")
    var scale: Double?

    @Option(help: "Refresh rate in Hz.")
    var refresh: Double?

    @Option(name: .customLong("mode-id"), help: "An exact mode ID.")
    var modeID: Int32?

    @Flag(name: .customLong("default"), help: "Switch to the display's default mode.")
    var useDefault = false

    @Flag(help: "Change the mode until you log out instead of permanently.")
    var session = false

    @Flag(help: ArgumentHelp(
        "Allow hidden modes that macOS does not list.",
        discussion: "A hidden mode is tried until you log out. In a terminal you then have 15 seconds to type y to keep it; otherwise the previous mode comes back."
    ))
    var allowHidden = false

    @Flag(help: "Show what would change without changing it.")
    var dryRun = false

    func validate() throws {
        if resolution == nil && scale == nil && refresh == nil && modeID == nil && !useDefault {
            throw ValidationError("Give a resolution, --refresh, --scale, --mode-id or --default.")
        }
    }

    func run() throws {
        let service = SystemDisplayService()
        let display = try target.resolve(in: service.displays())
        var query = try resolution.map { try ModeQuery(resolution: $0) } ?? ModeQuery()
        if let scale { query.scale = scale }
        if let refresh { query.refreshRate = refresh }
        query.modeID = modeID
        query.useDefault = useDefault
        query.allowHidden = allowHidden

        let mode = try query.resolve(on: display)
        guard mode.modeID != display.currentModeID else {
            print("\(display.name) is already at \(Output.describe(mode)).")
            return
        }
        guard !dryRun else {
            print("Would switch \(display.name) to \(Output.describe(mode)).")
            return
        }
        // Hidden modes are tried for the session and kept only when confirmed.
        let trial = session || mode.origin == .hidden
        let outcome = try ModeSwitcher(service: service).apply(modeID: mode.modeID, to: display.id, trial: trial) {
            session ? .keepForSession : Self.askToKeep()
        }
        switch outcome {
        case .alreadyCurrent:
            print("\(display.name) is already at \(Output.describe(mode)).")
        case .applied, .kept, .keptForSession:
            guard service.currentModeID(of: display.id) == mode.modeID else {
                Output.printError("warning: macOS accepted the change but reports a different mode now.")
                return
            }
            let until = outcome == .keptForSession ? " (until you log out)" : ""
            print("\(display.name): \(Output.describe(mode))\(until)")
        case .reverted(let modeID):
            let restored = display.modes.first { $0.modeID == modeID }
            print("Kept the previous mode: \(restored.map(Output.describe) ?? "mode \(modeID)").")
        }
    }

    /// Asks in the terminal whether to keep a hidden mode. Without a terminal the mode
    /// stays until the user logs out.
    static func askToKeep(seconds: Int = 15) -> ModeSwitcher.Decision {
        guard isatty(STDIN_FILENO) != 0 else {
            Output.printError("note: no terminal to confirm in, so this mode lasts until you log out.")
            return .keepForSession
        }
        let prompt = "Keep this display mode? Type y and press Return within \(seconds) seconds; anything else reverts: "
        FileHandle.standardOutput.write(Data(prompt.utf8))
        var input = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard poll(&input, 1, Int32(seconds * 1_000)) > 0, let answer = readLine() else {
            print("")
            return .revert
        }
        return answer.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("y") ? .keep : .revert
    }
}
