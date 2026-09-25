import ArgumentParser
import Foundation
import ResoluteKit

struct OverridesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "overrides",
        abstract: "Inspect and edit custom resolutions in /Library/Displays.",
        discussion: """
            Changes apply after the display is reconnected or the Mac restarts.
            Commands that write need administrator rights: run them with sudo.
            """,
        subcommands: [ListOverrides.self, ShowOverride.self, AddResolution.self, RemoveResolution.self, ResetOverride.self],
        defaultSubcommand: ListOverrides.self
    )
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
}

/// Which display's override to use.
struct OverrideTargetOptions: ParsableArguments {
    @Option(name: [.short, .long], help: "A connected display: main, an index, id:<number>, or part of its name.")
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
    }

    func key(in context: CommandContext) throws -> OverrideKey {
        if let vendor, let product {
            guard let vendorID = Self.hex(vendor), let productID = Self.hex(product) else {
                throw ValidationError("--vendor and --product take hexadecimal IDs, for example db4 and 3401.")
            }
            return OverrideKey(vendorID: vendorID, productID: productID)
        }
        let displays = context.service.displays()
        return OverrideKey(display: try DisplaySelector(display ?? "main").resolve(in: displays))
    }

    private static func hex(_ text: String) -> UInt32? {
        UInt32(text.lowercased().hasPrefix("0x") ? String(text.dropFirst(2)) : text, radix: 16)
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
        let key = try target.key(in: context)
        let store = OverrideStore(locations: location.locations)
        let (override, source) = try store.editableOverride(for: key)
        let display = context.service.displays().first { OverrideKey(display: $0) == key }
        let summary = OverrideSummary(key: key, override: override, source: source, locations: store.locations, display: display)
        context.write(json ? try Output.json(summary) : summary.text)
    }
}

struct AddResolution: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a custom resolution to a display's override.")

    @OptionGroup var entry: EntryOptions

    @Option(help: "HiDPI flags as two hex words (default 00000009 00a00000).")
    var flags: String?

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let installer = try location.installer(in: context)
        let key = try target.key(in: context)
        var draft = OverrideDraft(try OverrideStore(locations: location.locations).editableOverride(for: key).override)
        let newEntry = try entry.entry(flags: try flags.map { try HiDPIFlags(parsing: $0) })
        try draft.add(newEntry)
        let url = try await installer.install(draft.working)
        context.write("Added \(newEntry.summary) to \(url.path(percentEncoded: false))")
        context.write("Reconnect the display or restart the Mac to use it.")
    }
}

struct RemoveResolution: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove a custom resolution from a display's override.")

    @OptionGroup var entry: EntryOptions
    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let installer = try location.installer(in: context)
        let key = try target.key(in: context)
        guard let installed = try OverrideStore(locations: location.locations).installedOverride(for: key) else {
            throw ResoluteError.invalidEntry("There is no installed override for \(key).")
        }
        let unwanted = try entry.entry()
        var draft = OverrideDraft(installed)
        let matches = draft.working.resolutions.filter { $0.sameMode(as: unwanted) }
        guard !matches.isEmpty else {
            throw ResoluteError.invalidEntry("\(unwanted.sizeText) (\(unwanted.kindText)) is not in the override.")
        }
        draft.remove(matches)
        let url = try await installer.install(draft.working)
        context.write("Removed \(unwanted.sizeText) (\(unwanted.kindText)) from \(url.path(percentEncoded: false))")
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
        let installer = try location.installer(in: context)
        let key = try target.key(in: context)
        try await installer.remove(key)
        context.write("Removed the override for \(key). Backups are in \(installer.locations.backupRoot.path(percentEncoded: false))")
    }
}

/// An override as `overrides list` and `overrides show` print it.
struct OverrideSummary: Encodable {
    struct Entry: Encodable {
        let kind: String
        let width: Int?
        let height: Int?
        let pixelWidth: Int?
        let pixelHeight: Int?
        let flags: String?
        let summary: String

        init(_ entry: ScaleResolution) {
            switch entry {
            case .hiDPI(let width, let height, let flags):
                kind = "hidpi"
                self.width = width
                self.height = height
                pixelWidth = width * 2
                pixelHeight = height * 2
                self.flags = flags.description
            case .standard(let width, let height):
                kind = "standard"
                self.width = width
                self.height = height
                pixelWidth = width
                pixelHeight = height
                flags = nil
            case .preserved:
                kind = "preserved"
                width = nil
                height = nil
                pixelWidth = nil
                pixelHeight = nil
                flags = nil
            }
            summary = entry.summary
        }
    }

    let vendorID: String
    let productID: String
    let path: String
    let source: String
    let connectedDisplay: String?
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
            self.source = "macOS"
        case .missing:
            path = locations.userFile(for: key).path(percentEncoded: false)
            self.source = "none"
        }
        connectedDisplay = display?.name
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
        case "macOS": "shipped with macOS, not installed"
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
