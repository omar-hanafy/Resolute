import Foundation

/// Lets one Resolute process at a time edit overrides, so two edits cannot both start
/// from the same old file.
public struct OverrideLock: Sendable {
    public var file: URL

    public init(file: URL) {
        self.file = file
    }

    /// Runs `body` while holding the lock.
    public func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        let descriptor = await acquire()
        // Closing the file releases the lock, also if the process dies.
        defer { if descriptor >= 0 { close(descriptor) } }
        return try await body()
    }

    /// Opens and locks the file, polling so no thread is held while another edit runs.
    /// Returns -1 when the file cannot be opened, for example because only root may create
    /// its folder; the edit then goes ahead unlocked, as it did before there was a lock.
    private func acquire() async -> Int32 {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(file.path(percentEncoded: false), O_RDONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return -1 }
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EINTR else {
                close(descriptor)
                return -1
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return descriptor
    }
}

extension OverrideLocations {
    /// The lock file for edits to these overrides.
    public var lockFile: URL {
        backupRoot.deletingLastPathComponent().appending(path: "overrides.lock", directoryHint: .notDirectory)
    }
}
