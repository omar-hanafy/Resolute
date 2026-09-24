import Foundation

/// Where override files and their backups live.
public struct OverrideLocations: Hashable, Sendable {
    /// Overrides Resolute writes.
    public var userRoot: URL
    /// Overrides that ship with macOS (read only).
    public var systemRoot: URL
    /// Copies of the files Resolute replaced or removed.
    public var backupRoot: URL

    public init(userRoot: URL, systemRoot: URL, backupRoot: URL) {
        self.userRoot = userRoot
        self.systemRoot = systemRoot
        self.backupRoot = backupRoot
    }

    public static let standard = OverrideLocations(
        userRoot: URL(filePath: "/Library/Displays/Contents/Resources/Overrides", directoryHint: .isDirectory),
        systemRoot: URL(filePath: "/System/Library/Displays/Contents/Resources/Overrides", directoryHint: .isDirectory),
        backupRoot: URL(filePath: "/Library/Application Support/Resolute/Backups", directoryHint: .isDirectory)
    )

    /// Every location inside `root`, for staging and tests.
    public static func staged(at root: URL) -> OverrideLocations {
        OverrideLocations(
            userRoot: root.appending(path: "Overrides", directoryHint: .isDirectory),
            systemRoot: root.appending(path: "System", directoryHint: .isDirectory),
            backupRoot: root.appending(path: "Backups", directoryHint: .isDirectory)
        )
    }

    public func userFile(for key: OverrideKey) -> URL {
        file(for: key, in: userRoot)
    }

    public func systemFile(for key: OverrideKey) -> URL {
        file(for: key, in: systemRoot)
    }

    private func file(for key: OverrideKey, in root: URL) -> URL {
        root.appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
            .appending(path: key.productFileName, directoryHint: .notDirectory)
    }
}

/// Reads override files.
public struct OverrideStore: Sendable {
    /// Where an editable override came from.
    public enum Source: Hashable, Sendable {
        /// A file under the user root (written by Resolute, RDM or another tool).
        case installed
        /// The file macOS ships for this display.
        case system
        /// No file exists yet.
        case missing
    }

    public var locations: OverrideLocations

    public init(locations: OverrideLocations = .standard) {
        self.locations = locations
    }

    public func installedOverride(for key: OverrideKey) throws -> DisplayOverride? {
        try read(locations.userFile(for: key), key: key)
    }

    public func systemOverride(for key: OverrideKey) throws -> DisplayOverride? {
        try read(locations.systemFile(for: key), key: key)
    }

    /// What editing starts from: the installed override, else Apple's file, else nothing.
    public func editableOverride(for key: OverrideKey) throws -> (override: DisplayOverride, source: Source) {
        if let installed = try installedOverride(for: key) { return (installed, .installed) }
        if let system = try systemOverride(for: key) { return (system, .system) }
        return (DisplayOverride(key: key), .missing)
    }

    /// Displays with an override under the user root.
    public func installedKeys() -> [OverrideKey] {
        let fileManager = FileManager.default
        guard let vendors = try? fileManager.contentsOfDirectory(atPath: locations.userRoot.path(percentEncoded: false)) else {
            return []
        }
        var keys: [OverrideKey] = []
        for vendor in vendors {
            let directory = locations.userRoot.appending(path: vendor, directoryHint: .isDirectory)
            let products = (try? fileManager.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            keys += products.compactMap { OverrideKey(vendorDirectory: vendor, productFile: $0) }
        }
        return keys.sorted()
    }

    private func read(_ url: URL, key: OverrideKey) throws -> DisplayOverride? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        do {
            return try DisplayOverride(key: key, propertyList: Data(contentsOf: url))
        } catch ResoluteError.overrideUnreadable(_, let reason) {
            throw ResoluteError.overrideUnreadable(path: path, reason: reason)
        } catch {
            throw ResoluteError.overrideUnreadable(path: path, reason: "it is not a valid property list")
        }
    }
}
