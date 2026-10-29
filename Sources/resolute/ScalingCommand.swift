import ArgumentParser
import Foundation
import ResoluteKit

/// `resolute scaling`: Sharp Scaling, which gives a standard display Retina-style sizes.
struct ScalingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scaling",
        abstract: "Plan, turn on and check Sharp Scaling.",
        discussion: """
            Sharp Scaling gives a standard display, such as most 1080p and 1440p monitors, Retina-style (HiDPI) sizes \
            from Larger Text to More Space.
            Resolute writes them into the display's override file; macOS draws each one at twice its size, scales it \
            to the panel, and offers the sizes once the display reconnects.
            Without --display, commands use the main display. on and off need administrator rights: run them with sudo.
            """,
        subcommands: [PlanSharpScaling.self, TurnOnSharpScaling.self, TurnOffSharpScaling.self, ShowSharpScalingStatus.self],
        defaultSubcommand: ShowSharpScalingStatus.self
    )

    static let useThemHint = "Reconnect the display or restart to use them."
    static let goAwayHint = "The sharp sizes go away after you reconnect the display or restart."

    /// The plan for `display`, or why it can't have Sharp Scaling.
    static func plan(for display: Display, installed: DisplayOverride?, limit: DrawingLimit) throws -> SharpScalingPlan {
        let unknownPanel = ResoluteError.invalidEntry(
            "Resolute can’t tell the resolution of the panel in \(display.name), so it can’t plan sharp sizes for it."
        )
        switch SharpScalingPlan.unavailability(for: display, installed: installed) {
        case .builtIn?:
            throw ResoluteError.invalidEntry(
                "\(display.name) doesn’t need Sharp Scaling: built-in displays are Retina displays, so their sizes are sharp already."
            )
        case .alreadyHiDPI?:
            throw ResoluteError.invalidEntry(
                "\(display.name) doesn’t need Sharp Scaling: it has HiDPI sizes already, which resolute modes lists."
            )
        case .unknownPanel?:
            throw unknownPanel
        case nil:
            break
        }
        let record = installed.flatMap { try? SharpScalingRecord(in: $0) }
        guard let plan = SharpScalingPlan(display: display, limit: limit, record: record) else { throw unknownPanel }
        return plan
    }

    /// "this Mac draws up to 6144 px wide on it"
    static func limitPhrase(_ limit: DrawingLimit) -> String {
        limit.width.map { "this Mac draws up to \($0) px wide on it" } ?? "this Mac doesn’t say how wide it can draw on it"
    }

    /// "1 sharp size", "5 sharp sizes"
    static func count(_ number: Int) -> String {
        number == 1 ? "1 sharp size" : "\(number) sharp sizes"
    }

    /// "a", "a and b", "a, b and c"
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    /// " -d ASUS", to repeat the display option in a suggested command; empty for the main display.
    static func displayArgument(_ target: DisplayOptions) -> String {
        target.display == "main" ? "" : " -d \(Output.shellWord(target.display))"
    }
}

/// Plans as if this Mac published another drawing limit, for staging and tests.
struct DrawingLimitOptions: ParsableArguments {
    @Option(
        name: .customLong("drawing-limit"),
        help: ArgumentHelp("Plan for this drawing limit, WIDTH or WIDTHxHEIGHT in pixels, instead of the Mac's.", visibility: .hidden)
    )
    var drawingLimit: String?

    func validate() throws {
        if let drawingLimit, Self.parse(drawingLimit) == nil {
            throw ValidationError("--drawing-limit takes WIDTH or WIDTHxHEIGHT in pixels, for example 6144.")
        }
    }

    var limit: DrawingLimit {
        drawingLimit.flatMap(Self.parse) ?? .current()
    }

    static func parse(_ text: String) -> DrawingLimit? {
        if text.allSatisfy({ $0.isASCII && $0.isNumber }), let width = Int(text), width > 0 {
            return DrawingLimit(width: width)
        }
        return SharpSize(text).map { DrawingLimit(width: $0.width, height: $0.height) }
    }
}

