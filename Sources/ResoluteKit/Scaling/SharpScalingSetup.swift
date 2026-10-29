import Foundation

/// Turning Sharp Scaling on for a display, or changing its sizes: the override to write.
public struct SharpScalingSetup: Sendable {
    /// The display's override with the sharp sizes, their 1× entries and the record.
    public var override: DisplayOverride
    public var record: SharpScalingRecord
    /// The sizes this change writes.
    public var added: [SharpSize]
    /// The sizes an earlier setup wrote that this change takes out.
    public var removed: [SharpSize]
    /// True when the display has an installed file, which installing backs up first.
    public var replacesFile: Bool
    /// False when the file holds Sharp Scaling with these sizes already: nothing to write.
    public var hasChanges: Bool

    /// Merges `sizes` into the override in `file`, keeping its other entries and keys. Each
    /// size gets a HiDPI entry and, as the Custom Resolutions editor adds them, the 1× entry
    /// at its drawn size unless the file lists one. A size the file lists already stays the
    /// file's own. When Sharp Scaling was on, sizes it wrote that `sizes` leaves out come out,
    /// and what the file was before Sharp Scaling first changed it is kept on record.
    ///
    /// - Parameters:
    ///   - file: the display's override as `OverrideStore.editableFile(for:)` read it.
    ///   - sizes: the sharp sizes wanted, at least one.
    ///   - offered: those macOS offers now (`SharpScalingStatus.isOffered(_:on:)`).
    ///   - switchTo: the size to switch to once macOS offers it, if asked for.
    ///   - now: when the sizes are saved.
    public init(file: OverrideStore.EditableOverride, sizes: [SharpSize], offered: [SharpSize], switchTo: SharpSize?, now: Date) throws {
        let wanted = Set(sizes).sorted()
        guard !wanted.isEmpty else { throw ResoluteError.invalidEntry("Choose at least one sharp size.") }
        let previous = try SharpScalingRecord(in: file.override)

        var working = file.override
        var partners = previous?.partners ?? []
        let dropped = (previous?.added ?? []).filter { !wanted.contains($0) }
        for size in dropped {
            working.resolutions.removeAll { $0.sameMode(as: size.entry) }
            // Only a 1× entry Sharp Scaling wrote goes with its size.
            guard partners.contains(where: { $0.sameMode(as: size.partner) }) else { continue }
            working.resolutions.removeAll { $0.sameMode(as: size.partner) }
            partners.removeAll { $0.sameMode(as: size.partner) }
        }

        var draft = OverrideDraft(working)
        var added: [SharpSize] = []
        for size in wanted where !draft.working.resolutions.contains(where: { $0.sameMode(as: size.entry) }) {
            partners += try draft.add(size.entry)
            added.append(size)
        }

        let original: SharpScalingRecord.Original
        if let previous {
            original = previous.original
        } else {
            var backupDigest: String?
            if case .contents(let data) = file.installedState { backupDigest = SharpScalingRecord.digest(data) }
            original = SharpScalingRecord.Original(
                source: file.source, backupDigest: backupDigest, fingerprint: try SharpScalingRecord.fingerprint(of: file.override)
            )
        }
        let wroteBefore = Set(previous?.added ?? [])
        record = SharpScalingRecord(
            saved: now,
            sizes: wanted,
            added: wanted.filter { wroteBefore.contains($0) || added.contains($0) },
            partners: partners,
            offered: wanted.filter { offered.contains($0) },
            switchTo: switchTo,
            original: original
        )
        override = record.written(into: draft.working)
        self.added = added
        removed = dropped
        replacesFile = file.installedState != .absent
        hasChanges = previous?.sizes != wanted || !added.isEmpty || !dropped.isEmpty
    }
}
