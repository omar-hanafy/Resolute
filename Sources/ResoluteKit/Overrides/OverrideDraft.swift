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

    public var hasChanges: Bool { working != saved }

    /// Adds an entry after checking it is sensible and not already listed. A HiDPI entry is
    /// paired with a 1× entry at its pixel size, as RDM wrote them, unless the list has one.
    /// Returns the entries added besides `entry`.
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
        working.resolutions = ScaleResolutionCodec.canonicalOrder(working.resolutions + [entry] + alsoAdded)
        return alsoAdded
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

    static func validate(_ entry: ScaleResolution) throws {
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
