import Foundation

/// Turning Sharp Scaling off: how a display's override goes back to what it was.
public enum SharpScalingRemoval: Sendable {
    /// Why the rest of the file stays instead of the file from before Sharp Scaling.
    public enum Reason: Hashable, Sendable {
        /// Something else changed the file after Sharp Scaling wrote it.
        case changedSince
        /// Nothing did, but the backup from before Sharp Scaling is gone.
        case backupMissing
    }

    /// Put back the backup made when Sharp Scaling first wrote the file, byte for byte.
    case restore(OverrideBackup, contents: Data)
    /// Delete the file: there was none before Sharp Scaling, and nothing else changed it since.
    case remove
    /// Write the file without Sharp Scaling's sizes, the 1× entries it wrote with them and
    /// its record, keeping the rest.
    case strip(DisplayOverride, Reason)

    /// How to turn Sharp Scaling off in `installed`, a display's installed override; nil when
    /// it has no record. The file from before goes back only when nothing else changed the
    /// file since, so turning off never undoes someone's later edit; sizes that were in the
    /// file before Sharp Scaling stay either way. Backups are looked up in `store`.
    public static func plan(for installed: DisplayOverride, in store: OverrideStore) throws -> SharpScalingRemoval? {
        guard let record = try SharpScalingRecord(in: installed) else { return nil }
        var stripped = SharpScalingRecord.removed(from: installed)
        stripped.resolutions.removeAll { entry in
            record.added.contains { entry.sameMode(as: $0.entry) } || record.partners.contains { entry.sameMode(as: $0) }
        }
        // A file Sharp Scaling created got the target density every new file gets; the
        // nothing it replaced had none.
        let before = record.original.source == .missing ? withoutDefaultDensity(stripped) : stripped
        let unchanged = try SharpScalingRecord.fingerprint(of: before) == record.original.fingerprint
        switch record.original.source {
        case .installed:
            guard unchanged else { return .strip(stripped, .changedSince) }
            if let digest = record.original.backupDigest {
                for backup in store.backups(for: installed.key) {
                    guard let contents = try? store.restorableContents(of: backup),
                          SharpScalingRecord.digest(contents.data) == digest
                    else { continue }
                    return .restore(backup, contents: contents.data)
                }
            }
            return .strip(stripped, .backupMissing)
        case .system, .missing:
            return unchanged ? .remove : .strip(stripped, .changedSince)
        }
    }

    private static func withoutDefaultDensity(_ override: DisplayOverride) -> DisplayOverride {
        var keys = override.otherKeys.dictionary
        guard (keys[DisplayOverride.targetPPMMKey] as? Double) == DisplayOverride.defaultTargetPPMM else { return override }
        keys.removeValue(forKey: DisplayOverride.targetPPMMKey)
        var result = override
        result.otherKeys = PropertyListDictionary(keys)
        return result
    }
}
