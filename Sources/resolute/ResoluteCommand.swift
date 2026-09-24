import ArgumentParser
import ResoluteKit

@main
struct ResoluteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolute",
        abstract: "List and switch display modes, including the ones macOS hides.",
        version: ResoluteVersion.string,
        subcommands: [
            DisplaysCommand.self, ModesCommand.self, SetCommand.self, MirrorCommand.self, OverridesCommand.self,
        ],
        defaultSubcommand: DisplaysCommand.self
    )
}

/// Chooses a display.
struct DisplayOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "main, an index from `resolute displays`, id:<number>, or part of the display's name.")
    var display = "main"

    func resolve(in displays: [Display]) throws -> Display {
        try DisplaySelector(display).resolve(in: displays)
    }
}
