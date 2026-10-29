import ArgumentParser
import Foundation
import ResoluteKit

/// `resolute preset`: remember the mode of every display, and switch them all back in one go.
struct PresetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preset",
        abstract: "Save the mode of every display as a preset, and apply it again.",
        discussion: """
            A preset remembers the mode of every display, and whether they mirror. Apply one from the panel, \
            the Dock, its shortcut, or resolute preset apply <name>. Presets use only modes \
            macOS lists, so applying one needs no Keep or Revert. Names ignore case.

            Examples:
              resolute preset save Coding     remember the mode of every display
              resolute preset apply Coding    switch every display back to it
              resolute preset list            * marks presets the current setup matches
            """,
        subcommands: [
            ListPresets.self, ShowPreset.self, SavePreset.self, ApplyPreset.self, DeletePreset.self, RenamePreset.self,
        ],
        defaultSubcommand: ListPresets.self
    )

    /// The names of `resolute preset`'s commands.
    static var commandNames: [String] {
        configuration.subcommands.compactMap { $0.configuration.commandName }
    }

    /// Words people reach for, and the command they mean.
    static let synonyms = [
        "add": "save", "new": "save", "create": "save", "use": "apply", "load": "apply", "switch": "apply",
        "remove": "delete", "rm": "delete", "ls": "list", "mv": "rename",
    ]

    /// Why `word`, typed after `resolute preset`, is not one of its commands; nil for a
    /// command or an option. `list`, the default, would otherwise report the word only as an
    /// unexpected argument. Used by `ResoluteCommand.unknownCommandMessage(for:)`.
    static func unknownCommandMessage(for word: String) -> String? {
        guard !word.hasPrefix("-"), !commandNames.contains(word) else { return nil }
        let problem = "“\(word)” is not a preset command."
        if word == "help" {
            return problem + " Did you mean “resolute help preset”?"
        }
        let lowercased = word.lowercased()
        if let command = synonyms[lowercased] ?? commandNames.first(where: { ResoluteCommand.isTypo(lowercased, of: $0) }) {
            return problem + " Did you mean “resolute preset \(command)”?"
        }
        return problem + " To apply a preset by that name, run “resolute preset apply \(Output.shellWord(word))”."
    }

    /// Changing presets as root would leave the person's presets file to the administrator.
    static func refuseRoot(_ command: String, in context: CommandContext) throws {
        guard context.isRoot else { return }
        throw ResoluteError.invalidEntry("Presets belong to you, not the administrator: run resolute preset \(command) without sudo.")
    }

    /// The preset named `name`, or an error that says what to do instead.
    static func preset(named name: String, in library: PresetLibrary) throws -> Preset {
        do {
            return try library.find(named: name)
        } catch PresetError.notFound(_, let suggestions) where suggestions.isEmpty {
            guard !library.presets.isEmpty else {
                throw ResoluteError.invalidEntry(
                    "There is no preset named “\(name)”: there are no presets yet. "
                        + "To save the current setup as one: resolute preset save \(Output.shellWord(name))"
                )
            }
            throw ResoluteError.invalidEntry("There is no preset named “\(name)”. List them with `resolute preset list`.")
        }
    }
}

extension CommandContext {
    /// The presets the app and the command share, in this context's support folder.
    var presetStore: PresetStore {
        PresetStore(locations: support)
    }
}

struct ListPresets: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List presets.",
        discussion: "* marks presets the current setup matches."
    )

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let store = context.presetStore
        let library = try store.load()
        for problem in library.problems {
            let name = problem.name.map { " (“\($0)”)" } ?? ""
            context.writeError(
                "warning: preset \(problem.index + 1)\(name) in \(store.file.path(percentEncoded: false)) "
                    + "can’t be read, so it is left out: \(problem.reason)."
            )
        }
        let displays = context.service.displays()
        let plans = library.presets.map { ($0, $0.plan(for: displays)) }
        if json {
            context.write(try Output.json(plans.map { PresetReport($0.0, plan: $0.1) }))
            return
        }
        guard !plans.isEmpty else {
            context.write("There are no presets yet. To save the current setup as one: resolute preset save <name>")
            return
        }
        let hasShortcuts = plans.contains { $0.0.shortcut != nil }
        context.write(Output.table(plans.map { preset, plan in
            [plan.isActive ? "*" : " ", preset.name] + (hasShortcuts ? [preset.shortcut?.displayText ?? ""] : []) + [preset.summary]
        }))
    }
}

