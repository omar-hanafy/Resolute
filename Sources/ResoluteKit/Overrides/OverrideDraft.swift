import Foundation

/// An override being edited: the saved version and the working copy.
public struct OverrideDraft: Equatable, Sendable {
    public private(set) var saved: DisplayOverride
    public var working: DisplayOverride
    /// 1× entries `add` put in to go with a HiDPI entry, keyed by that entry. Removing the
    /// HiDPI entry removes its partner too, but only when this draft added it: a file cannot
    /// say why a 1× entry is there, so entries read from one are never removed implicitly.
    private var partners: [ScaleResolution: ScaleResolution] = [:]

    public init(_ override: DisplayOverride) {
        saved = override
        working = override
    }

    /// Whether saving would write something different, as `changes` lists it.
    public var hasChanges: Bool { !changes.isEmpty }

    /// One unsaved change, as the unsaved bar counts them: the picture, the name, and each
    /// entry added or removed, so adding a HiDPI entry with its 1× entry is two changes.
    public enum Change: Hashable, Sendable, CustomStringConvertible {
        case picture
        case name
        case added(ScaleResolution)
        case removed(ScaleResolution)
        /// The same entries in another order, as removing an entry from a list in Apple's
        /// order and adding it back leaves them.
        case reordered
        /// Keys Resolute keeps without editing them, changed by code outside the editors.
        case otherSettings

        /// "picture", "name", "1600 × 900 HiDPI added", "1920 × 1080 1× removed"
        public var description: String {
            switch self {
            case .picture: "picture"
            case .name: "name"
            case .added(let entry): "\(Self.text(for: entry)) added"
            case .removed(let entry): "\(Self.text(for: entry)) removed"
            case .reordered: "order of resolutions"
            case .otherSettings: "other settings"
            }
        }

        private static func text(for entry: ScaleResolution) -> String {
            entry.describedMode == nil ? entry.sizeText : "\(entry.sizeText) \(entry.kindText)"
        }
    }

    /// What saving would change, in the order the editors show it: the picture, the name,
    /// then the entries added and removed.
    public var changes: [Change] {
        var changes: [Change] = []
        if working.picture != saved.picture { changes.append(.picture) }
        // An empty name is not written, so it is the same as none.
        if (working.productName ?? "") != (saved.productName ?? "") { changes.append(.name) }
        let before = Set(saved.resolutions), after = Set(working.resolutions)
        let added = working.resolutions.filter { !before.contains($0) }
        let removed = saved.resolutions.filter { !after.contains($0) }
        changes += added.map(Change.added) + removed.map(Change.removed)
        if added.isEmpty, removed.isEmpty, working.resolutions != saved.resolutions { changes.append(.reordered) }
        if working.otherKeys != saved.otherKeys { changes.append(.otherSettings) }
        return changes
    }

    /// "1 unsaved change: picture" or "2 unsaved changes", for the unsaved bar; nil when
    /// there are none.
    public var changeSummary: String? {
        let changes = changes
        switch changes.count {
        case 0: return nil
        case 1: return "1 unsaved change: \(changes[0])"
        default: return "\(changes.count) unsaved changes"
        }
    }

    // MARK: - Picture and name

    /// The skin the working picture shows (see `DisplayIcons.skin(for:)`).
    public var pictureSkin: String { DisplayIcons.skin(for: working.picture) }

    /// Shows `skin`, one of `DisplayIcons.skins`. Choosing the skin the saved override shows
    /// puts its picture back as it was, so going back to it is no change, even when it was
    /// written from other artwork, or is a picture Resolute did not write (`custom`).
    /// Returns false, changing nothing, when this Mac has no artwork for `skin`.
    @discardableResult
    public mutating func setPicture(skin: String, using icons: DisplayIcons = .system) -> Bool {
        if DisplayIcons.skin(for: working.picture) == skin { return true }
        if DisplayIcons.skin(for: saved.picture) == skin {
            working.picture = saved.picture
            return true
        }
        guard let picture = icons.picture(forSkin: skin) else { return false }
        working.picture = picture
        return true
    }

    public mutating func setPicture(_ picture: DisplayOverride.Picture) {
        working.picture = picture
    }

