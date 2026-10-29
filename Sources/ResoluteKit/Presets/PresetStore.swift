import Foundation

/// Reads and writes the presets file the app and the `resolute` command share.
///
/// A change reads the file, edits it and writes it back while holding a lock, so the app
/// and the command line, saving at the same moment, never lose each other's change. Each
/// write replaces the file in one step, so a reader without the lock sees the old presets
/// or the new ones, never half a file.
public struct PresetStore: Sendable {
    public let file: URL
    /// How long a change waits for another process to finish its own.
    public var lockTimeout: Duration

    public init(file: URL, lockTimeout: Duration = .seconds(10)) {
        self.file = file
        self.lockTimeout = lockTimeout
    }

    public init(locations: SupportLocations) {
        self.init(file: locations.presetsFile)
    }

    /// The lock beside the presets file: the file itself is replaced by every write, and a
    /// lock on a replaced file would guard nothing.
    public var lockFile: URL {
        file.deletingLastPathComponent()
            .appending(path: file.deletingPathExtension().lastPathComponent + ".lock", directoryHint: .notDirectory)
    }

    private var path: String { file.path(percentEncoded: false) }

    /// The presets as saved. With no file there are none yet; a file that is not a presets
    /// file throws `unreadableFile`, and entries that are not presets are left out of
    /// `presets` and listed in `problems`.
    public func load() throws -> PresetLibrary {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return PresetLibrary()
        } catch {
            throw PresetError.unreadableFile(path: path, reason: error.localizedDescription)
        }
        return try PresetLibrary(data: data, path: path)
    }

    /// Reads the presets, lets `change` edit them and writes them back, all while holding
    /// the lock. Nothing is written when `change` throws or changes nothing. Not reentrant:
    /// an `update` inside `change` waits for the outer one until the timeout.
    @discardableResult
    public func update<T>(_ change: (inout PresetLibrary) throws -> T) throws -> T {
        let folder = file.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw PresetError.writeFailed(path: path, reason: error.localizedDescription)
        }
        return try withLock {
            let saved = try load()
            guard saved.version <= PresetFile.version else {
                throw PresetError.newerFile(path: path, version: saved.version)
            }
            var library = saved
            let result = try change(&library)
            if library != saved { try write(library) }
            return result
        }
    }

    private func write(_ library: PresetLibrary) throws {
        do {
            try PresetFile.data(for: library).write(to: file, options: .atomic)
        } catch {
            throw PresetError.writeFailed(path: path, reason: error.localizedDescription)
        }
    }

    /// Runs `body` holding an exclusive lock on `lockFile`, polling so that a lock held for
    /// too long ends in `busy` rather than a hang.
    private func withLock<T>(_ body: () throws -> T) throws -> T {
        let lockPath = lockFile.path(percentEncoded: false)
        let descriptor = open(lockPath, O_RDONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw PresetError.lockUnavailable(path: lockPath, reason: String(cString: strerror(errno)).lowercased())
        }
        // Closing the file releases the lock, also when the process dies.
        defer { close(descriptor) }
        let deadline = ContinuousClock.now.advanced(by: lockTimeout)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            guard code == EWOULDBLOCK || code == EINTR else {
                throw PresetError.lockUnavailable(path: lockPath, reason: String(cString: strerror(code)).lowercased())
            }
            guard ContinuousClock.now < deadline else { throw PresetError.busy(path: lockPath) }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return try body()
    }
}