struct PlanSharpScaling: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Show the sharp sizes Sharp Scaling would add, and whether this Mac can draw them."
    )

    @OptionGroup var target: DisplayOptions
    @OptionGroup var location: LocationOptions
    @OptionGroup var drawing: DrawingLimitOptions

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let display = try target.resolve(in: context.service.displays())
        let installed = try OverrideStore(locations: location.locations).installedOverride(for: OverrideKey(display: display))
        let plan = try ScalingCommand.plan(for: display, installed: installed, limit: drawing.limit)
        context.write(json ? Self.json(plan, display: display) : Self.text(plan, display: display))
    }

    /// The design's terminal frame (68:2029): a line about the panel and this Mac, then one
    /// row per size, two spaces in, its columns three and then four spaces apart.
    static func text(_ plan: SharpScalingPlan, display: Display) -> String {
        let header = "\(display.name) · \(plan.native.sizeText) panel · \(ScalingCommand.limitPhrase(plan.limit))"
        let rows = plan.steps.map { step in [step.size.sizeText, "drawn at \(step.size.drawnText)", note(for: step, in: plan)] }
        var widths = [0, 0]
        for row in rows {
            widths[0] = max(widths[0], row[0].count)
            widths[1] = max(widths[1], row[1].count)
        }
        func padded(_ cell: String, to width: Int) -> String {
            cell + String(repeating: " ", count: width - cell.count)
        }
        let lines = rows.map { row in "  " + padded(row[0], to: widths[0] + 3) + padded(row[1], to: widths[1] + 4) + row[2] }
        return ([header] + lines).joined(separator: "\n")
    }

    /// "text 60% larger", "same size as now", or why the size is left out.
    static func note(for step: SharpScalingPlan.Step, in plan: SharpScalingPlan) -> String {
        guard step.fits else {
            return plan.limit.isTooWide(step.size) ? "left out: wider than this Mac draws" : "left out: taller than this Mac draws"
        }
        return step.size == plan.native ? "same size as now" : "text \(step.textLarger)% larger"
    }

    static func json(_ plan: SharpScalingPlan, display: Display) -> String {
        let limit: OrderedJSON = plan.limit.isKnown
            ? .object([("width", plan.limit.width.map(OrderedJSON.number) ?? .null), ("height", plan.limit.height.map(OrderedJSON.number) ?? .null)])
            : .null
        let sizes = plan.steps.map { step in
            OrderedJSON.object([
                ("size", .string(step.size.description)),
                ("drawn", .string("\(step.size.drawnWidth)x\(step.size.drawnHeight)")),
                ("textLarger", .number(step.textLarger)),
                ("fits", .bool(step.fits)),
            ])
        }
        return OrderedJSON.object([
            ("display", .string(display.name)),
            ("panel", .string(plan.native.description)),
            ("limit", limit),
            ("sizes", .array(sizes)),
        ]).text
    }
}

