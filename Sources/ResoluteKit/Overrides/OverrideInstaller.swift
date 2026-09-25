import Foundation
import os

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
    private static let log = ResoluteLog.overrides

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
        let path = destination.path(percentEncoded: false)
        try await logging("Wrote \(path), \(contents.count) bytes", failure: "Did not write \(path)") {
            try await run(script, changing: destination)
        }
        return destination
    }

    /// Deletes the override for `key`, and its vendor folder when that is left empty.
    public func remove(_ key: OverrideKey, expecting state: OverrideFileState? = nil) async throws {
        let destination = locations.userFile(for: key)
        let script = Self.removeScript(destination: destination, backupStem: backupStem(for: key), expecting: state)
        let path = destination.path(percentEncoded: false)
        try await logging("Removed \(path)", failure: "Did not remove \(path)") {
            try await run(script, changing: destination)
        }
    }

    /// Deletes `backups`, and their folders once empty. Refuses anything outside the
    /// backup folder before running a script.
    public func removeBackups(_ backups: [OverrideBackup]) async throws {
        guard !backups.isEmpty else { return }
        let root = locations.backupRoot.standardizedFileURL.path(percentEncoded: false)
        for backup in backups {
            guard locations.contains(backup) else {
                throw ResoluteError.invalidEntry("\(backup.file.path(percentEncoded: false)) is not a backup in \(root).")
            }
        }
        let folders = Set(backups.map { Self.folderPath($0.file.deletingLastPathComponent()) })
        let from = folders.count == 1 ? folders.first ?? "" : Self.folderPath(locations.backupRoot)
        let count = backups.count == 1 ? "1 backup" : "\(backups.count) backups"
        try await logging("Removed \(count) from \(from)", failure: "Did not remove \(count) from \(from)") {
            try await run(Self.removeBackupsScript(files: backups.map(\.file)), changing: nil)
        }
    }

    /// Runs `change` and logs `done`, or `failure` with the reason. A cancelled password
    /// prompt changes nothing, so it is only noted.
    private func logging(_ done: String, failure: String, _ change: () async throws -> Void) async throws {
        do {
            try await change()
            Self.log.notice("\(done, privacy: .public)")
        } catch ResoluteError.cancelled {
            Self.log.info("\(failure, privacy: .public): the password prompt was cancelled")
            throw ResoluteError.cancelled
        } catch {
            Self.log.error("\(failure, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// A folder's path without the trailing slash, as messages show it.
    private static func folderPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
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
        return "set -e; umask 022; " + Self.pathSafetyFunctions + "; "
            + "safe_directory \(Shell.quote(folder)); safe_file \(Shell.quote(scriptLock.path(percentEncoded: false))); "
            + "exec /usr/bin/lockf -k -s -t \(max(0, scriptLockTimeout)) "
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
            pathSafetyFunctions,
            "safe_directory \(Shell.quote(folder))",
            "safe_file \(file)",
            checkCommand(file: file, state: state),
            backupCommand(file: file, stem: backupStem),

            // Written beside the destination and renamed over it, so the file appears whole.
            "incoming=$(/usr/bin/mktemp \(Shell.quote(template)))",
            "trap '/bin/rm -f \"$incoming\"' EXIT",
            "printf '%s' \(Shell.quote(contents.base64EncodedString())) | /usr/bin/base64 -D > \"$incoming\"",
            "/bin/chmod 644 \"$incoming\"",
            "/bin/mv -f \"$incoming\" \(file)",
        ] as [String?]).compactMap { $0 }.joined(separator: "; ")
    }

    static func removeScript(destination: URL, backupStem: URL, expecting state: OverrideFileState? = nil) -> String {
        let file = Shell.quote(destination.path(percentEncoded: false))
        let folder = Shell.quote(destination.deletingLastPathComponent().path(percentEncoded: false))
        return ([
            "set -e",
            "umask 022",
            pathSafetyFunctions,
            "check_directory \(folder)",
            "safe_file \(file)",
            checkCommand(file: file, state: state),
            backupCommand(file: file, stem: backupStem),
            "/bin/rm -f \(file)",
            "/bin/rmdir \(folder) 2>/dev/null || true",
        ] as [String?]).compactMap { $0 }.joined(separator: "; ")
    }

    /// Deletes each file that is a regular file (a link could point anywhere), then each
    /// folder that is left empty.
    static func removeBackupsScript(files: [URL]) -> String {
        var commands = ["set -e", pathSafetyFunctions]
        // Validate every path before deleting any file.
        for file in files {
            commands.append("check_directory \(Shell.quote(file.deletingLastPathComponent().path(percentEncoded: false)))")
            commands.append("safe_file \(Shell.quote(file.path(percentEncoded: false)))")
        }
        for file in files {
            let path = Shell.quote(file.path(percentEncoded: false))
            commands.append("if [ -f \(path) ] && [ ! -L \(path) ]; then /bin/rm -f \(path); fi")
        }
        let folders = Set(files.map { $0.deletingLastPathComponent().path(percentEncoded: false) })
        for folder in folders.sorted() {
            commands.append("/bin/rmdir \(Shell.quote(folder)) 2>/dev/null || true")
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
            // Path safety rejects links before the optimistic state check.
            return "if [ -e \(file) ]; then \(changed); fi"
        case .contents(let data)?:
            // Compare bytes only after confirming the destination is a regular file.
            return "if [ ! -f \(file) ] || ! printf '%s' \(Shell.quote(data.base64EncodedString())) "
                + "| /usr/bin/base64 -D | /usr/bin/cmp -s - \(file); then \(changed); fi"
        }
    }

    /// Validate paths in the process that performs the write, after authorization. Root
    /// only traverses root-owned, non-writable directories, so an unprivileged process
    /// cannot swap a checked component before the following rename/copy/unlink.
    /// Staging remains usable as a normal user. The two macOS system aliases are the
    /// only directory symlinks accepted, and only for unprivileged staging.
    static let pathSafetyFunctions = #"""
    PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
    safe_uid=$(/usr/bin/id -u)
    unsafe_path() { echo "Refusing unsafe override path: $1" >&2; exit 1; }
    trusted_node() {
        if [ "$safe_uid" = 0 ]; then
            [ "$(/usr/bin/stat -f %u "$1")" = 0 ] || unsafe_path "$1"
            mode=$(/usr/bin/stat -f %Lp "$1")
            [ "$((0$mode & 022))" = 0 ] || unsafe_path "$1"
            # ACL write grants are not represented by the POSIX mode bits.
            [ -z "$(/bin/ls -lde "$1" | /usr/bin/sed -n '2p')" ] || unsafe_path "$1"
        fi
    }
    check_directory() {
        [ "$1" = / ] && return
        set -- "${1%/}"
        parent=$(/usr/bin/dirname "$1")
        check_directory "$parent"
        if [ -L "$1" ]; then
            case "$1" in /var|/tmp)
                [ "$safe_uid" != 0 ] && return;;
            esac
            unsafe_path "$1"
        fi
        if [ -e "$1" ]; then
            [ -d "$1" ] || unsafe_path "$1"
            trusted_node "$1"
        fi
    }
    safe_directory() {
        check_directory "$1"
        /bin/mkdir -p "$1"
        check_directory "$1"
    }
    safe_file() {
        [ ! -L "$1" ] || unsafe_path "$1"
        if [ -e "$1" ]; then
            [ -f "$1" ] || unsafe_path "$1"
            [ "$(/usr/bin/stat -f %l "$1")" = 1 ] || unsafe_path "$1"
            trusted_node "$1"
        fi
    }
    """#

    /// Copies the file about to change to "<stem>.plist", or "<stem>-2.plist" and so on.
    /// Each name is claimed with an exclusive create (`set -C`), so installs that overlap
    /// never overwrite each other's backups. A name that cannot be claimed for any other
    /// reason stops the script with that reason, and a failed copy leaves no empty backup.
    private static func backupCommand(file: String, stem: URL) -> String {
        let folderPath = stem.deletingLastPathComponent().path(percentEncoded: false)
        let base = Shell.quote(stem.path(percentEncoded: false))
        let noBackup = Shell.quote("Could not create a backup in \(folderPath)")
        let noCopy = Shell.quote("Could not back up the file being replaced.")
        return "if [ -f \(file) ]; then safe_directory \(Shell.quote(folderPath)); n=1; backup=\(base).plist; "
            + "until (set -C; : > \"$backup\") 2>/dev/null; do "
            + "[ -e \"$backup\" ] || { echo \(noBackup) >&2; exit 1; }; n=$((n + 1)); backup=\(base)-$n.plist; done; "
            + "/bin/cp \(file) \"$backup\" || { /bin/rm -f \"$backup\"; echo \(noCopy) >&2; exit 1; }; fi"
    }
}
