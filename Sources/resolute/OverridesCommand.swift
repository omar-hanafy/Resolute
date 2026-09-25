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
            Every change backs up the file it replaces; `backups` lists them and `restore` puts one back.
            """,
        subcommands: [
            ListOverrides.self, ShowOverride.self, AddResolution.self, RemoveResolution.self, ResetOverride.self,
            ListBackups.self, RestoreBackup.self, PruneBackups.self,
        ],
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
            context.write("No overrides in \(Output.folder(store.locations.userRoot)).")
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
            let file = try OverrideStore(locations: location.locations).editableFile(for: target.key)
            var draft = OverrideDraft(file.override)
            let alsoAdded = try draft.add(newEntry)
            // The lock keeps other Resolute commands out; this also catches another tool.
            let url = try await installer.install(draft.working, expecting: file.installedState)
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
            let file = try store.editableFile(for: target.key)
            guard file.source != .missing else {
                throw ResoluteError.invalidEntry("There is no override for \(target), so there is nothing to remove.")
            }
            var draft = OverrideDraft(file.override)
            let matches = draft.working.resolutions.filter { $0.sameMode(as: unwanted) }
            guard !matches.isEmpty else {
                throw ResoluteError.invalidEntry(missingMessage(for: unwanted, in: draft.working, target: target))
            }
            draft.remove(matches)
            let url = try await installer.install(draft.working, expecting: file.installedState)
            let count = matches.count > 1 ? " (\(matches.count) entries)" : ""
            context.write("Removed \(unwanted.sizeText) \(unwanted.kindText)\(count) for \(target).")
            for entry in draft.newlyUnpairedHiDPIEntries {
                guard let pixels = entry.pixelSize else { continue }
                context.write(
                    "\(entry.sizeText) HiDPI no longer has its 1× entry at \(pixels.width) × \(pixels.height), "
                        + "which Resolute and RDM add with each HiDPI entry. To put it back: "
                        + location.command("overrides add \(pixels.width)x\(pixels.height)@1x\(self.target.arguments)", isRoot: context.isRoot)
                )
            }
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
            let state = try OverrideStore(locations: location.locations).installedState(for: target.key)
            try await installer.remove(target.key, expecting: state)
            return true
        }
        guard removed else {
            context.write(Self.nothingToRemove(for: target))
            return
        }
        let folder = Output.folder(installer.locations.backupFolder(for: target.key))
        context.write("Removed the override for \(target). A backup is in \(folder).")
        context.write("To undo it: " + location.command("overrides restore 1\(self.target.arguments)", isRoot: context.isRoot))
        context.write(OverridesCommand.reconnectHint)
    }

    static func nothingToRemove(for target: OverrideTarget) -> String {
        "There is no custom override for \(target), so there is nothing to remove."
    }
}

struct ListBackups: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "backups",
        abstract: "List the backups of a display's override, newest first."
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
        let summaries = store.backups(for: target.key).enumerated().map { BackupSummary(number: $0.offset + 1, backup: $0.element, store: store) }
        if json {
            context.write(try Output.json(summaries))
            return
        }
        let folder = Output.folder(store.locations.backupFolder(for: target.key))
        guard !summaries.isEmpty else {
            context.write("There are no backups of \(target) in \(folder).")
            return
        }
        context.write("Backups of \(target), newest first, in \(folder):")
        context.write(Output.table(summaries.map { ["\($0.number)", Output.localTime($0.backup.date), $0.contentsText, $0.fileName] }, indent: "  "))
        // Restoring writes to /Library, so it needs sudo whoever runs this.
        context.write("To restore one: " + location.command("overrides restore <number>\(self.target.arguments)", isRoot: true))
    }
}

struct RestoreBackup: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "restore",
        abstract: "Put back a backup of a display's override.",
        discussion: "Name the backup by its number in `resolute overrides backups` (1 is the newest) or by its file name. "
            + "The override it replaces is backed up first, so a restore can be undone the same way."
    )

    @Argument(help: "A number from `resolute overrides backups`, or a backup's file name.")
    var backup: String

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let target = try target.target(in: context)
        let store = OverrideStore(locations: location.locations)
        let chosen = try Self.pick(backup, from: store.backups(for: target.key), target: target)
        // Written back as it is, so a backup Resolute cannot show is restored too.
        let data = try store.restorableContents(of: chosen).data
        // Nothing to change needs no administrator rights, so check before asking for them.
        guard try store.installedState(for: target.key) != .contents(data) else {
            context.write(Self.alreadyMatches(chosen, target: target))
            return
        }
        let installer = try location.installer(in: context)
        try await location.withLock(in: context) {
            let current = try store.installedState(for: target.key)
            guard current != .contents(data) else {
                context.write(Self.alreadyMatches(chosen, target: target))
                return
            }
            let url = try await installer.install(contents: data, for: target.key, expecting: current)
            context.write("Restored \(chosen.fileName), from \(Output.localTime(chosen.date)), for \(target).")
            let saved = "Saved \(url.path(percentEncoded: false))."
            context.write(current == .absent ? saved : saved + " The override it replaced is backed up too.")
            context.write(OverridesCommand.reconnectHint)
        }
    }

    /// The backup `text` names: a number from `overrides backups`, or a file name. A path
    /// counts by its name only, so nothing outside the backup folder is ever read.
    static func pick(_ text: String, from backups: [OverrideBackup], target: OverrideTarget) throws -> OverrideBackup {
        let listing = "List them with `resolute overrides backups`."
        guard !backups.isEmpty else { throw ResoluteError.invalidEntry("There are no backups of \(target).") }
        if let number = Int(text) {
            guard (1...backups.count).contains(number) else {
                let count = backups.count == 1 ? "there is 1" : "there are \(backups.count)"
                throw ResoluteError.invalidEntry("There is no backup \(number) of \(target): \(count). \(listing)")
            }
            return backups[number - 1]
        }
        let name = URL(filePath: text).lastPathComponent
        guard let match = backups.first(where: { $0.fileName == name }) else {
            throw ResoluteError.invalidEntry("There is no backup named “\(text)” of \(target). \(listing)")
        }
        return match
    }

    static func alreadyMatches(_ backup: OverrideBackup, target: OverrideTarget) -> String {
        "The override for \(target) already matches \(backup.fileName), so nothing changed."
    }
}

struct PruneBackups: AsyncParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Delete all but the newest backups of a display's override.",
        discussion: "With --all, prunes the backups of every display, connected or not."
    )

    @Option(help: "How many of the newest backups to keep.")
    var keep = 10

    @Flag(help: "Prune the backups of every display.")
    var all = false

    @OptionGroup var target: OverrideTargetOptions
    @OptionGroup var location: LocationOptions

    func validate() throws {
        guard keep >= 0 else { throw ValidationError("--keep takes 0 or more.") }
        if all, target.display != nil || target.vendor != nil {
            throw ValidationError("Pass either --all or one display.")
        }
    }

    func run() async throws {
        try await run(in: .live)
    }

    func run(in context: CommandContext) async throws {
        let store = OverrideStore(locations: location.locations)
        let displays = context.service.displays()
        let targets = all
            ? store.backupKeys().map { key in OverrideTarget(key: key, display: displays.first { OverrideKey(display: $0) == key }) }
            : [try target.target(in: context)]
        // Nothing to remove needs no administrator rights, so check before asking for them.
        guard targets.contains(where: { store.backups(for: $0.key).count > keep }) else {
            if targets.isEmpty { context.write("There are no backups in \(Output.folder(store.locations.backupRoot)).") }
            targets.forEach { context.write(nothingToRemove(for: $0, count: store.backups(for: $0.key).count)) }
            return
        }
        let installer = try location.installer(in: context)
        try await location.withLock(in: context) {
            for target in targets {
                let backups = store.backups(for: target.key)
                guard backups.count > keep else {
                    context.write(nothingToRemove(for: target, count: backups.count))
                    continue
                }
                let unwanted = Array(backups.dropFirst(keep))
                try await installer.removeBackups(unwanted)
                let kept = keep == 0 ? "none" : "the newest \(keep)"
                context.write("Removed \(Self.count(unwanted.count)) of \(target), and kept \(kept).")
            }
        }
    }

    func nothingToRemove(for target: OverrideTarget, count: Int) -> String {
        "Nothing to remove: \(target) has \(count == 0 ? "no backups" : Self.count(count))."
    }

    /// "1 backup", "3 backups"
    static func count(_ number: Int) -> String {
        number == 1 ? "1 backup" : "\(number) backups"
    }
}

/// A backup as `overrides backups` lists it.
struct BackupSummary: Encodable {
    let number: Int
    let backup: OverrideBackup
    let entries: Int?
    let productName: String?
    let problem: String?
    /// False when `restore` would refuse it: it is gone, or macOS could not read it either.
    let isRestorable: Bool

    init(number: Int, backup: OverrideBackup, store: OverrideStore) {
        self.number = number
        self.backup = backup
        do {
            let contents = try store.restorableContents(of: backup)
            entries = contents.override?.resolutions.count
            productName = contents.override?.productName
            problem = contents.problem.map {
                ResoluteError.overrideUnreadable(path: backup.file.path(percentEncoded: false), reason: $0).localizedDescription
            }
            isRestorable = true
        } catch {
            entries = nil
            productName = nil
            problem = error.localizedDescription
            isRestorable = false
        }
    }

    var fileName: String { backup.fileName }

    /// "2 entries", "1 entry, named “Studio”", or why it cannot be read.
    var contentsText: String {
        guard let entries else { return isRestorable ? "can’t show its entries" : "can’t be read" }
        let count = entries == 1 ? "1 entry" : "\(entries) entries"
        return productName.map { "\(count), named “\($0)”" } ?? count
    }

    enum CodingKeys: String, CodingKey {
        case number, date, fileName, path, entries, productName, problem
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(number, forKey: .number)
        try container.encode(ISO8601DateFormatter().string(from: backup.date), forKey: .date)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(backup.file.path(percentEncoded: false), forKey: .path)
        try container.encode(entries, forKey: .entries)
        try container.encode(productName, forKey: .productName)
        try container.encode(problem, forKey: .problem)
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