struct TurnOnSharpScaling: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "on",
        abstract: "Add the sharp sizes to a display's override.",
        discussion: """
            Backs up the override file first and keeps its other entries. The sizes appear after the display reconnects \
            or the Mac restarts.
            With --switch the display moves to the sharp version of its size once macOS offers it: now if it does already, \
            otherwise the Resolute app switches when the display is back, or run this again then.
            """
    )

    @OptionGroup var target: DisplayOptions

    @Option(
        parsing: .upToNextOption,
        help: "Only these sizes from `resolute scaling plan`, for example 1600x900,2560x1440. By default, all that this Mac can draw."
    )
    var sizes: [String] = []

    @Flag(name: .customLong("switch"), help: "Move the display to the sharp version of its size once macOS offers it.")
    var switchWhenReady = false

    @OptionGroup var location: LocationOptions
    @OptionGroup var drawing: DrawingLimitOptions

    func validate() throws {
        guard sizes.isEmpty || !requested.isEmpty else { throw ValidationError("--sizes takes WIDTHxHEIGHT sizes, for example 1920x1080.") }
        for text in requested where SharpSize(text) == nil {
            throw ValidationError("“\(text)” is not a size. Use WIDTHxHEIGHT from resolute scaling plan, for example 1920x1080.")
        }
    }

    /// The sizes as typed, whether separated by commas or spaces.
    private var requested: [String] {
        sizes.flatMap { $0.split(separator: ",") }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let display = try target.resolve(in: context.service.displays())
        let key = OverrideKey(display: display)
        let store = OverrideStore(locations: location.locations)
        let plan = try ScalingCommand.plan(for: display, installed: try store.installedOverride(for: key), limit: drawing.limit)
        let chosen = try chosenSizes(from: plan, display: display)
        let switchTo = switchWhenReady
            ? SharpScalingPlan.switchTarget(from: display.currentMode, among: chosen, native: plan.native)
            : nil
        // Nothing to change needs no administrator rights, so check before asking for them.
        let preview = try SharpScalingSetup(file: store.editableFile(for: key), sizes: chosen, offered: [], switchTo: switchTo, now: Date())
        var wrote: SharpScalingSetup?
        if preview.hasChanges {
            let writer = SharpScalingWriter(store: store, installer: try location.installer(in: context))
            let setup = try await location.withLock(in: context) {
                try await writer.turnOn(for: display, sizes: chosen, switchTo: switchTo)
            }
            if setup.hasChanges { wrote = setup }
        }
        if let wrote {
            if wrote.replacesFile { context.write("Backed up the override file for \(display.name).") }
            context.write(Self.summary(wrote))
        } else {
            try reportAlreadyOn(display: display, store: store, in: context)
        }
        if let switchTo { try moveToSharp(switchTo, on: display, wrote: wrote != nil, in: context) }
    }

    /// The sizes asked for, or every size this Mac can draw. Each must be one of the plan's.
    private func chosenSizes(from plan: SharpScalingPlan, display: Display) throws -> [SharpSize] {
        let asked = requested.compactMap { SharpSize($0) }
        guard !asked.isEmpty else {
            guard !plan.sizes.isEmpty else {
                throw ResoluteError.invalidEntry(
                    "None of the sharp sizes for \(display.name) fit: \(ScalingCommand.limitPhrase(plan.limit)), so there is nothing to add."
                )
            }
            return plan.sizes
        }
        for size in asked {
            guard let step = plan.step(for: size) else {
                throw ResoluteError.usage(
                    "\(size.sizeText) is not one of the sharp sizes for \(display.name): "
                        + ScalingCommand.list(plan.steps.map(\.size.description)) + "."
                )
            }
            guard step.fits else {
                throw ResoluteError.usage(
                    "\(size.sizeText) is drawn at \(size.drawnText), and \(ScalingCommand.limitPhrase(plan.limit)), so it can’t be added."
                )
            }
        }
        return asked
    }

    /// "Added 5 sharp sizes. Reconnect the display or restart to use them."
    static func summary(_ setup: SharpScalingSetup) -> String {
        let added = setup.added.count, removed = setup.removed.count
        let applyHint = "Reconnect the display or restart to apply the change."
        switch (added, removed) {
        case (0, 0):
            return "The override already lists these sizes, so Sharp Scaling now keeps track of them."
        case (_, 0):
            return "Added \(ScalingCommand.count(added)). \(ScalingCommand.useThemHint)"
        case (0, _):
            return "Removed \(ScalingCommand.count(removed)). \(applyHint)"
        default:
            return "Added \(ScalingCommand.count(added)) and removed \(removed). \(applyHint)"
        }
    }

    private func reportAlreadyOn(display: Display, store: OverrideStore, in context: CommandContext) throws {
        let status = try SharpScalingStatus(
            display: display, installed: try store.installedOverride(for: OverrideKey(display: display)),
            systemStart: SharpScalingStatus.systemStart()
        )
        let already = "Sharp Scaling is already on for \(display.name) with these sizes."
        switch status.state {
        case .waiting:
            context.write(already + " " + ScalingCommand.useThemHint)
        case .partial:
            context.write(already + " macOS skipped " + ScalingCommand.list(status.skipped.map(\.sizeText)) + " on this Mac.")
        case .ready, .off:
            context.write(already)
        }
    }

    /// Switches to `size`, sharp, once macOS offers it. Until then, after a write, the sizes
    /// appearing after a reconnect is all there is to say: the app switches when they do.
    private func moveToSharp(_ size: SharpSize, on display: Display, wrote: Bool, in context: CommandContext) throws {
        guard let shown = context.service.displays().first(where: { $0.id == display.id }),
              let mode = SharpScalingStatus.sharpMode(for: size, on: shown, keeping: shown.currentMode)
        else {
            if !wrote { context.write("Run this again after the reconnect to switch to the sharp \(size.sizeText).") }
            return
        }
        guard mode.modeID != shown.currentModeID else {
            context.write("\(shown.name) is already at \(Output.describe(mode)).")
            return
        }
        let switcher = ModeSwitcher(service: context.service)
        let history = context.history
        let outcome: ModeSwitcher.Outcome
        do {
            outcome = try switcher.apply(modeID: mode.modeID, to: shown.id, trial: false) { .keep }
        } catch {
            history.record(error, switching: shown, to: mode)
            throw error
        }
        history.record(outcome, switching: shown, to: mode)
        guard switcher.currentModeID(of: shown.id) == mode.modeID else {
            context.writeError("warning: macOS accepted the change but reports a different mode now.")
            return
        }
        context.write("\(shown.name): \(Output.describe(mode))")
    }
}

