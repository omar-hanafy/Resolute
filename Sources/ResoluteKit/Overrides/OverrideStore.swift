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

/// What an override's file held when it was read, so that a change based on it can check
/// that nothing changed the file in the meantime.
public enum OverrideFileState: Hashable, Sendable {
    case absent
    case contents(Data)
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

    /// An override to edit, where it came from, and what the installed file (the one a
    /// save replaces) held when it was read.
    public struct EditableOverride: Sendable {
        public var override: DisplayOverride
        public var source: Source
        public var installedState: OverrideFileState
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

    /// What the installed file holds now, for a change based on it (see `OverrideInstaller`).
    public func installedState(for key: OverrideKey) throws -> OverrideFileState {
        try contents(of: locations.userFile(for: key)).map(OverrideFileState.contents) ?? .absent
    }

    /// What editing starts from: the installed override, else Apple's file, else nothing,
    /// with the installed file's state from the same read.
    public func editableFile(for key: OverrideKey) throws -> EditableOverride {
        let installed = locations.userFile(for: key)
        if let data = try contents(of: installed) {
            return EditableOverride(override: try parse(data, key: key, at: installed), source: .installed, installedState: .contents(data))
        }
        if let system = try systemOverride(for: key) {
            return EditableOverride(override: system, source: .system, installedState: .absent)
        }
        return EditableOverride(override: DisplayOverride(key: key), source: .missing, installedState: .absent)
    }

    /// What editing starts from: the installed override, else Apple's file, else nothing.
    public func editableOverride(for key: OverrideKey) throws -> (override: DisplayOverride, source: Source) {
        let file = try editableFile(for: key)
        return (file.override, file.source)
    }

    /// Displays with an override under the user root, by the names macOS reads: on a
    /// case-sensitive volume, "DisplayVendorID-DB4" is not the lowercase name macOS looks for.
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
        return Set(keys).filter { key in
            fileManager.fileExists(atPath: locations.userFile(for: key).path(percentEncoded: false))
        }.sorted()
    }

    // MARK: - Backups

    /// Backups of `key`'s override, newest first.
    public func backups(for key: OverrideKey) -> [OverrideBackup] {
        let folder = locations.backupFolder(for: key)
        guard Self.hasUnlinkedParents(folder) else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return names.compactMap { name -> OverrideBackup? in
            let file = folder.appending(path: name, directoryHint: .notDirectory)
            // Only regular files: a link could point anywhere.
            let type = try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.type] as? FileAttributeType
            guard type == .typeRegular else { return nil }
            return OverrideBackup(key: key, file: file)
        }.sorted { ($0.date, $0.sequence) > ($1.date, $1.sequence) }
    }

    /// Displays that have backups.
    public func backupKeys() -> [OverrideKey] {
        let fileManager = FileManager.default
        guard let vendors = try? fileManager.contentsOfDirectory(atPath: locations.backupRoot.path(percentEncoded: false)) else {
            return []
        }
        var keys = Set<OverrideKey>()
        for vendor in vendors {
            let folder = locations.backupRoot.appending(path: vendor, directoryHint: .isDirectory)
            for name in (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? [] {
                // "DisplayProductID-3401-20260921-141320.plist" names product 3401.
                let product = name.split(separator: "-", maxSplits: 2).prefix(2).joined(separator: "-")
                guard let key = OverrideKey(vendorDirectory: vendor, productFile: product), !keys.contains(key),
                      !backups(for: key).isEmpty
                else { continue }
                keys.insert(key)
            }
        }
        return keys.sorted()
    }

    /// A backup's bytes, as a restore writes them back, and the override they hold when
    /// Resolute can read one. Throws when the backup is gone, or holds no property list
    /// macOS could read: a dictionary, or a list of them.
    public func restorableContents(of backup: OverrideBackup) throws -> BackupContents {
        try validate(backup)
        guard let data = try regularContents(of: backup.file) else {
            throw ResoluteError.overrideUnreadable(path: backup.file.path(percentEncoded: false), reason: "it no longer exists")
        }
        do {
            return BackupContents(data: data, override: try parse(data, key: backup.key, at: backup.file), problem: nil)
        } catch ResoluteError.overrideUnreadable(let path, let reason) {
            let list = try? PropertyListSerialization.propertyList(from: data, format: nil)
            guard list is [String: Any] || ((list as? [[String: Any]])?.isEmpty == false) else {
                throw ResoluteError.overrideUnreadable(path: path, reason: reason)
            }
            return BackupContents(data: data, override: nil, problem: reason)
        }
    }

    /// A backup's bytes, and the override they hold; throws when they are not one.
    public func contents(of backup: OverrideBackup) throws -> (override: DisplayOverride, data: Data) {
        try validate(backup)
        guard let data = try regularContents(of: backup.file) else {
            throw ResoluteError.overrideUnreadable(path: backup.file.path(percentEncoded: false), reason: "it no longer exists")
        }
        return (try parse(data, key: backup.key, at: backup.file), data)
    }

    private func validate(_ backup: OverrideBackup) throws {
        guard locations.contains(backup), Self.hasUnlinkedParents(backup.file.deletingLastPathComponent()) else {
            throw ResoluteError.overrideUnreadable(path: backup.file.path(percentEncoded: false), reason: "it is not a regular backup in the backup folder")
        }
    }

    /// Check each parent rather than resolving links, which would accept a redirected
    /// vendor folder. /var and /tmp are macOS's own aliases used by staged locations.
    private static func hasUnlinkedParents(_ folder: URL) -> Bool {
        var current = folder.standardizedFileURL
        while current.path != "/" {
            if current.path != "/var" && current.path != "/tmp" {
                var info = stat()
                if lstat(current.path, &info) == 0, info.st_mode & S_IFMT != S_IFDIR { return false }
            }
            current.deleteLastPathComponent()
        }
        return true
    }

    /// Open without following the final link or blocking on a FIFO, then inspect the
    /// descriptor used for the read so a replaced directory entry cannot bypass it.
    private func regularContents(of url: URL, followingLinks: Bool = false) throws -> Data? {
        let path = url.path(percentEncoded: false)
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | (followingLinks ? 0 : O_NOFOLLOW))
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            let reason = errno == EACCES ? "you don’t have permission to read it" : "it is not a readable regular file"
            throw ResoluteError.overrideUnreadable(path: path, reason: reason)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            throw ResoluteError.overrideUnreadable(path: path, reason: "it is not a regular file with a single link")
        }
        return try handle.readToEnd() ?? Data()
    }

    // MARK: - Reading

    private func read(_ url: URL, key: OverrideKey) throws -> DisplayOverride? {
        try contents(of: url).map { try parse($0, key: key, at: url) }
    }

    /// The bytes at `url`, or nil when nothing is there.
    private func contents(of url: URL) throws -> Data? {
        let path = url.path(percentEncoded: false)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) else { return nil }
        guard !isFolder.boolValue else {
            throw ResoluteError.overrideUnreadable(path: path, reason: "it is a folder, not a file")
        }
        do {
            return try regularContents(of: url, followingLinks: true)
        } catch let error as ResoluteError {
            throw error
        } catch {
            throw ResoluteError.overrideUnreadable(path: path, reason: Self.readFailure(error))
        }
    }

    private func parse(_ data: Data, key: OverrideKey, at url: URL) throws -> DisplayOverride {
        let path = url.path(percentEncoded: false)
        do {
            return try DisplayOverride(key: key, propertyList: data)
        } catch ResoluteError.overrideUnreadable(_, let reason) {
            throw ResoluteError.overrideUnreadable(path: path, reason: reason)
        } catch {
            throw ResoluteError.overrideUnreadable(path: path, reason: "it is not a valid property list")
        }
    }

    /// Why a file could not be read, to follow "Could not read <path>: ".
    static func readFailure(_ error: Error) -> String {
        if (error as? CocoaError)?.code == .fileReadNoPermission {
            return "you don’t have permission to read it"
        }
        if let posix = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain {
            return String(cString: strerror(Int32(posix.code))).lowercased()
        }
        return error.localizedDescription
    }
}

