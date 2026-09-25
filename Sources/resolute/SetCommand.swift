import ArgumentParser
import Foundation
import ResoluteKit

struct SetCommand: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Switch a display to another mode.",
        discussion: """
            Examples:
              resolute set 1496x967          keep the refresh rate, pick the resolution
              resolute set 1920x1200@1x      a low-resolution (1×) mode
              resolute set --refresh 60      keep the resolution, change the refresh rate
              resolute set --mode-id 55      an exact mode from `resolute modes --raw`
              resolute set --default         the display's default mode
            """
    )

    @Argument(help: "WIDTHxHEIGHT in points, optionally followed by @2x or @1x and @<Hz>.")
    var resolution: String?

    @OptionGroup var target: DisplayOptions

    // Read as text, so that only plain decimal numbers count: "0x3c" is not 60 Hz.
    @Option(help: "2 for HiDPI, 1 for low resolution.")
    var scale: String?

    @Option(help: "Refresh rate in Hz, for example 60 or 59.94.")
    var refresh: String?

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
        if let refresh, !(ModeQuery.decimal(refresh).map(ModeQuery.isPlausible(refreshRate:)) ?? false) {
            throw ValidationError("--refresh takes a rate in hertz, for example 60 or 59.94.")
        }
        if let scale, !(ModeQuery.decimal(scale).map(ModeQuery.isPlausible(scale:)) ?? false) {
            throw ValidationError("--scale takes 2 for HiDPI or 1 for low resolution.")
        }
        if modeID != nil, resolution != nil || scale != nil || refresh != nil || useDefault {
            throw ValidationError("--mode-id names one exact mode; leave out the resolution, --scale, --refresh and --default.")
        }
        if useDefault, resolution != nil || scale != nil || refresh != nil {
            throw ValidationError("--default picks the display's default mode; leave out the resolution, --scale and --refresh.")
        }
        // Only something shaped like a size is checked here: a bare word or number is more
        // likely the value of a mistyped option, which ArgumentParser reports after this.
        if let resolution, Output.looksLikeSize(resolution) {
            let parsed: ModeQuery
            do {
                parsed = try ModeQuery(resolution: resolution)
            } catch {
                throw ValidationError(error.localizedDescription)
            }
            if parsed.scale != nil, scale != nil {
                throw ValidationError("Give the scale once, either as @2x or @1x in the resolution or with --scale.")
            }
            if parsed.refreshRate != nil, refresh != nil {
                throw ValidationError("Give the refresh rate once, either as @60 in the resolution or with --refresh.")
            }
        }
    }

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        // Checked here rather than in validate(): ArgumentParser validates before it
        // reports unknown options, so this message would hide a mistyped one.
        guard resolution != nil || scale != nil || refresh != nil || modeID != nil || useDefault else {
            throw ResoluteError.usage("Give a resolution, --refresh, --scale, --mode-id or --default.")
        }
        let service = context.service
        let display = try target.resolve(in: service.displays())
        var query: ModeQuery
        do {
            query = try resolution.map { try ModeQuery(resolution: $0) } ?? ModeQuery()
        } catch ResoluteError.invalidResolution(let text) {
            if refresh == nil, let rate = ModeQuery.decimal(text), ModeQuery.isPlausible(refreshRate: rate), rate <= 1_000 {
                throw ResoluteError.usage("“\(text)” is not a resolution. To change only the refresh rate, use --refresh \(text).")
            }
            throw ResoluteError.usage(ResoluteError.invalidResolution(text).localizedDescription)
        } catch let error as ResoluteError {
            throw ResoluteError.usage(error.localizedDescription)
        }
        if let scale = scale.flatMap(ModeQuery.decimal) { query.scale = scale }
        if let refresh = refresh.flatMap(ModeQuery.decimal) { query.refreshRate = refresh }
        query.modeID = modeID
        query.useDefault = useDefault
        query.allowHidden = allowHidden

        let mode = try query.resolve(on: display)
        guard mode.modeID != display.currentModeID else {
            context.write("\(display.name) is already at \(Output.describe(mode)).")
            return
        }
        guard !dryRun else {
            context.write("Would switch \(display.name) to \(Output.describe(mode)).")
            return
        }
        // Hidden modes are tried for the session and kept only when confirmed; --session
        // only limits how long a confirmed mode lasts.
        let trial = session || mode.origin == .hidden
        let switcher = ModeSwitcher(service: service)
        let outcome = try switcher.apply(modeID: mode.modeID, to: display.id, trial: trial) {
            guard mode.origin == .hidden else { return .keepForSession }
            let decision = context.confirmHiddenMode()
            return session && decision == .keep ? .keepForSession : decision
        }
        switch outcome {
        case .alreadyCurrent:
            context.write("\(display.name) is already at \(Output.describe(mode)).")
        case .applied, .kept, .keptForSession:
            // The full snapshot, since CoreGraphics may not name a hidden mode in use.
            guard switcher.currentModeID(of: display.id) == mode.modeID else {
                context.writeError("warning: macOS accepted the change but reports a different mode now.")
                return
            }
            let until = outcome == .keptForSession ? " (until you log out)" : ""
            context.write("\(display.name): \(Output.describe(mode))\(until)")
        case .reverted(let modeID):
            let restored = display.modes.first { $0.modeID == modeID }
            context.write("Kept the previous mode: \(restored.map(Output.describe) ?? "mode \(modeID)").")
        }
    }

    /// Asks in the terminal whether to keep a hidden mode. Without a terminal the mode
    /// stays until the user logs out.
    static func askToKeep(seconds: Int = 15) -> ModeSwitcher.Decision {
        guard isatty(STDIN_FILENO) != 0 else {
            FileHandle.standardError.write(Data("note: no terminal to confirm in, so this mode lasts until you log out.\n".utf8))
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
