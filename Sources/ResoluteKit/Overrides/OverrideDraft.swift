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
    public mutating func add(_ entry: ScaleResolution) throws {
        try Self.validate(entry)
        if working.resolutions.contains(where: { $0.sameMode(as: entry) }) {
            throw ResoluteError.invalidEntry("\(entry.sizeText) (\(entry.kindText)) is already in the list.")
        }
        working.resolutions.append(entry)
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
            guard width >= 320, height >= 200, width * 2 <= maximumPixels, height * 2 <= maximumPixels else {
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