struct ShowPreset: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a preset and what applying it would change."
    )

    @Argument(help: "The preset's name; case doesn't matter.")
    var name: String

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let preset = try PresetCommand.preset(named: name, in: try context.presetStore.load())
        let plan = preset.plan(for: context.service.displays())
        if json {
            context.write(try Output.json(PresetReport(preset, plan: plan)))
            return
        }
        context.write(preset.name + (preset.shortcut.map { " (\($0.displayText))" } ?? ""))
        for step in plan.steps {
            context.write("  " + Self.describe(step))
        }
        if let line = Self.describe(plan.mirroring) {
            context.write("  " + line)
        }
        context.write(Self.verdict(plan))
    }

    /// "Built-in Retina Display: 1496 × 967 HiDPI (2992 × 1934 px) @ 120 Hz, mode 42 (in use)"
    static func describe(_ step: PresetPlan.Step) -> String {
        switch (step.status, step.mode) {
        case (.inUse, let mode?):
            "\(step.displayName): \(Output.describe(mode)) (in use)"
        case (.switches, let mode?):
            "\(step.displayName): \(Output.describe(mode))"
        case (.skipped(let problem), _):
            "\(step.displayName): \(step.setting.modeText) (skipped: \(problem.reason(for: step.setting)))"
        case (_, nil):
            "\(step.displayName): \(step.setting.modeText)"
        }
    }

    static func describe(_ mirroring: PresetPlan.Mirroring) -> String? {
        switch mirroring {
        case .leftAlone: nil
        case .inUse(let on): "Mirroring: \(on ? "on" : "off") (in use)"
        case .turns(let on): "Mirroring: \(on ? "on" : "off")"
        case .notPossible: "Mirroring: on (skipped: it needs at least two displays)"
        }
    }

    /// The last line: whether the setup matches, else what applying would change.
    static func verdict(_ plan: PresetPlan) -> String {
        guard !plan.isActive else { return "The current setup matches it." }
        var changes: [String] = []
        if case .turns(let on) = plan.mirroring { changes.append("turn mirroring \(on ? "on" : "off")") }
        let switching = plan.steps.filter { $0.status == .switches }.count
        if switching > 0 { changes.append("switch \(switching) display\(switching == 1 ? "" : "s")") }
        guard !changes.isEmpty else { return "Applying it would change nothing now." }
        return "Applying it would \(changes.joined(separator: " and "))."
    }
}

struct SavePreset: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "save",
        abstract: "Save the current mode of every display as a preset.",
        discussion: "Saving only reads the displays; it never switches them. A display in a hidden mode is left out, "
            + "since presets use only modes macOS lists. With --replace, a preset of the same name keeps its shortcut "
            + "and its place in the list."
    )

    @Argument(help: "A name for the preset.")
    var name: String

    @Flag(help: "Save over a preset of the same name.")
    var replace = false

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        do {
            _ = try PresetName.validated(name)
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        try PresetCommand.refuseRoot("save", in: context)
        let displays = context.service.displays()
        guard !displays.isEmpty else { throw ResoluteError.noDisplays }
        let capture = PresetCapture(displays: displays)
        let saved: (preset: Preset, replaced: Bool)
        do {
            saved = try context.presetStore.update { try $0.save(capture, named: name, replacing: replace) }
        } catch PresetError.nameTaken(let existing) {
            throw ResoluteError.invalidEntry(
                "There is already a preset named “\(existing)”. To save the current setup over it: "
                    + "resolute preset save \(Output.shellWord(name)) --replace"
            )
        }
        for leftOut in capture.leftOut {
            context.writeError("warning: " + leftOut.message)
        }
        if json {
            context.write(try Output.json(PresetReport(saved.preset, plan: saved.preset.plan(for: displays))))
            return
        }
        let verb = saved.replaced ? "Replaced “\(saved.preset.name)” with the current setup" : "Saved “\(saved.preset.name)”"
        context.write("\(verb): \(saved.preset.summary)")
    }
}

