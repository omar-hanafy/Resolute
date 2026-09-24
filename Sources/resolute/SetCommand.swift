import ArgumentParser
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

    @Flag(help: "Allow hidden modes that macOS does not list.")
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
        try service.apply(modeID: mode.modeID, to: display.id, scope: session ? .session : .permanent)
        if service.currentModeID(of: display.id) == mode.modeID {
            print("\(display.name): \(Output.describe(mode))")
        } else {
            Output.printError("warning: macOS accepted the change but reports a different mode now.")
        }
    }
}
