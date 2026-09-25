import ArgumentParser
import Foundation
import ResoluteKit

struct OverridesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overrides",
        abstract: "Inspect and edit custom resolutions in /Library/Displays.",
        discussion: """
            Without --display, --vendor or --product, commands use the main display.
            Changes apply after the display is reconnected or the Mac restarts.
            Commands that write need administrator rights: run them with sudo.
            """,
        subcommands: [ListOverrides.self, ShowOverride.self, AddResolution.self, RemoveResolution.self, ResetOverride.self],
        defaultSubcommand: ListOverrides.self
    )

    static let reconnectHint = "The change applies after you reconnect the display or restart the Mac."
}

/// Where overrides are read from and written to.
struct LocationOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Use this directory instead of /Library/Displays.", visibility: .hidden))
    var root: String?

    var locations: OverrideLocations {
        root.map { OverrideLocations.staged(at: URL(filePath: $0, directoryHint: .isDirectory)) } ?? .standard
    }

    func installer(in context: CommandContext) throws -> OverrideInstaller {
        guard root != nil || context.isRoot else { throw ResoluteError.needsRoot }
        return OverrideInstaller(locations: locations, runner: ShellCommandRunner())
    }

    /// Held while a command reads, changes and writes an override, so commands that
    /// overlap cannot lose each other's changes.
    func withLock<T>(in context: CommandContext, _ body: () async throws -> T) async throws -> T {
        try await OverrideLock(file: locations.lockFile).withLock(onWait: {
            context.writeError("Waiting for another resolute command to finish editing overrides…")
        }, body)
    }

    /// How to run a follow-up command against the same overrides.
    func command(_ arguments: String, isRoot: Bool) -> String {
        if let root { return "resolute \(arguments) --root \(Output.shellWord(root))" }
        return (isRoot ? "sudo " : "") + "resolute \(arguments)"
    }
}

/// Which display's override to use.
struct OverrideTargetOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "A connected display: main (the default), an index, id:<number>, or part of its name.")
    var display: String?

    @Option(help: "Vendor ID in hex, for a display that is not connected (for example db4).")
    var vendor: String?

    @Option(help: "Product ID in hex, for a display that is not connected (for example 3401).")
    var product: String?

    func validate() throws {
        if (vendor == nil) != (product == nil) {
            throw ValidationError("Pass both --vendor and --product.")
        }
        if display != nil && vendor != nil {
            throw ValidationError("Pass either --display or --vendor and --product.")
        }
        if let vendor, Self.hex(vendor) == nil {
            throw ValidationError("--vendor takes a hexadecimal ID, for example db4.")
        }
        if let product, Self.hex(product) == nil {
            throw ValidationError("--product takes a hexadecimal ID, for example 3401.")
        }
    }

    func target(in context: CommandContext) throws -> OverrideTarget {
        let displays = context.service.displays()
        if let vendor, let product, let vendorID = Self.hex(vendor), let productID = Self.hex(product) {
            let key = OverrideKey(vendorID: vendorID, productID: productID)
            return OverrideTarget(key: key, display: displays.first { OverrideKey(display: $0) == key })
        }
        let display = try DisplaySelector(display ?? "main").resolve(in: displays)
        return OverrideTarget(key: OverrideKey(display: display), display: display)
    }

    /// These options as typed, to repeat them in a suggested command.
    var arguments: String {
        if let vendor, let product { return " --vendor \(vendor) --product \(product)" }
        return display.map { " -d \(Output.shellWord($0))" } ?? ""
    }

    static func hex(_ text: String) -> UInt32? {
        UInt32(text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text, radix: 16)
    }
}

/// An override and the connected display it belongs to, if any.
struct OverrideTarget: CustomStringConvertible {
    var key: OverrideKey
    var display: Display?

    /// "Built-in Retina Display (vendor 610, product a050)", or "vendor db4, product 3401".
    var description: String {
        display.map { "\($0.name) (\(key))" } ?? key.description
    }
}