struct ApplyPreset: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "apply",
        abstract: "Switch every display in a preset to its mode.",
        discussion: "Only modes macOS lists are used, so nothing needs Keep or Revert. A display that is not connected "
            + "is skipped, and a resolution no longer offered at the saved refresh rate gets the closest one. "
            + "Mirroring changes first when the preset sets it."
    )

    @Argument(help: "The preset's name; case doesn't matter.")
    var name: String

    @Flag(help: "Print JSON.")
    var json = false

    @Flag(help: "Show what would change without changing it.")
    var dryRun = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let preset = try PresetCommand.preset(named: name, in: try context.presetStore.load())
        guard !dryRun else {
            let plan = preset.plan(for: context.service.displays())
            context.write(json ? try Output.json(PresetReport(preset, plan: plan)) : Self.preview(plan).joined(separator: "\n"))
            return
        }
        let before = context.service.displays()
        let result = PresetApplier(service: context.service).apply(preset)
        context.history.record(result, applying: preset, displays: before)
        if json {
            context.write(try Output.json(PresetResultReport(result)))
        } else {
            report(result, in: context)
        }
        if result.hasFailures {
            throw ResoluteError.invalidEntry(result.changedAnything
                ? "“\(preset.name)” was applied only in part."
                : "“\(preset.name)” could not be applied.")
        }
        if result.appliedNothing {
            throw ResoluteError.invalidEntry("Nothing in “\(preset.name)” applies to the displays connected now.")
        }
    }

    /// What applying would do, a line for mirroring and for each display.
    static func preview(_ plan: PresetPlan) -> [String] {
        var lines: [String] = []
        switch plan.mirroring {
        case .leftAlone: break
        case .inUse(let on): lines.append("Mirroring is already \(on ? "on" : "off").")
        case .turns(let on): lines.append("Would turn mirroring \(on ? "on" : "off").")
        case .notPossible: lines.append("Would skip mirroring: it needs at least two displays.")
        }
        for step in plan.steps {
            switch (step.status, step.mode) {
            case (.inUse, let mode?):
                lines.append("\(step.displayName) is already at \(Output.describe(mode)).")
            case (.switches, let mode?):
                lines.append("Would switch \(step.displayName) to \(Output.describe(mode)).")
            case (.skipped(let problem), _):
                lines.append("Would skip \(step.displayName): \(problem.reason(for: step.setting)).")
            case (_, nil):
                break
            }
        }
        return lines
    }

    /// Says what applying did, like `set` and `mirror` do: changes and skips on standard
    /// output, failures and doubts on standard error.
    private func report(_ result: PresetResult, in context: CommandContext) {
        switch result.mirroring {
        case .leftAlone: break
        case .alreadyInUse(let on): context.write("Mirroring is already \(on ? "on" : "off").")
        case .turned(let on): context.write(on ? "Mirroring is on." : "Mirroring is off.")
        case .notPossible: context.write("Skipped mirroring: it needs at least two displays.")
        case .failed(let on, let message): context.writeError("Could not turn mirroring \(on ? "on" : "off"): \(message)")
        }
        for display in result.displays {
            let name = display.displayName
            switch display.outcome {
            case .switched:
                if let mode = display.mode { context.write("\(name): \(Output.describe(mode))") }
            case .alreadyInUse:
                if let mode = display.mode { context.write("\(name) is already at \(Output.describe(mode)).") }
            case .skipped(let problem):
                context.write("Skipped \(name): \(problem.reason(for: display.setting)).")
            case .failed(let message):
                let mode = display.mode.map { " to \(Output.describe($0))" } ?? ""
                context.writeError("Could not switch \(name)\(mode): \(message)")
            case .wentAway:
                context.writeError("warning: \(name) went away, so its new mode could not be checked.")
            case .showsOtherMode(let shown):
                context.writeError(shown.map { "warning: macOS accepted the change but \(name) shows \(Output.describe($0)) now." }
                    ?? "warning: macOS accepted the change but \(name) reports a different mode now.")
            }
        }
    }
}

struct DeletePreset: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a preset.")

    @Argument(help: "The preset's name; case doesn't matter.")
    var name: String

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        try PresetCommand.refuseRoot("delete", in: context)
        let deleted = try context.presetStore.update { library in
            try library.delete(named: try PresetCommand.preset(named: name, in: library).name)
        }
        if json {
            context.write(try Output.json(PresetReport(deleted, plan: deleted.plan(for: context.service.displays()))))
            return
        }
        context.write("Deleted “\(deleted.name)”.")
    }
}

struct RenamePreset: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename",
        abstract: "Rename a preset.",
        discussion: "Changing only the case of a name renames it too."
    )

    @Argument(help: "The preset's name now; case doesn't matter.")
    var name: String

    @Argument(help: "Its new name.")
    var newName: String

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        do {
            _ = try PresetName.validated(newName)
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        try PresetCommand.refuseRoot("rename", in: context)
        let (old, renamed) = try context.presetStore.update { library -> (Preset, Preset) in
            let preset = try PresetCommand.preset(named: name, in: library)
            return (preset, try library.rename(preset.name, to: newName))
        }
        if json {
            context.write(try Output.json(PresetReport(renamed, plan: renamed.plan(for: context.service.displays()))))
            return
        }
        context.write(old.name == renamed.name ? "“\(old.name)” already has that name." : "Renamed “\(old.name)” to “\(renamed.name)”.")
    }
}

// MARK: - JSON

/// A preset as `preset list`, `show`, `save`, `delete` and `rename` print it, with what
/// applying it would do now. Like every JSON object the commands print, it has every key,
/// with null for a missing value.
struct PresetReport: Encodable {
    /// One display setting, and the connected display it is for.
    struct DisplayEntry: Encodable {
        let setting: DisplaySetting
        let step: PresetPlan.Step

        enum CodingKeys: String, CodingKey {
            case summary, connectedDisplay, connectedDisplayID, currentMode, mode, status, reason
        }