struct TurnOffSharpScaling: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "off",
        abstract: "Remove Sharp Scaling from a display's override.",
        discussion: """
            Puts back the override file from before Sharp Scaling when nothing else changed it since; otherwise takes out \
            only the sharp sizes and keeps the rest. The file it replaces is backed up either way.
            The sharp sizes go away after the display reconnects or the Mac restarts.
            """
    )

    @OptionGroup var target: DisplayOptions
    @OptionGroup var location: LocationOptions

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let display = try target.resolve(in: context.service.displays())
        let key = OverrideKey(display: display)
        let store = OverrideStore(locations: location.locations)
        let nothingToRemove = "Sharp Scaling is off for \(display.name), so there is nothing to remove."
        // Nothing to remove needs no administrator rights, so check before asking for them.
        guard let installed = try store.installedOverride(for: key), try SharpScalingRecord(in: installed) != nil else {
            context.write(nothingToRemove)
            return
        }
        let writer = SharpScalingWriter(store: store, installer: try location.installer(in: context))
        // Checked again under the lock: an overlapping command may have turned it off.
        guard let removal = try await location.withLock(in: context, { try await writer.turnOff(for: key) }) else {
            context.write(nothingToRemove)
            return
        }
        context.write("Backed up the override file for \(display.name).")
        switch removal {
        case .restore:
            context.write("Put back the file from before Sharp Scaling. \(ScalingCommand.goAwayHint)")
        case .remove:
            context.write("Removed the override file Sharp Scaling created. \(ScalingCommand.goAwayHint)")
        case .strip(_, .changedSince):
            context.write(
                "Took out the sharp sizes and kept the rest of the file, which changed after Sharp Scaling was set up. "
                    + ScalingCommand.goAwayHint
            )
        case .strip(_, .backupMissing):
            context.write(
                "Took out the sharp sizes and kept the rest of the file: its backup from before Sharp Scaling is gone. "
                    + ScalingCommand.goAwayHint
            )
        }
    }
}

