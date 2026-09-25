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
    var lock: OverrideLock {
        OverrideLock(file: locations.lockFile)
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

    func entry(flags: HiDPIFlags? = nil) throws -> ScaleResolution {
        try ScaleResolution(parsing: resolution, standard: standard, flags: flags)
    }

    /// Reports a malformed entry as a usage error. Only something shaped like a size is
    /// checked: a bare word is more likely the value of a mistyped option, which
    /// ArgumentParser reports after validation.
    func validate(flags: String? = nil) throws {
        guard Output.looksLikeSize(resolution) else { return }
        do {
            _ = try entry(flags: try flags.map { try HiDPIFlags(parsing: $0) })
        } catch {
            throw ValidationError(error.localizedDescription)
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

    @Option(help: "HiDPI flags as two hex words (default 00000009 00a00000).")
    var flags: String?

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func validate() throws {
        try entry.validate(flags: flags)
    }

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let newEntry = try entry.entry(flags: try flags.map { try HiDPIFlags(parsing: $0) })
        let target = try target.target(in: context)
        let installer = try location.installer(in: context)
        try await location.lock.withLock {
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
        abstract: "Remove a custom resolution from a display's override."
    )

    @OptionGroup var entry: EntryOptions
    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func validate() throws {
        try entry.validate()
    }

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let unwanted = try entry.entry()
        let target = try target.target(in: context)
        let installer = try location.installer(in: context)
        try await location.lock.withLock {
            guard let installed = try OverrideStore(locations: location.locations).installedOverride(for: target.key) else {
                throw ResoluteError.invalidEntry("There is no custom override for \(target).")
            }
            var draft = OverrideDraft(installed)
            let matches = draft.working.resolutions.filter { $0.sameMode(as: unwanted) }
            guard !matches.isEmpty else {
                throw ResoluteError.invalidEntry("\(unwanted.sizeText) \(unwanted.kindText) is not in the override for \(target).")
            }
            draft.remove(matches)
            let url = try await installer.install(draft.working)
            context.write("Removed \(unwanted.sizeText) \(unwanted.kindText) for \(target).")
            // Entries read from a file are never removed implicitly; say what stays.
            if case .hiDPI = unwanted, let pixels = unwanted.pixelSize,
               draft.working.resolutions.contains(.standard(width: pixels.width, height: pixels.height)) {
                context.write(
                    "\(pixels.width) × \(pixels.height) 1× stays in the override. To remove it too: "
                        + "resolute overrides remove \(pixels.width)x\(pixels.height)@1x\(self.target.arguments)"
                )
            }
            context.write("Saved \(url.path(percentEncoded: false))")
            context.write(OverridesCommand.reconnectHint)
        }
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
        guard FileManager.default.fileExists(atPath: file) else {
            context.write("There is no custom override for \(target), so there is nothing to remove.")
            return
        }
        let installer = try location.installer(in: context)
        try await location.lock.withLock {
            try await installer.remove(target.key)
        }
        context.write(
            "Removed the override for \(target). A backup is in \(installer.locations.backupRoot.path(percentEncoded: false))"
        )
        context.write(OverridesCommand.reconnectHint)
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
        if entries.isEmpty { lines.append("  no custom resolutions") }
        lines += entries.map { "  • \($0.summary)" }
        return lines.joined(separator: "\n")
    }
}