/// A copy of an override file that an install or a removal replaced. Its name says when:
/// "DisplayProductID-3401-20260921-141320.plist", in UTC so that names sort by time
/// whatever the time zone, with "-2", "-3" and so on for later backups in the same second.
public struct OverrideBackup: Hashable, Sendable, Identifiable {
    public var key: OverrideKey
    public var file: URL
    public var date: Date
    /// 1 for the first backup made in a second, 2 for the next, and so on.
    public var sequence: Int

    public var id: URL { file }
    public var fileName: String { file.lastPathComponent }

    init(key: OverrideKey, file: URL, date: Date, sequence: Int) {
        self.key = key
        self.file = file
        self.date = date
        self.sequence = sequence
    }

    /// Reads a backup's name; nil for any other file.
    init?(key: OverrideKey, file: URL) {
        let name = file.lastPathComponent
        let prefix = key.productFileName + "-"
        guard name.hasPrefix(prefix), name.hasSuffix(".plist") else { return nil }
        let stamp = name.dropFirst(prefix.count).dropLast(".plist".count)
        let parts = stamp.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let date = Self.date(from: parts[0] + "-" + parts[1])
        else { return nil }
        var sequence = 1
        if parts.count == 3 {
            // The installer counts from 2, without leading zeros.
            guard let number = Int(parts[2]), number >= 2, String(number) == parts[2] else { return nil }
            sequence = number
        }
        self.init(key: key, file: file, date: date, sequence: sequence)
    }

    private static func date(from stamp: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        guard let date = formatter.date(from: stamp), formatter.string(from: date) == stamp else { return nil }
        return date
    }
}

extension OverrideLocations {
    /// Check the complete identity, not just the number of path components.
    func contains(_ backup: OverrideBackup) -> Bool {
        guard backup.file.isFileURL, OverrideBackup(key: backup.key, file: backup.file) != nil else { return false }
        return backup.file.standardizedFileURL.deletingLastPathComponent()
            == backupFolder(for: backup.key).standardizedFileURL
    }

    /// Where backups of `key`'s override go.
    public func backupFolder(for key: OverrideKey) -> URL {
        backupRoot.appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
    }
}

/// A backup as a restore sees it: its bytes, and the override they hold when Resolute can
/// read one.
public struct BackupContents: Sendable {
    public let data: Data
    /// Nil when Resolute cannot edit what the bytes hold, such as a file listing several overrides.
    public let override: DisplayOverride?
    /// Why `override` is nil, as the reason `ResoluteError.overrideUnreadable` gives.
    public let problem: String?
}