struct ShowSharpScalingStatus: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Say whether Sharp Scaling is on for a display, and which sizes macOS accepted."
    )

    @OptionGroup var target: DisplayOptions
    @OptionGroup var location: LocationOptions

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let display = try target.resolve(in: context.service.displays())
        let installed = try OverrideStore(locations: location.locations).installedOverride(for: OverrideKey(display: display))
        let status = try SharpScalingStatus(display: display, installed: installed, systemStart: SharpScalingStatus.systemStart())
        if json {
            context.write(Self.json(status, display: display))
            return
        }
        for line in lines(status, display: display, installed: installed) { context.write(line) }
    }

    /// One line, keys in the design's order (68:2029):
    /// {"display":"ASUS PA278QV","scaling":"on","saved":5,"available":5,"skipped":[],"current":"2560x1440","hidpi":true}
    static func json(_ status: SharpScalingStatus, display: Display) -> String {
        let scaling = switch status.state {
        case .off: "off"
        case .waiting: "waiting"
        case .ready: "on"
        case .partial: "partial"
        }
        return OrderedJSON.object([
            ("display", .string(display.name)),
            ("scaling", .string(scaling)),
            ("saved", .number(status.saved.count)),
            ("available", .number(status.available.count)),
            ("skipped", .array(status.skipped.map { .string($0.description) })),
            ("current", status.current.map { OrderedJSON.string(SharpSize($0).description) } ?? .null),
            ("hidpi", status.current.map { OrderedJSON.bool($0.isHiDPI) } ?? .null),
        ]).text
    }

    private func lines(_ status: SharpScalingStatus, display: Display, installed: DisplayOverride?) -> [String] {
        let name = display.name
        let sizes = status.saved.count
        let onCommand = location.command("scaling on\(ScalingCommand.displayArgument(target))", isRoot: true)
        switch status.state {
        case .off:
            let line = "Sharp Scaling is off for \(name)."
            guard SharpScalingPlan.unavailability(for: display, installed: installed) == nil else { return [line] }
            let planCommand = location.command("scaling plan\(ScalingCommand.displayArgument(target))", isRoot: false)
            return [line, "To see the sizes it would add: \(planCommand)"]
        case .waiting:
            let saved = status.record.map { Self.savedTime($0.saved) } ?? ""
            return [
                "Sharp Scaling for \(name) is saved and waits for a reconnect.",
                "Saved \(saved): \(ScalingCommand.list(status.saved.map(\.sizeText))). macOS reads the override file when the display connects.",
                ScalingCommand.useThemHint,
            ]
        case .ready:
            let accepted = sizes == 1 ? "macOS accepted the size" : sizes == 2 ? "macOS accepted both sizes" : "macOS accepted all \(sizes) sizes"
            var lines = ["Sharp Scaling is ready on \(name)."]
            if let current = status.current, current.isHiDPI, status.saved.contains(SharpSize(current)) {
                lines.append("\(accepted), and \(name) now uses the sharp \(SharpSize(current).sizeText).")
            } else if let current = status.current, !current.isHiDPI, let sharp = status.sharpVersionOfCurrent {
                lines.append("\(accepted). \(name) still uses \(SharpSize(current).sizeText) at 1×.")
                lines.append("To switch to the sharp one: resolute set \(SharpSize(sharp).description)@2x\(ScalingCommand.displayArgument(target))")
            } else {
                lines.append("\(accepted).")
            }
            return lines
        case .partial:
            guard !status.available.isEmpty else {
                return [
                    "macOS added none of the \(sizes) sharp sizes for \(name).",
                    "It skipped all of them on this Mac.",
                    "To remove them: " + location.command("scaling off\(ScalingCommand.displayArgument(target))", isRoot: true),
                ]
            }
            let skipped = status.skipped.count
            let other = Self.word(status.available.count)
            let which = skipped == 1 ? "size" : "sizes"
            return [
                "macOS added \(status.available.count) of \(sizes) sizes for \(name).",
                "It skipped \(ScalingCommand.list(status.skipped.map(\.sizeText))) on this Mac. "
                    + "Keep the other \(other), or remove the skipped \(which) so the list matches what you can use.",
                "To remove \(skipped == 1 ? "it" : "them"): \(onCommand) --sizes \(status.available.map(\.description).joined(separator: ","))",
            ]
        }
    }

    /// "on 2026-10-28 at 09:42", in this Mac's time zone.
    static func savedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "'on' yyyy-MM-dd 'at' HH:mm"
        return formatter.string(from: date)
    }

    /// "four", as the design writes small counts in a sentence.
    static func word(_ number: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(number) ? words[number] : String(number)
    }
}

/// JSON on one line with its keys in a set order, as the design shows the scaling commands'.
/// (`Output.json` sorts keys and spreads them over lines.)
enum OrderedJSON {
    case string(String)
    case number(Int)
    case bool(Bool)
    case null
    case array([OrderedJSON])
    case object([(String, OrderedJSON)])

    var text: String {
        switch self {
        case .string(let value): Self.quoted(value)
        case .number(let value): String(value)
        case .bool(let value): value ? "true" : "false"
        case .null: "null"
        case .array(let values): "[" + values.map(\.text).joined(separator: ",") + "]"
        case .object(let pairs): "{" + pairs.map { Self.quoted($0.0) + ":" + $0.1.text }.joined(separator: ",") + "}"
        }
    }

    /// `value` as a JSON string, escaped by `JSONEncoder`.
    private static func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }
}
