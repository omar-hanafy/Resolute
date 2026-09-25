import Foundation

/// Combines trusted private mode records with the public CoreGraphics modes.
public enum ModeMerge {
    /// Adds private indexes and bit depths to the public modes, appends each hidden mode
    /// once, and works out the current mode when CoreGraphics reports one it does not list.
    /// `currentPrivateIndex` counts only as a position in `records`: SkyLight can report
    /// one from another list when the display changed or went away after they were read.
    public static func merge(
        systemModes: [DisplayMode],
        records: [PrivateModeRecord],
        hidden: [PrivateModeRecord],
        currentModeID: Int32?,
        currentPrivateIndex: Int32?
    ) -> (modes: [DisplayMode], currentModeID: Int32?) {
        let recordsByID = Dictionary(records.map { ($0.modeID, $0) }, uniquingKeysWith: { first, _ in first })
        var modes = systemModes.map { mode in
            guard let record = recordsByID[mode.modeID] else { return mode }
            var mode = mode
            mode.privateIndex = record.index
            mode.bitsPerSample = record.bitsPerSample
            return mode
        }
        var knownIDs = Set(modes.map(\.modeID))
        for record in hidden where knownIDs.insert(record.modeID).inserted {
            modes.append(record.mode(origin: .hidden))
        }
        var current = currentModeID
        let currentIsListed = current.map { id in modes.contains { $0.modeID == id } } ?? false
        if !currentIsListed, let currentPrivateIndex, records.indices.contains(Int(currentPrivateIndex)),
           let privateCurrent = modes.first(where: { $0.privateIndex == currentPrivateIndex }) {
            current = privateCurrent.modeID
        }
        return (modes, current)
    }

    /// The private index `CGSConfigureDisplayMode` needs for a hidden mode.
    public static func privateIndex(ofHiddenMode modeID: Int32, in hidden: [PrivateModeRecord]) -> Int32? {
        hidden.first { $0.modeID == modeID }?.index
    }
}