/// The resolution an `add` or `remove` command names.
struct EntryOptions: ParsableArguments {
    @Argument(help: "WIDTHxHEIGHT: points for a HiDPI entry (or add @2x), pixels for a 1× entry (add @1x or --standard).")
    var resolution: String

    @Flag(help: "A 1× entry instead of a HiDPI one (same as @1x).")
    var standard = false

    /// The entry named. For `add` it must also be one Resolute writes; `remove` takes any
    /// entry a file may hold, such as an old one below the sizes `add` accepts. Problems
    /// are usage errors.
    func entry(flags: String? = nil, adding: Bool) throws -> ScaleResolution {
        do {
            let entry = try ScaleResolution(parsing: resolution, standard: standard, flags: try flags.map { try HiDPIFlags(parsing: $0) })
            if adding { try OverrideDraft.validate(entry) }
            return entry
        } catch let error as ResoluteError {
            throw ResoluteError.usage(error.localizedDescription)
        }
    }

    /// Reports a bad entry while parsing. Only something shaped like a size is checked:
    /// a bare word is more likely the value of a mistyped option, which ArgumentParser
    /// reports after validation; anything else is reported by `entry(flags:adding:)` later.
    func validate(flags: String? = nil, adding: Bool) throws {
        guard Output.looksLikeSize(resolution) else { return }
        do {
            _ = try entry(flags: flags, adding: adding)
        } catch ResoluteError.usage(let message) {
            throw ValidationError(message)
        }
    }
}

struct ListOverrides: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List installed overrides.")

    @OptionGroup var location: LocationOptions

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let store = OverrideStore(locations: location.locations)
        let displays = context.service.displays()
        let summaries = store.installedKeys().map { key in
            OverrideSummary(key: key, store: store, display: displays.first { OverrideKey(display: $0) == key })
        }
        if json {
            context.write(try Output.json(summaries))
            return
        }
        guard !summaries.isEmpty else {
            context.write("No overrides in \(store.locations.userRoot.path(percentEncoded: false))")
            return
        }
        summaries.forEach { context.write($0.text) }
    }
}

struct ShowOverride: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show the override for a display (the installed one, else the one macOS ships)."
    )

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let target = try target.target(in: context)
        let store = OverrideStore(locations: location.locations)
        let (override, source) = try store.editableOverride(for: target.key)
        let summary = OverrideSummary(
            key: target.key, override: override, source: source, locations: store.locations, display: target.display
        )
        context.write(json ? try Output.json(summary) : summary.text)
    }
}

struct AddResolution: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a custom resolution to a display's override.",
        discussion: "A HiDPI entry comes with a 1× entry at its pixel size, as RDM wrote them, unless the override lists one."
    )

    @OptionGroup var entry: EntryOptions

    @Option(help: "HiDPI flags as two hex words, for example 00000009,00a00000 (the default).")
    var flags: String?

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func validate() throws {
        try entry.validate(flags: flags, adding: true)
    }

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let newEntry = try entry.entry(flags: flags, adding: true)
        let target = try target.target(in: context)
        let installer = try location.installer(in: context)
        try await location.withLock(in: context) {
            var draft = OverrideDraft(try OverrideStore(locations: location.locations).editableOverride(for: target.key).override)
            let alsoAdded = try draft.add(newEntry)
            let url = try await installer.install(draft.working)
            context.write("Added \(newEntry.summary) for \(target).")
            for partner in alsoAdded {
                context.write("Also added \(partner.summary), the 1× entry HiDPI entries are paired with.")
            }
            context.write("Saved \(url.path(percentEncoded: false))")
            context.write(OverridesCommand.reconnectHint)
        }
    }
}

