import Foundation

/// An override being edited: the saved version and the working copy.
public struct OverrideDraft: Equatable, Sendable {
    public private(set) var saved: DisplayOverride
    public var working: DisplayOverride

    public init(_ override: DisplayOverride) {
        saved = override
        working = override
    }

    public var hasChanges: Bool { working != saved }

    /// Adds an entry after checking it is sensible and not already listed.
    ///
    /// A HiDPI entry is written together with a 1× entry at its pixel size, and a file read
    /// back lists that pair as the HiDPI entry alone. So a 1× entry some HiDPI entry already
    /// writes is refused, and a 1× entry the new HiDPI entry will write is folded into it:
    /// the list then shows what reopening the saved file will show. Returns the folded entries.
    @discardableResult
    public mutating func add(_ entry: ScaleResolution) throws -> [ScaleResolution] {
        try Self.validate(entry)
        if working.resolutions.contains(where: { $0.sameMode(as: entry) }) {
            throw ResoluteError.invalidEntry("\(entry.sizeText) (\(entry.kindText)) is already in the list.")
        }
        if let writer = hiDPIEntry(writing: entry) {
            throw ResoluteError.invalidEntry(
                "\(entry.sizeText) (1×) is already there: it is written with the HiDPI entry \(writer.sizeText)."
            )
        }
        var folded: [ScaleResolution] = []
        if case .hiDPI = entry, let pixels = entry.pixelSize {
            folded = working.resolutions.filter { $0 == .standard(width: pixels.width, height: pixels.height) }
            working.resolutions.removeAll { folded.contains($0) }
        }
        working.resolutions.append(entry)
        return folded
    }

    /// The HiDPI entry that writes the 1× `entry` as its backing, if there is one.
    public func hiDPIEntry(writing entry: ScaleResolution) -> ScaleResolution? {
        guard case .standard(let width, let height) = entry else { return nil }
        return working.resolutions.first { candidate in
            guard case .hiDPI = candidate, let pixels = candidate.pixelSize else { return false }
            return pixels.width == width && pixels.height == height
        }
    }

    public mutating func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where working.resolutions.indices.contains(index) {
            working.resolutions.remove(at: index)
        }
    }

    public mutating func revert() {
        working = saved
    }

    public mutating func markSaved() {
        saved = working
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
