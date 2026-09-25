import Foundation

/// Writes and removes override files through a `CommandRunning`, backing up what it replaces.
public struct OverrideInstaller: Sendable {
    public var locations: OverrideLocations
    public var runner: any CommandRunning
    public var now: @Sendable () -> Date
    /// A lock the script takes before it changes anything, for callers that cannot hold
    /// `OverrideLock` themselves: the app runs as the user, and only root can create the
    /// lock file. Nil when the caller holds the lock already, as the command line does
    /// (a script taking it too would wait for its own caller).
    public var scriptLock: URL?
    /// How long a script waits for `scriptLock`, in seconds.
    public var scriptLockTimeout = 60

    public init(
        locations: OverrideLocations = .standard,
        runner: any CommandRunning,
        now: @escaping @Sendable () -> Date = { Date() },
        scriptLock: URL? = nil
    ) {
        self.locations = locations
        self.runner = runner
        self.now = now
        self.scriptLock = scriptLock
    }

    /// The script's exit status when the file is not in the state the change expected.
    static let changedStatus: Int32 = 3
    /// lockf's exit status when the lock stayed taken (EX_TEMPFAIL) and when it could not
    /// create the lock file (EX_CANTCREAT).
    static let lockBusyStatus: Int32 = 75
    static let lockUnavailableStatus: Int32 = 73

    /// Writes `override` to its file and returns the file's location.
    ///
    /// The file's contents travel inside the script, so the privileged script never
    /// reads a file that another process running as the user could swap. With `expecting`,
    /// the script first checks that the file still holds what the change was based on, and
    /// throws `ResoluteError.overrideChanged` without touching anything if it does not.
    @discardableResult
    public func install(_ override: DisplayOverride, expecting state: OverrideFileState? = nil) async throws -> URL {
        try await install(contents: try override.propertyListData(), for: override.key, expecting: state)
    }

    /// Writes `contents` as `key`'s override, byte for byte, as restoring a backup does.
    @discardableResult
    public func install(contents: Data, for key: OverrideKey, expecting state: OverrideFileState? = nil) async throws -> URL {
        let destination = locations.userFile(for: key)
        let script = Self.installScript(contents: contents, destination: destination, backupStem: backupStem(for: key), expecting: state)
        try await run(script, changing: destination)
        return destination
    }

    /// Deletes the override for `key`, and its vendor folder when that is left empty.
    public func remove(_ key: OverrideKey, expecting state: OverrideFileState? = nil) async throws {
        let destination = locations.userFile(for: key)
        try await run(Self.removeScript(destination: destination, backupStem: backupStem(for: key), expecting: state), changing: destination)
    }

    /// Deletes `backups`, and their folders once empty. Refuses anything outside the
    /// backup folder before running a script.
    public func removeBackups(_ backups: [OverrideBackup]) async throws {
        guard !backups.isEmpty else { return }
        let root = locations.backupRoot.standardizedFileURL.path(percentEncoded: false)
        for backup in backups {
            let folder = backup.file.standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
            guard folder.path(percentEncoded: false) == root else {
                throw ResoluteError.invalidEntry("\(backup.file.path(percentEncoded: false)) is not a backup in \(root).")
            }
        }
        try await run(Self.removeBackupsScript(files: backups.map(\.file)), changing: nil)
    }

    /// Runs `script`, under `scriptLock` when there is one, and names what went wrong.
    private func run(_ script: String, changing destination: URL?) async throws {
        do {
            try await runner.run(locked(script))
        } catch ResoluteError.commandFailed(let status, let message) {
            if status == Self.changedStatus, let destination {
                throw ResoluteError.overrideChanged(path: destination.path(percentEncoded: false))
            }
            if scriptLock != nil, status == Self.lockBusyStatus {
                throw ResoluteError.overridesBusy
            }
            if let scriptLock, status == Self.lockUnavailableStatus {
                throw ResoluteError.lockUnavailable(path: scriptLock.path(percentEncoded: false), reason: "it could not be created")
            }
            throw ResoluteError.commandFailed(status: status, message: message)
        }
    }

