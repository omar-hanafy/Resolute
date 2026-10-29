import CryptoKit
import Foundation

/// What Sharp Scaling saved for a display, kept in the display's override file under `key`.
///
/// It lives in the override file rather than in Resolute's support folder because it
/// describes that file. The same privileged, backed-up install writes it with the sizes, so
/// the two never disagree. It is system-wide like the override, so the app and `resolute`,
/// with sudo or without, read the same one. And it goes away with the file when an earlier
/// backup is restored or the override is removed, so it never claims sizes that are gone.
/// Resolute's override editors keep keys they don't know, and macOS ignores them.
public struct SharpScalingRecord: Hashable, Sendable {
    /// The override key the record is kept under.
    public static let key = "ResoluteSharpScaling"
    /// The record's format. A newer one is refused rather than misread.
    public static let version = 1

    /// The override before Sharp Scaling first changed it, so turning it off can put it back.
    public struct Original: Hashable, Sendable {
        /// Where it came from: a file of its own, the file macOS ships, or nowhere.
        public var source: OverrideStore.Source
        /// The SHA-256 of the installed file Sharp Scaling replaced, which finds that file's
        /// backup; nil when it replaced none.
        public var backupDigest: String?
        /// The SHA-256 of its contents (see `fingerprint(of:)`), so turning Sharp Scaling
        /// off can tell whether anything else changed the file since.
        public var fingerprint: String

        public init(source: OverrideStore.Source, backupDigest: String?, fingerprint: String) {
            self.source = source
            self.backupDigest = backupDigest
            self.fingerprint = fingerprint
        }
    }

    /// When the sizes were last written.
    public var saved: Date
    /// The sharp sizes, Larger Text first.
    public var sizes: [SharpSize]
    /// The sizes Sharp Scaling wrote. The others were in the file already, and stay in it
    /// when Sharp Scaling is turned off.
    public var added: [SharpSize]
    /// The 1× entries Sharp Scaling wrote with its sizes.
    public var partners: [ScaleResolution]
    /// The sizes macOS offered when they were written. One it offers now that it didn't
    /// then shows that the display has read the file since.
    public var offered: [SharpSize]
    /// The size to switch to once macOS offers it, when that was asked for.
    public var switchTo: SharpSize?
    public var original: Original

    public init(
        saved: Date,
        sizes: [SharpSize],
        added: [SharpSize],
        partners: [ScaleResolution],
        offered: [SharpSize],
        switchTo: SharpSize?,
        original: Original
    ) {
        self.saved = saved
        self.sizes = sizes
        self.added = added
        self.partners = partners
        self.offered = offered
        self.switchTo = switchTo
        self.original = original
    }

    /// The record in `override`; nil when it has none. One that can't be read throws, rather
    /// than passing for Sharp Scaling being off and losing what it saved.
    public init?(in override: DisplayOverride) throws {
        guard let value = override.otherKeys.dictionary[Self.key] else { return nil }
        let damaged = ResoluteError.overrideUnreadable(
            path: override.key.relativePath,
            reason: "its Sharp Scaling record is damaged. resolute overrides backups lists earlier versions of the file to restore"
        )
        guard let list = value as? [String: Any], let version = list["version"] as? Int, version >= 1 else { throw damaged }
        guard version <= Self.version else {
            throw ResoluteError.overrideUnreadable(
                path: override.key.relativePath, reason: "its Sharp Scaling record comes from a newer version of Resolute"
            )
        }
        func sizes(_ name: String) throws -> [SharpSize] {
            guard let texts = list[name] as? [String] else { throw damaged }
            return try texts.map { text in
                guard let size = SharpSize(text) else { throw damaged }
                return size
            }
        }
        guard let saved = list["saved"] as? Date,
              let original = list["original"] as? [String: Any],
              let source = (original["source"] as? String).flatMap(Self.source(named:)),
              let fingerprint = original["contents"] as? String
        else { throw damaged }
        let backup = original["backup"]
        guard backup == nil || backup is String else { throw damaged }
        let switchTo = list["switch"]
        guard switchTo == nil || (switchTo as? String).flatMap(SharpSize.init) != nil else { throw damaged }
        self.init(
            saved: saved,
            sizes: try sizes("sizes"),
            added: try sizes("added"),
            partners: try sizes("partners").map { .standard(width: $0.width, height: $0.height) },
            offered: try sizes("offered"),
            switchTo: (switchTo as? String).flatMap(SharpSize.init),
            original: Original(source: source, backupDigest: backup as? String, fingerprint: fingerprint)
        )
    }

    /// The record as the property list kept in the override.
    var propertyList: [String: Any] {
        var original: [String: Any] = ["source": Self.name(of: self.original.source), "contents": self.original.fingerprint]
        if let backupDigest = self.original.backupDigest { original["backup"] = backupDigest }
        var list: [String: Any] = [
            "version": Self.version,
            "saved": saved,
            "sizes": sizes.map(\.description),
            "added": added.map(\.description),
            "partners": partners.compactMap { $0.pixelSize.map { "\($0.width)x\($0.height)" } },
            "offered": offered.map(\.description),
            "original": original,
        ]
        if let switchTo { list["switch"] = switchTo.description }
        return list
    }

    /// `override` holding this record, in place of any it had.
    public func written(into override: DisplayOverride) -> DisplayOverride {
        var result = override
        var keys = result.otherKeys.dictionary
        keys[Self.key] = propertyList
        result.otherKeys = PropertyListDictionary(keys)
        return result
    }

    /// `override` without a record.
    public static func removed(from override: DisplayOverride) -> DisplayOverride {
        var result = override
        var keys = result.otherKeys.dictionary
        guard keys.removeValue(forKey: key) != nil else { return override }
        result.otherKeys = PropertyListDictionary(keys)
        return result
    }

    /// The SHA-256 of `override`'s contents as Resolute writes them, leaving out a record.
    /// Property-list XML lists keys in order, so equal contents give equal fingerprints
    /// whatever order their keys were read in.
    public static func fingerprint(of override: DisplayOverride) throws -> String {
        var keys = override.otherKeys.dictionary
        keys.merge(override.picture.dictionary) { _, picture in picture }
        keys.removeValue(forKey: key)
        if let name = override.productName, !name.isEmpty {
            keys[DisplayOverride.productNameKey] = name
        }
        let entries = try ScaleResolutionCodec.encode(override.resolutions)
        if !entries.isEmpty {
            keys[DisplayOverride.resolutionsKey] = entries
        }
        return digest(try PropertyListSerialization.data(fromPropertyList: keys, format: .xml, options: 0))
    }

    /// The SHA-256 of `data`, in lowercase hex.
    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func name(of source: OverrideStore.Source) -> String {
        switch source {
        case .installed: "installed"
        case .system: "system"
        case .missing: "missing"
        }
    }

    private static func source(named name: String) -> OverrideStore.Source? {
        switch name {
        case "installed": .installed
        case "system": .system
        case "missing": .missing
        default: nil
        }
    }
}