    /// Sets the name macOS shows. Nil, empty or only spaces keeps the name the display
    /// reports: a blank name would leave the display without one.
    public mutating func setName(_ name: String?) {
        let isBlank = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        working.productName = isBlank ? nil : name
    }

    /// HiDPI entries that this edit left without their 1× entry, because it removed that
    /// entry, or added the HiDPI entry and then removed its partner.
    public var newlyUnpairedHiDPIEntries: [ScaleResolution] {
        let before = Set(saved.unpairedHiDPIEntries)
        return working.unpairedHiDPIEntries.filter { !before.contains($0) }
    }

    /// Adds an entry after checking it is sensible and not already listed. A HiDPI entry is
    /// paired with a 1× entry at its pixel size, as RDM wrote them, unless the list has one.
    /// Returns the entries added besides `entry`. See `inserting(_:into:)` for where they go.
    @discardableResult
    public mutating func add(_ entry: ScaleResolution) throws -> [ScaleResolution] {
        try Self.validate(entry)
        if working.resolutions.contains(where: { $0.sameMode(as: entry) }) {
            throw ResoluteError.invalidEntry("\(entry.sizeText) (\(entry.kindText)) is already in the list.")
        }
        var alsoAdded: [ScaleResolution] = []
        if case .hiDPI = entry, let pixels = entry.pixelSize {
            let partner = ScaleResolution.standard(width: pixels.width, height: pixels.height)
            if !working.resolutions.contains(where: { $0.sameMode(as: partner) }) {
                alsoAdded.append(partner)
                partners[entry] = partner
            }
        }
        working.resolutions = Self.inserting([entry] + alsoAdded, into: working.resolutions)
        return alsoAdded
    }

    /// `entries` added to `list`: where they sort when `list` is in the order Resolute and
    /// RDM write, else after it (sorted among themselves), so a list in another order, such
    /// as a copy of Apple's file, keeps that order.
    static func inserting(_ entries: [ScaleResolution], into list: [ScaleResolution]) -> [ScaleResolution] {
        guard ScaleResolutionCodec.canonicalOrder(list) == list else {
            return list + ScaleResolutionCodec.canonicalOrder(entries)
        }
        return ScaleResolutionCodec.canonicalOrder(list + entries)
    }

    /// Removes `entries`, and the 1× entries this draft added to go with them.
    public mutating func remove(_ entries: [ScaleResolution]) {
        var unwanted = Set(entries)
        for entry in entries {
            if let partner = partners.removeValue(forKey: entry) { unwanted.insert(partner) }
        }
        // A partner removed by hand is no longer this draft's to remove later.
        partners = partners.filter { !unwanted.contains($0.value) }
        working.resolutions.removeAll { unwanted.contains($0) }
    }

    /// Drops every unsaved change: the picture, the name and the entries.
    public mutating func revert() {
        working = saved
        partners = [:]
    }

    /// After a save every entry is in the file, so none is removed implicitly any more.
    public mutating func markSaved() {
        saved = working
        partners = [:]
    }

    /// The largest pixel size Resolute writes to an override.
    static let maximumPixels = 16_384

    /// Throws when `entry` cannot be added: outside the sizes Resolute writes, HiDPI flags
    /// without the HiDPI bit, or an entry Resolute keeps without interpreting.
    public static func validate(_ entry: ScaleResolution) throws {
        switch entry {
        case .hiDPI(let width, let height, let flags):
            // Compared by halving the limit: doubling a huge size would overflow.
            guard width >= 320, height >= 200, width <= maximumPixels / 2, height <= maximumPixels / 2 else {
                throw ResoluteError.invalidEntry("HiDPI resolutions must be between 320 × 200 and 8192 × 8192.")
            }
            guard flags.primary & HiDPIFlags.hiDPIBit != 0 else {
                throw ResoluteError.invalidEntry("HiDPI flags need bit 0 of the first word set.")
            }
        case .standard(let width, let height):
            guard width >= 320, height >= 200, width <= maximumPixels, height <= maximumPixels else {
                throw ResoluteError.invalidEntry("Resolutions must be between 320 × 200 and 16384 × 16384.")
            }
        case .preserved:
            throw ResoluteError.invalidEntry("Only HiDPI and 1× resolutions can be added.")
        }
    }
}