        func encode(to encoder: any Encoder) throws {
            // The setting's own keys, as the presets file has them.
            try setting.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(setting.summary, forKey: .summary)
            try container.encode(step.display?.name, forKey: .connectedDisplay)
            try container.encode(step.display?.id, forKey: .connectedDisplayID)
            try container.encode(step.display?.currentMode, forKey: .currentMode)
            try container.encode(step.mode, forKey: .mode)
            switch step.status {
            case .inUse: try container.encode("inUse", forKey: .status)
            case .switches: try container.encode("switches", forKey: .status)
            case .skipped(let problem): try container.encode(PresetReport.code(problem), forKey: .status)
            }
            let reason: String? = if case .skipped(let problem) = step.status { problem.reason(for: setting) } else { nil }
            try container.encode(reason, forKey: .reason)
        }
    }

    let preset: Preset
    let plan: PresetPlan

    init(_ preset: Preset, plan: PresetPlan) {
        self.preset = preset
        self.plan = plan
    }

    enum CodingKeys: String, CodingKey {
        case id, name, summary, shortcut, mirroring, mirroringStatus, isActive, displays
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset.id.uuidString, forKey: .id)
        try container.encode(preset.name, forKey: .name)
        try container.encode(preset.summary, forKey: .summary)
        try container.encode(preset.shortcut?.displayText, forKey: .shortcut)
        try container.encode(preset.mirroring, forKey: .mirroring)
        let mirroringStatus = switch plan.mirroring {
        case .leftAlone: "leftAlone"
        case .inUse: "inUse"
        case .turns: "turns"
        case .notPossible: "notPossible"
        }
        try container.encode(mirroringStatus, forKey: .mirroringStatus)
        try container.encode(plan.isActive, forKey: .isActive)
        try container.encode(zip(preset.displays, plan.steps).map { DisplayEntry(setting: $0, step: $1) }, forKey: .displays)
    }

    /// A skipped setting's status, as JSON names it.
    static func code(_ problem: PresetPlan.Problem) -> String {
        switch problem {
        case .notConnected: "notConnected"
        case .resolutionNotOffered: "resolutionNotOffered"
        case .currentModeUnknown: "currentModeUnknown"
        case .currentResolutionHidden: "currentResolutionHidden"
        }
    }
}

/// What `preset apply --json` prints: what happened to mirroring and to each display.
struct PresetResultReport: Encodable {
    struct DisplayEntry: Encodable {
        let result: PresetResult.DisplayResult

        enum CodingKeys: String, CodingKey {
            case summary, connectedDisplay, connectedDisplayID, result, reason, previousMode, mode
        }

        func encode(to encoder: any Encoder) throws {
            try result.setting.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(result.setting.summary, forKey: .summary)
            try container.encode(result.display?.name, forKey: .connectedDisplay)
            try container.encode(result.display?.id, forKey: .connectedDisplayID)
            let (code, reason): (String, String?) = switch result.outcome {
            case .switched: ("switched", nil)
            case .alreadyInUse: ("alreadyInUse", nil)
            case .skipped(let problem): (PresetReport.code(problem), problem.reason(for: result.setting))
            case .failed(let message): ("failed", message)
            case .wentAway: ("wentAway", "the display went away, so its new mode could not be checked")
            case .showsOtherMode(let shown?):
                ("showsOtherMode", "macOS accepted the change but the display shows \(Output.describe(shown)) now")
            case .showsOtherMode(nil): ("showsOtherMode", "macOS accepted the change but the display reports a different mode now")
            }
            try container.encode(code, forKey: .result)
            try container.encode(reason, forKey: .reason)
            try container.encode(result.previousMode, forKey: .previousMode)
            try container.encode(result.mode, forKey: .mode)
        }
    }

    let result: PresetResult

    init(_ result: PresetResult) {
        self.result = result
    }

    enum CodingKeys: String, CodingKey {
        case id, name, succeeded, changed, mirroring, mirroringResult, mirroringReason, displays
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(result.preset.id.uuidString, forKey: .id)
        try container.encode(result.preset.name, forKey: .name)
        let succeeded = !result.hasFailures && !result.appliedNothing
        try container.encode(succeeded, forKey: .succeeded)
        try container.encode(result.changedAnything, forKey: .changed)
        try container.encode(result.preset.mirroring, forKey: .mirroring)
        let (code, reason): (String, String?) = switch result.mirroring {
        case .leftAlone: ("leftAlone", nil)
        case .alreadyInUse: ("alreadyInUse", nil)
        case .turned: ("turned", nil)
        case .notPossible: ("notPossible", "mirroring needs at least two displays")
        case .failed(_, let message): ("failed", message)
        }
        try container.encode(code, forKey: .mirroringResult)
        try container.encode(reason, forKey: .mirroringReason)
        try container.encode(result.displays.map(DisplayEntry.init), forKey: .displays)
    }
}
