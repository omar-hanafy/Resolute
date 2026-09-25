import ArgumentParser
import Foundation
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

/// What a command talks to. `live` is the real system; tests pass their own.
struct CommandContext: Sendable {
    var service: any DisplayControlling
    var write: @Sendable (String) -> Void
    var writeError: @Sendable (String) -> Void
    /// Asks whether to keep a hidden mode that is on trial.
    var confirmHiddenMode: @Sendable () -> ModeSwitcher.Decision
    /// Writing to /Library needs root.
    var isRoot: Bool

    static var live: CommandContext {
        CommandContext(
            service: SystemDisplayService(),
            write: { print($0) },
            writeError: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
            confirmHiddenMode: { SetCommand.askToKeep() },
            isRoot: geteuid() == 0
        )
    }
}

/// A command that runs against a `CommandContext`.
protocol ContextCommand {
    func run(in context: CommandContext) async throws
}

/// Chooses a display.
struct DisplayOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "main, an index from `resolute displays`, id:<number>, or part of the display's name.")
    var display = "main"

    func resolve(in displays: [Display]) throws -> Display {
        try DisplaySelector(display).resolve(in: displays)
    }
}