struct RemoveResolution: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a custom resolution from a display's override.",
        discussion: "Without an override of its own, the display's override starts as a copy of the one macOS ships. "
            + "Removing a HiDPI entry leaves the 1× entry at its pixel size, which the override may need for other reasons; "
            + "remove that separately if it was only there for the HiDPI entry."
    )

    @OptionGroup var entry: EntryOptions
    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func validate() throws {
        try entry.validate(adding: false)
    }

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let unwanted = try entry.entry(adding: false)
        let target = try target.target(in: context)
        let installer = try location.installer(in: context)
        let store = OverrideStore(locations: location.locations)
        try await location.withLock(in: context) {
            let (override, source) = try store.editableOverride(for: target.key)
            guard source != .missing else {
                throw ResoluteError.invalidEntry("There is no override for \(target), so there is nothing to remove.")
            }
            var draft = OverrideDraft(override)
            let matches = draft.working.resolutions.filter { $0.sameMode(as: unwanted) }
            guard !matches.isEmpty else {
                throw ResoluteError.invalidEntry(missingMessage(for: unwanted, in: draft.working, target: target))
            }
            draft.remove(matches)
            let url = try await installer.install(draft.working)
            let count = matches.count > 1 ? " (\(matches.count) entries)" : ""
            context.write("Removed \(unwanted.sizeText) \(unwanted.kindText)\(count) for \(target).")
            if case .hiDPI = unwanted, let pixels = unwanted.pixelSize {
                let partner = ScaleResolution.standard(width: pixels.width, height: pixels.height)
                if draft.working.resolutions.contains(where: { $0.sameMode(as: partner) }) {
                    // Entries are never removed implicitly, and one macOS ships is never
                    // suggested for removal: it may be the panel's native size.
                    let shipped = (try? store.systemOverride(for: target.key))??.resolutions
                        .contains { $0.sameMode(as: partner) } ?? false
                    context.write(shipped
                        ? "\(partner.summary) stays in the override: the file macOS ships lists it too."
                        : "\(partner.summary) stays in the override. If it was there only for \(unwanted.sizeText) HiDPI, "
                            + "remove it too: " + location.command(
                                "overrides remove \(pixels.width)x\(pixels.height)@1x\(self.target.arguments)", isRoot: context.isRoot
                            ))
                }
            }
            context.write("Saved \(url.path(percentEncoded: false))")
            context.write(OverridesCommand.reconnectHint)
        }
    }

    /// Why `entry` could not be found, pointing at the entry of the other kind when that is there.
    private func missingMessage(for entry: ScaleResolution, in override: DisplayOverride, target: OverrideTarget) -> String {
        let missing = "\(entry.sizeText) \(entry.kindText) is not in the override for \(target)"
        guard case .hiDPI(let width, let height, _) = entry,
              override.resolutions.contains(where: { $0.sameMode(as: .standard(width: width, height: height)) })
        else { return missing + "." }
        return missing + ", but \(width) × \(height) 1× is: add @1x."
    }
}

struct ResetOverride: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Delete a display's override so macOS uses its default resolutions."
    )

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let target = try target.target(in: context)
        let file = location.locations.userFile(for: target.key).path(percentEncoded: false)
        // Nothing to remove needs no administrator rights, so check before asking for them.
        guard FileManager.default.fileExists(atPath: file) else {
            context.write(Self.nothingToRemove(for: target))
            return
        }
        let installer = try location.installer(in: context)
        let removed = try await location.withLock(in: context) { () async throws -> Bool in
            // Checked again under the lock: an overlapping reset may have removed it.
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file, isDirectory: &isFolder) else { return false }
            guard !isFolder.boolValue else {
                throw ResoluteError.invalidEntry("\(file) is a folder, not an override file. Remove it in the Finder.")
            }
            try await installer.remove(target.key)
            return true
        }
        guard removed else {
            context.write(Self.nothingToRemove(for: target))
            return
        }
        context.write(
            "Removed the override for \(target). A backup is in \(installer.locations.backupRoot.path(percentEncoded: false))"
        )
        context.write(OverridesCommand.reconnectHint)
    }

    static func nothingToRemove(for target: OverrideTarget) -> String {
        "There is no custom override for \(target), so there is nothing to remove."
    }
}

/// An override as `overrides list` and `overrides show` print it.
struct OverrideSummary: Encodable {
    struct Entry: Encodable {
        /// "hidpi", "standard", or "preserved" for an element that names no mode.
        let kind: String
        let width: Int?
        let height: Int?
        let pixelWidth: Int?
        let pixelHeight: Int?
        let flags: String?
        /// Written back byte for byte, in a form Resolute does not write itself.
        let keptAsIs: Bool
        let summary: String

