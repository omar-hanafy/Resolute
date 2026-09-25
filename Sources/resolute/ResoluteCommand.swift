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
            DisplaysCommand.self, ModesCommand.self, SetCommand.self, MirrorCommand.self, OverridesCommand.self, DoctorCommand.self,
        ],
        defaultSubcommand: DisplaysCommand.self
    )

    static let commands = ["displays", "modes", "set", "mirror", "overrides", "doctor"]
    static let overridesCommands = ["list", "show", "add", "remove", "reset", "backups", "restore", "prune"]

    static func main() async {
        let result = await execute(Array(CommandLine.arguments.dropFirst()), in: .live)
        if let message = result.message, !message.isEmpty {
            if result.code == 0 {
                print(message)
            } else {
                FileHandle.standardError.write(Data((message + "\n").utf8))
            }
        }
        Foundation.exit(result.code)
    }

    /// Parses and runs `arguments` against `context`; returns what to print besides the
    /// command's own output, and the exit code. `main` and the tests both use it.
    static func execute(_ arguments: [String], in context: CommandContext) async -> (message: String?, code: Int32) {
        // A mistyped command is caught first: `displays`, the default, would only report
        // an unexpected argument.
        if let problem = unknownCommandMessage(for: arguments) {
            return ("Error: \(problem)", ExitCode.validationFailure.rawValue)
        }
        let command: ParsableCommand
        do {
            command = try parseAsRoot(arguments)
        } catch {
            return (fullMessage(for: error), exitCode(for: error).rawValue)
        }
        do {
            if let runnable = command as? any ContextCommand {
                try await runnable.run(in: context)
            } else {
                var command = command
                try command.run()
            }
            return (nil, 0)
        } catch ResoluteError.usage(let message) {
            return (usageMessage(message, for: type(of: command)), ExitCode.validationFailure.rawValue)
        } catch {
            return (fullMessage(for: error), exitCode(for: error).rawValue)
        }
    }

    /// A mistake found while running, shown like ArgumentParser shows one found while
    /// parsing: with the command's usage. (A `ValidationError` thrown from `run` would show
    /// the usage of `resolute` itself.)
    static func usageMessage(_ message: String, for command: ParsableCommand.Type) -> String {
        let usage = usageString(for: command)
        let path = usage.split(separator: " ").dropFirst().prefix { $0.first?.isLetter == true }.joined(separator: " ")
        return "Error: \(message)\nUsage: \(usage)\n  See 'resolute \(path) --help' for more information."
    }

    static func unknownCommandMessage(for arguments: [String]) -> String? {
        guard let first = arguments.first, !first.hasPrefix("-") else { return nil }
        if first == "help" {
            // "resolute help mode" would print the root help and succeed.
            guard arguments.count > 1, !arguments[1].hasPrefix("-"), !commands.contains(arguments[1]) else { return nil }
            let word = arguments[1]
            let suggestion = commands.first { isTypo(word.lowercased(), of: $0) }
            return "“\(word)” is not a resolute command." + (suggestion.map { " Did you mean “resolute help \($0)”?" } ?? "")
        }
        if first == "overrides" {
            // "resolute overrides ad …" would reach `list`, the default, as extra arguments.
            guard arguments.count > 1, !arguments[1].hasPrefix("-"), !overridesCommands.contains(arguments[1]) else {
                return nil
            }
            let word = arguments[1]
            let problem = "“\(word)” is not an overrides command."
            if word == "help" {
                return problem + " Did you mean “resolute help overrides”?"
            }
            if let command = overridesCommands.first(where: { isTypo(word.lowercased(), of: $0) }) {
                return problem + " Did you mean “resolute overrides \(command)”?"
            }
            return problem + " The overrides commands are "
                + overridesCommands.dropLast().joined(separator: ", ") + " and " + (overridesCommands.last ?? "") + "."
        }
        guard !commands.contains(first) else { return nil }
        let problem = "“\(first)” is not a resolute command."
        if first.lowercased() == "version" {
            return problem + " Did you mean “resolute --version”?"
        }
        // Checked before typos: "reset" is one letter from "set", which changes the screen.
        if overridesCommands.contains(first.lowercased()) {
            return problem + " Did you mean “resolute overrides \(first.lowercased())”?"
        }
        if let command = commands.first(where: { isTypo(first.lowercased(), of: $0) }) {
            return problem + " Did you mean “resolute \(command)”?"
        }
        if Output.looksLikeSize(first), (try? ModeQuery(resolution: first)) != nil {
            return problem + " To switch to that resolution, run “resolute set \(first)”."
        }
        return problem + " The commands are " + commands.dropLast().joined(separator: ", ") + " and " + (commands.last ?? "") + "."
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
    /// How long `set` waits for a display that went away during a trial to come back, and
    /// how often it looks, in seconds.
    var restoreTimeout: TimeInterval = 30
    var restorePollInterval: TimeInterval = 0.5

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
