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

    static let commands = ["displays", "modes", "set", "mirror", "overrides"]

    /// Catches a mistyped command first: `displays`, the default, would only report an
    /// unexpected argument.
    static func main() async {
        if let message = unknownCommandMessage(for: Array(CommandLine.arguments.dropFirst())) {
            FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
            Foundation.exit(ExitCode.validationFailure.rawValue)
        }
        await main(nil)
    }

    static func unknownCommandMessage(for arguments: [String]) -> String? {
        guard let word = arguments.first, !word.hasPrefix("-"), word != "help", !commands.contains(word) else {
            return nil
        }
        let problem = "“\(word)” is not a resolute command."
        if word.lowercased() == "version" {
            return problem + " Did you mean “resolute --version”?"
        }
        if let command = commands.first(where: { isTypo(word.lowercased(), of: $0) }) {
            return problem + " Did you mean “resolute \(command)”?"
        }
        if Output.looksLikeSize(word), (try? ModeQuery(resolution: word)) != nil {
            return problem + " To switch to that resolution, run “resolute set \(word)”."
        }
        return problem + " The commands are displays, modes, set, mirror and overrides."
    }

    /// Close enough to `command` to be a slip: a prefix of three or more letters, or at
    /// most two letters wrong.
    static func isTypo(_ word: String, of command: String) -> Bool {
        if word.count >= 3, command.hasPrefix(word) || word.hasPrefix(command) { return true }
        return editDistance(word, command) <= 2
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs), right = Array(rhs)
        guard !left.isEmpty, !right.isEmpty else { return max(left.count, right.count) }
        var previous = Array(0...right.count)
        for i in 1...left.count {
            var current = [i] + Array(repeating: 0, count: right.count)
            for j in 1...right.count {
                let substitution = previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return previous[right.count]
    }
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
