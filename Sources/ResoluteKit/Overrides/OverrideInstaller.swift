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
            contents: try override.propertyListData(), destination: destination, backupStem: backupStem(for: override.key)
        ))
        return destination
    }

    /// Deletes the override for `key`, and its vendor folder when that is left empty.
    public func remove(_ key: OverrideKey) async throws {
        try await runner.run(Self.removeScript(destination: locations.userFile(for: key), backupStem: backupStem(for: key)))
    }

    /// Where a backup of `key`'s file goes, without the extension: the script adds
    /// ".plist", or "-2.plist" and so on when several backups share a second.
    func backupStem(for key: OverrideKey) -> URL {
        locations.backupRoot
            .appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
            .appending(path: "\(key.productFileName)-\(Self.timestamp(now()))", directoryHint: .notDirectory)
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func installScript(contents: Data, destination: URL, backupStem: URL) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = destination.deletingLastPathComponent().path(percentEncoded: false)
        let template = folder + (folder.hasSuffix("/") ? "" : "/") + ".resolute.XXXXXX"
        return [
            "set -e",
            // WindowServer must be able to read what root writes, whatever umask sudo passes on.
            "umask 022",
            backupCommand(file: file, stem: backupStem),
            "mkdir -p \(Shell.quote(folder))",
            // Written beside the destination and renamed over it, so the file appears whole.
            "incoming=$(mktemp \(Shell.quote(template)))",
            "trap 'rm -f \"$incoming\"' EXIT",
            "printf '%s' \(Shell.quote(contents.base64EncodedString())) | /usr/bin/base64 -D > \"$incoming\"",
            "chmod 644 \"$incoming\"",
            "mv -f \"$incoming\" \(file)",
        ].joined(separator: "; ")
    }

    static func removeScript(destination: URL, backupStem: URL) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = Shell.quote(destination.deletingLastPathComponent().path(percentEncoded: false))
        return [
            "set -e",
            "umask 022",
            backupCommand(file: file, stem: backupStem),
            "rm -f \(file)",
            "rmdir \(folder) 2>/dev/null || true",
        ].joined(separator: "; ")
    }

    /// Copies the file about to change to "<stem>.plist", or "<stem>-2.plist" and so on.
    /// Each name is claimed with an exclusive create (`set -C`), so installs that overlap
    /// never overwrite each other's backups.
    private static func backupCommand(file: String, stem: URL) -> String {
        let folder = Shell.quote(stem.deletingLastPathComponent().path(percentEncoded: false))
        let base = Shell.quote(stem.path(percentEncoded: false))
        return "if [ -f \(file) ]; then mkdir -p \(folder); n=1; backup=\(base).plist; "
            + "while ! (set -C; : > \"$backup\") 2>/dev/null; do n=$((n + 1)); [ \"$n\" -le 1000 ]; backup=\(base)-$n.plist; done; "
            + "cp -p \(file) \"$backup\"; fi"
    }
}