        init(_ entry: ScaleResolution) {
            switch entry.describedMode {
            case .hiDPI(let width, let height, let flags)?:
                kind = "hidpi"
                self.width = width
                self.height = height
                pixelWidth = width * 2
                pixelHeight = height * 2
                // A kept 12-byte entry has one flags word, not the pair `flags` would show.
                self.flags = entry.isEditable ? flags.description : nil
            case .standard(let width, let height)?:
                kind = "standard"
                self.width = width
                self.height = height
                pixelWidth = width
                pixelHeight = height
                flags = nil
            case .preserved?, nil:
                kind = "preserved"
                width = nil
                height = nil
                pixelWidth = nil
                pixelHeight = nil
                flags = nil
            }
            keptAsIs = !entry.isEditable
            summary = entry.summary
        }

        enum CodingKeys: String, CodingKey {
            case kind, width, height, pixelWidth, pixelHeight, flags, keptAsIs, summary
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(width, forKey: .width)
            try container.encode(height, forKey: .height)
            try container.encode(pixelWidth, forKey: .pixelWidth)
            try container.encode(pixelHeight, forKey: .pixelHeight)
            try container.encode(flags, forKey: .flags)
            try container.encode(keptAsIs, forKey: .keptAsIs)
            try container.encode(summary, forKey: .summary)
        }
    }

    let vendorID: String
    let productID: String
    let path: String
    /// "installed", "system" (the file macOS ships) or "missing".
    let source: String
    let connectedDisplay: String?
    let connectedDisplayID: UInt32?
    let productName: String?
    let entries: [Entry]
    let problem: String?

    init(key: OverrideKey, override: DisplayOverride, source: OverrideStore.Source, locations: OverrideLocations, display: Display?, problem: String? = nil) {
        vendorID = Output.hex(key.vendorID)
        productID = Output.hex(key.productID)
        switch source {
        case .installed:
            path = locations.userFile(for: key).path(percentEncoded: false)
            self.source = "installed"
        case .system:
            path = locations.systemFile(for: key).path(percentEncoded: false)
            self.source = "system"
        case .missing:
            path = locations.userFile(for: key).path(percentEncoded: false)
            self.source = "missing"
        }
        connectedDisplay = display?.name
        connectedDisplayID = display?.id
        productName = override.productName
        entries = override.resolutions.map(Entry.init)
        self.problem = problem
    }

    init(key: OverrideKey, store: OverrideStore, display: Display?) {
        do {
            let installed = try store.installedOverride(for: key)
            self.init(
                key: key, override: installed ?? DisplayOverride(key: key), source: installed == nil ? .missing : .installed,
                locations: store.locations, display: display
            )
        } catch {
            self.init(
                key: key, override: DisplayOverride(key: key), source: .installed, locations: store.locations,
                display: display, problem: error.localizedDescription
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case vendorID, productID, path, source, connectedDisplay, connectedDisplayID, productName, entries, problem
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vendorID, forKey: .vendorID)
        try container.encode(productID, forKey: .productID)
        try container.encode(path, forKey: .path)
        try container.encode(source, forKey: .source)
        try container.encode(connectedDisplay, forKey: .connectedDisplay)
        try container.encode(connectedDisplayID, forKey: .connectedDisplayID)
        try container.encode(productName, forKey: .productName)
        try container.encode(entries, forKey: .entries)
        try container.encode(problem, forKey: .problem)
    }

    var text: String {
        let origin = switch source {
        case "installed": "installed"
        case "system": "shipped with macOS, not installed"
        default: "no override yet"
        }
        var lines = [path]
        lines.append("  vendor \(vendorID), product \(productID), \(connectedDisplay.map { "connected: \($0)" } ?? "not connected"), \(origin)")
        if let productName { lines.append("  name: \(productName)") }
        if let problem { lines.append("  problem: \(problem)") }
        if entries.isEmpty, problem == nil { lines.append("  no custom resolutions") }
        lines += entries.map { "  • \($0.summary)" }
        return lines.joined(separator: "\n")
    }
}
