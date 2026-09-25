import Foundation

/// Lets one Resolute process at a time edit overrides, so two edits cannot both start
/// from the same old file. It is not reentrant: a nested `withLock` on the same file waits
/// for the outer one until its timeout.
public struct OverrideLock: Sendable {
    public var file: URL
    /// How long to wait for another edit to finish.
    public var timeout: Duration

    public init(file: URL, timeout: Duration = .seconds(60)) {
        self.file = file
        self.timeout = timeout
    }

    /// Runs `body` while holding the lock. `onWait` is called once when another edit holds
    /// it, so the caller can say what it is waiting for.
    public func withLock<T>(onWait: () -> Void = {}, _ body: () async throws -> T) async throws -> T {
        let descriptor = try await acquire(onWait: onWait)
        // Closing the file releases the lock, also if the process dies.
        defer { close(descriptor) }
        return try await body()
    }

    /// Opens and locks the file, polling so no thread is held while another edit runs.
    private func acquire(onWait: () -> Void) async throws -> Int32 {
        let path = file.path(percentEncoded: false)
        do {
            try await ShellCommandRunner().run(
                "set -e; umask 022; " + OverrideInstaller.pathSafetyFunctions + "; safe_directory "
                    + Shell.quote(file.deletingLastPathComponent().path(percentEncoded: false))
                    + "; safe_file " + Shell.quote(path)
            )
        } catch {
            throw ResoluteError.lockUnavailable(path: path, reason: error.localizedDescription)
        }
        let descriptor = open(path, O_RDONLY | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw ResoluteError.lockUnavailable(path: path, reason: Self.describe(errno))
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            close(descriptor)
            throw ResoluteError.lockUnavailable(path: path, reason: "it is not a regular file with a single link")
        }
        let deadline = ContinuousClock.now + timeout
        var hasWaited = false
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            do {
                guard code == EWOULDBLOCK || code == EINTR else {
                    throw ResoluteError.lockUnavailable(path: path, reason: Self.describe(code))
                }
                guard ContinuousClock.now < deadline else { throw ResoluteError.overridesBusy }
                if !hasWaited {
                    hasWaited = true
                    onWait()
                }
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                close(descriptor)
                throw error
            }
        }
        return descriptor
    }

    private static func describe(_ code: Int32) -> String {
        String(cString: strerror(code)).lowercased()
    }
}

extension OverrideLocations {
    /// The lock file for edits to these overrides.
    public var lockFile: URL {
        backupRoot.deletingLastPathComponent().appending(path: "overrides.lock", directoryHint: .notDirectory)
    }
}