    /// `script` run while holding `scriptLock`, through lockf(1), which takes the same
    /// flock(2) lock as `OverrideLock`.
    func locked(_ script: String) -> String {
        guard let scriptLock else { return script }
        let folder = scriptLock.deletingLastPathComponent().path(percentEncoded: false)
        return "umask 022; mkdir -p \(Shell.quote(folder)) && exec /usr/bin/lockf -k -s -t \(scriptLockTimeout) "
            + "\(Shell.quote(scriptLock.path(percentEncoded: false))) /bin/sh -c \(Shell.quote(script))"
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

    static func installScript(contents: Data, destination: URL, backupStem: URL, expecting state: OverrideFileState? = nil) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = destination.deletingLastPathComponent().path(percentEncoded: false)
        let template = folder + (folder.hasSuffix("/") ? "" : "/") + ".resolute.XXXXXX"
        return ([
            "set -e",
            // WindowServer must be able to read what root writes, whatever umask sudo passes on.
            "umask 022",
            checkCommand(file: file, state: state),
            backupCommand(file: file, stem: backupStem),
            "mkdir -p \(Shell.quote(folder))",
            // Written beside the destination and renamed over it, so the file appears whole.
            "incoming=$(mktemp \(Shell.quote(template)))",
            "trap 'rm -f \"$incoming\"' EXIT",
            "printf '%s' \(Shell.quote(contents.base64EncodedString())) | /usr/bin/base64 -D > \"$incoming\"",
            "chmod 644 \"$incoming\"",
            "mv -f \"$incoming\" \(file)",
        ] as [String?]).compactMap { $0 }.joined(separator: "; ")
    }

    static func removeScript(destination: URL, backupStem: URL, expecting state: OverrideFileState? = nil) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = Shell.quote(destination.deletingLastPathComponent().path(percentEncoded: false))
        return ([
            "set -e",
            "umask 022",
            checkCommand(file: file, state: state),
            backupCommand(file: file, stem: backupStem),
            "rm -f \(file)",
            "rmdir \(folder) 2>/dev/null || true",
        ] as [String?]).compactMap { $0 }.joined(separator: "; ")
    }

    /// Deletes each file that is a regular file (a link could point anywhere), then each
    /// folder that is left empty.
    static func removeBackupsScript(files: [URL]) -> String {
        var commands = ["set -e"]
        for file in files {
            let path = Shell.quote(file.path(percentEncoded: false))
            commands.append("if [ -f \(path) ] && [ ! -L \(path) ]; then rm -f \(path); fi")
        }
        let folders = Set(files.map { $0.deletingLastPathComponent().path(percentEncoded: false) })
        for folder in folders.sorted() {
            commands.append("rmdir \(Shell.quote(folder)) 2>/dev/null || true")
        }
        return commands.joined(separator: "; ")
    }

    /// Stops the script with `changedStatus` unless `file` still holds what `state` says.
    /// Nil when there is nothing to check.
    private static func checkCommand(file: String, state: OverrideFileState?) -> String? {
        let changed = "{ echo \(Shell.quote("The override changed after it was read.")) >&2; exit \(changedStatus); }"
        switch state {
        case nil:
            return nil
        case .absent?:
            return "if [ -e \(file) ] || [ -L \(file) ]; then \(changed); fi"
        case .contents(let data)?:
            return "if [ -L \(file) ] || [ ! -f \(file) ] || ! printf '%s' \(Shell.quote(data.base64EncodedString())) "
                + "| /usr/bin/base64 -D | /usr/bin/cmp -s - \(file); then \(changed); fi"
        }
    }

    /// Copies the file about to change to "<stem>.plist", or "<stem>-2.plist" and so on.
    /// Each name is claimed with an exclusive create (`set -C`), so installs that overlap
    /// never overwrite each other's backups. A name that cannot be claimed for any other
    /// reason stops the script with that reason, and a failed copy leaves no empty backup.
    private static func backupCommand(file: String, stem: URL) -> String {
        let folderPath = stem.deletingLastPathComponent().path(percentEncoded: false)
        let base = Shell.quote(stem.path(percentEncoded: false))
        let noBackup = Shell.quote("Could not create a backup in \(folderPath)")
        let noCopy = Shell.quote("Could not back up the file being replaced.")
        return "if [ -f \(file) ]; then mkdir -p \(Shell.quote(folderPath)); n=1; backup=\(base).plist; "
            + "until (set -C; : > \"$backup\") 2>/dev/null; do "
            + "[ -e \"$backup\" ] || { echo \(noBackup) >&2; exit 1; }; n=$((n + 1)); backup=\(base)-$n.plist; done; "
            + "cp -p \(file) \"$backup\" || { rm -f \"$backup\"; echo \(noCopy) >&2; exit 1; }; fi"
    }
}
