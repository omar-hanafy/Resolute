import Foundation

/// Writes and removes override files through a `CommandRunning`, backing up what it replaces.
public struct OverrideInstaller: Sendable {
    public var locations: OverrideLocations
    public var runner: any CommandRunning
    public var now: @Sendable () -> Date

    public init(
        locations: OverrideLocations = .standard,
        runner: any CommandRunning,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.locations = locations
        self.runner = runner
        self.now = now
    }

    /// Writes `override` to its file and returns the file's location.
    ///
    /// The file's contents travel inside the script, so the privileged script never
    /// reads a file that another process running as the user could swap.
    @discardableResult
    public func install(_ override: DisplayOverride) async throws -> URL {
        let destination = locations.userFile(for: override.key)
        try await runner.run(Self.installScript(
            contents: try override.propertyListData(), destination: destination, backup: backupFile(for: override.key)
        ))
        return destination
    }

    /// Deletes the override for `key`, and its vendor folder when that is left empty.
    public func remove(_ key: OverrideKey) async throws {
        try await runner.run(Self.removeScript(destination: locations.userFile(for: key), backup: backupFile(for: key)))
    }

    /// The next unused backup file for `key`: a timestamp, plus a counter when several
    /// backups are made within the same second.
    func backupFile(for key: OverrideKey) -> URL {
        let folder = locations.backupRoot.appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
        let stem = "\(key.productFileName)-\(Self.timestamp(now()))"
        var candidate = folder.appending(path: "\(stem).plist")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder.appending(path: "\(stem)-\(counter).plist")
            counter += 1
        }
        return candidate
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func installScript(contents: Data, destination: URL, backup: URL) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = destination.deletingLastPathComponent().path(percentEncoded: false)
        let template = folder + (folder.hasSuffix("/") ? "" : "/") + ".resolute.XXXXXX"
        return [
            "set -e",
            // WindowServer must be able to read what root writes, whatever umask sudo passes on.
            "umask 022",
            backupCommand(file: file, backup: backup),
            "mkdir -p \(Shell.quote(folder))",
            // Written beside the destination and renamed over it, so the file appears whole.
            "incoming=$(mktemp \(Shell.quote(template)))",
            "trap 'rm -f \"$incoming\"' EXIT",
            "printf '%s' \(Shell.quote(contents.base64EncodedString())) | /usr/bin/base64 -D > \"$incoming\"",
            "chmod 644 \"$incoming\"",
            "mv -f \"$incoming\" \(file)",
        ].joined(separator: "; ")
    }

    static func removeScript(destination: URL, backup: URL) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = Shell.quote(destination.deletingLastPathComponent().path(percentEncoded: false))
        return [
            "set -e",
            "umask 022",
            backupCommand(file: file, backup: backup),
            "rm -f \(file)",
            "rmdir \(folder) 2>/dev/null || true",
        ].joined(separator: "; ")
    }

    private static func backupCommand(file: String, backup: URL) -> String {
        let folder = Shell.quote(backup.deletingLastPathComponent().path(percentEncoded: false))
        return "if [ -f \(file) ]; then mkdir -p \(folder); cp -p \(file) \(Shell.quote(backup.path(percentEncoded: false))); fi"
    }
}
