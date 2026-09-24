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
    @discardableResult
    public func install(_ override: DisplayOverride) async throws -> URL {
        let staging = FileManager.default.temporaryDirectory.appending(path: "Resolute-\(UUID().uuidString).plist")
        try override.propertyListData().write(to: staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        let destination = locations.userFile(for: override.key)
        try await runner.run(Self.installScript(
            staging: staging, destination: destination, backup: backupFile(for: override.key)
        ))
        return destination
    }

    /// Deletes the override for `key`, and its vendor folder when that is left empty.
    public func remove(_ key: OverrideKey) async throws {
        try await runner.run(Self.removeScript(destination: locations.userFile(for: key), backup: backupFile(for: key)))
    }

    func backupFile(for key: OverrideKey) -> URL {
        locations.backupRoot
            .appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
            .appending(path: "\(key.productFileName)-\(Self.timestamp(now())).plist")
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func installScript(staging: URL, destination: URL, backup: URL) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        return [
            "set -e",
            backupCommand(file: file, backup: backup),
            "mkdir -p \(Shell.quote(destination.deletingLastPathComponent().path(percentEncoded: false)))",
            "cp \(Shell.quote(staging.path(percentEncoded: false))) \(file)",
            "chmod 644 \(file)",
        ].joined(separator: "; ")
    }

    static func removeScript(destination: URL, backup: URL) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = Shell.quote(destination.deletingLastPathComponent().path(percentEncoded: false))
        return [
            "set -e",
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
