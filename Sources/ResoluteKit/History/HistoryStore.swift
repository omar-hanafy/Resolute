import Foundation
import os

/// History's file, shared by the app and the `resolute` command (also under `sudo`): one
/// JSON entry per line, appended in the order changes end.
///
/// Writers take `history.lock` in the same folder, then open the history file, so a prune,
/// which writes a new file and renames it over the old one, never leaves a waiting writer
/// appending to the file it replaced. Readers take no lock: the rename swaps the whole file,
/// and a line still being written is not read until it ends.
public struct HistoryStore: Sendable {
    /// How long History keeps a change.
    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    /// A prune waits until the oldest entry is this much older than `retention`, so the file
    /// is rewritten about once a day rather than on every change.
    static let pruneSlack: TimeInterval = 24 * 60 * 60
    static let lockFileName = "history.lock"
    /// Longer than any entry: a first line without a newline this far in is not one.
    static let longestLine = 64 * 1024

    public var locations: SupportLocations
    /// How long to wait for another process that is writing.
    public var lockTimeout: Duration
    /// Past this size the oldest entries go even within `retention`; a prune leaves three
    /// quarters of it, so the file is not rewritten on every change after that.
    var maximumFileSize: Int
    /// Who gets what this store creates; set when running as root because of `sudo`.
    var owner: FileOwner?
    var now: @Sendable () -> Date

    public init(locations: SupportLocations = .standard, lockTimeout: Duration = .seconds(2)) {
        self.init(locations: locations, lockTimeout: lockTimeout, maximumFileSize: 1 << 20, owner: .sudoPerson(), now: { Date() })
    }

    init(
        locations: SupportLocations, lockTimeout: Duration = .seconds(2), maximumFileSize: Int,
        owner: FileOwner?, now: @escaping @Sendable () -> Date
    ) {
        self.locations = locations
        self.lockTimeout = lockTimeout
        self.maximumFileSize = maximumFileSize
        self.owner = owner
        self.now = now
    }

    private var folderURL: URL { locations.historyFile.deletingLastPathComponent() }
    private var fileName: String { locations.historyFile.lastPathComponent }

    // MARK: - Reading

    /// The entries of the last 7 days, newest first. Lines that can't be read, such as a
    /// line cut short or one a newer Resolute wrote, are skipped.
    public func entries() throws -> [HistoryEntry] {
        guard let data = try contents() else { return [] }
        let cutoff = now().addingTimeInterval(-Self.retention)
        let decoder = JSONDecoder()
        var read: [(line: Int, entry: HistoryEntry)] = []
        for (number, line) in Self.completeLines(of: data).enumerated() {
            guard let entry = try? decoder.decode(HistoryEntry.self, from: line), entry.date >= cutoff else { continue }
            read.append((number, entry))
        }
        // Processes append as their changes end, so a line can be a moment out of order.
        read.sort { $0.entry.date != $1.entry.date ? $0.entry.date > $1.entry.date : $0.line > $1.line }
        return read.map(\.entry)
    }

    /// The entries of the last 7 days in `filter`, newest first, at most `limit` of them.
    public func entries(matching filter: HistoryFilter, limit: Int? = nil) throws -> [HistoryEntry] {
        let matching = try entries().filter(filter.includes)
        return limit.map { Array(matching.prefix(max(0, $0))) } ?? matching
    }

    /// The file's bytes; nil when there is no history yet. A file grown past any size this
    /// store leaves is read from its end.
    private func contents() throws -> Data? {
        guard let folder = try SupportFolder.open(folderURL, creating: false, owner: owner) else { return nil }
        let file: Int32
        do {
            file = try folder.openFile(fileName, flags: O_RDONLY)
        } catch HistoryError.missing {
            return nil
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else {
            throw HistoryError.unusable(path: folder.path + "/" + fileName, reason: SupportFolder.describe(errno))
        }
        let limit = max(maximumFileSize * 4, 1 << 20)
        let start = max(0, Int(info.st_size) - limit)
        var data = try Self.read(file, from: start, path: folder.path)
        if start > 0, let newline = data.firstIndex(of: 0x0A) {
            // The first line was cut where the reading started.
            data = data.suffix(from: data.index(after: newline))
        }
        return data
    }

    // MARK: - Writing

    /// Adds `entry` at the end of the file, creating the folder and the file. Now and then
    /// the oldest entries are pruned, under the same lock.
    public func append(_ entry: HistoryEntry) throws {
        var line = try Self.encode(entry)
        line.append(0x0A)
        try withLock { folder in
            let file = try folder.openFile(fileName, flags: O_RDWR | O_APPEND | O_CREAT)
            defer { close(file) }
            var info = stat()
            guard fstat(file, &info) == 0 else {
                throw HistoryError.unusable(path: folder.path + "/" + fileName, reason: SupportFolder.describe(errno))
            }
            // A writer that died mid-line left no newline; this entry must not join that line.
            if info.st_size > 0, try Self.read(file, from: Int(info.st_size) - 1, count: 1, path: folder.path) != Data([0x0A]) {
                line.insert(0x0A, at: line.startIndex)
            }
            try Self.write(line, to: file, path: folder.path)
            if try needsPruning(file, size: Int(info.st_size) + line.count, path: folder.path) {
                try rewrite(in: folder)
            }
        }
    }

    /// Drops entries older than 7 days and lines that can't be read, and past the size cap
    /// the oldest entries too. Lines a newer Resolute wrote stay until they are old.
    public func prune() throws {
        guard try SupportFolder.open(folderURL, creating: false, owner: owner) != nil else { return }
        try withLock { folder in try rewrite(in: folder) }
    }

    /// Whether the file has grown past its cap or its first, oldest line is well past 7 days.
    private func needsPruning(_ file: Int32, size: Int, path: String) throws -> Bool {
        if size > maximumFileSize { return true }
        let start = try Self.read(file, from: 0, count: Self.longestLine, path: path)
        guard let newline = start.firstIndex(of: 0x0A) else { return true }
        guard let date = Self.envelopeDate(start[start.startIndex..<newline]) else { return true }
        return date < now().addingTimeInterval(-Self.retention - Self.pruneSlack)
    }

    /// Writes the lines worth keeping to a new file and renames it over the old one, so a
    /// reader sees either file whole.
    private func rewrite(in folder: SupportFolder) throws {
        let file: Int32
        do {
            file = try folder.openFile(fileName, flags: O_RDONLY)
        } catch HistoryError.missing {
            return
        }
        let data: Data
        do {
            defer { close(file) }
            data = try Self.read(file, from: 0, path: folder.path)
        }
        let cutoff = now().addingTimeInterval(-Self.retention)
        var kept = Self.completeLines(of: data).filter { line in
            Self.envelopeDate(line).map { $0 >= cutoff } ?? false
        }
        let target = maximumFileSize * 3 / 4
        var size = kept.reduce(0) { $0 + $1.count + 1 }
        var dropped = 0
        while size > target, dropped < kept.count {
            size -= kept[dropped].count + 1
            dropped += 1
        }
        kept.removeFirst(dropped)

        let temporary = ".history-\(UUID().uuidString).tmp"
        let output = try folder.openFile(temporary, flags: O_WRONLY | O_CREAT | O_EXCL, mode: 0o644)
        do {
            var bytes = Data(capacity: size)
            for line in kept {
                bytes.append(line)
                bytes.append(0x0A)
            }
            try Self.write(bytes, to: output, path: folder.path)
            guard fsync(output) == 0 else {
                throw HistoryError.unusable(path: folder.path + "/" + temporary, reason: SupportFolder.describe(errno))
            }
            close(output)
            try folder.rename(temporary, to: fileName)
        } catch {
            close(output)
            folder.remove(temporary)
            throw error
        }
        let removed = Self.completeLines(of: data).count - kept.count
        if removed > 0 {
            ResoluteLog.history.info("Pruned \(removed) history entries")
        }
    }

    /// Runs `body` holding the history lock, waiting up to `lockTimeout` for another writer.
    private func withLock<T>(_ body: (SupportFolder) throws -> T) throws -> T {
        guard let folder = try SupportFolder.open(folderURL, creating: true, owner: owner) else {
            throw HistoryError.missing(path: folderURL.path(percentEncoded: false))
        }
        let lock = try folder.openFile(Self.lockFileName, flags: O_RDWR | O_CREAT)
        // Closing the file releases the lock, also if the process dies.
        defer { close(lock) }
        let deadline = ContinuousClock.now.advanced(by: lockTimeout)
        while flock(lock, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            guard code == EWOULDBLOCK || code == EINTR else {
                throw HistoryError.unusable(path: folder.path + "/" + Self.lockFileName, reason: SupportFolder.describe(code))
            }
            guard ContinuousClock.now < deadline else { throw HistoryError.busy(path: locations.historyFile.path(percentEncoded: false)) }
            usleep(2_000)
        }
        return try body(folder)
    }

    // MARK: - Lines

    static func encode(_ entry: HistoryEntry) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(entry)
    }

    /// The lines of `data` that end in a newline and hold something. A last line without
    /// one is still being written, or was cut short.
    static func completeLines(of data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 0x0A) {
            let line = data[start..<newline]
            if !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) {
                lines.append(Data(line))
            }
            start = data.index(after: newline)
        }
        return lines
    }

    /// The date of a stored line, of any format version; nil for a line that isn't one.
    static func envelopeDate(_ line: Data) -> Date? {
        struct Envelope: Decodable {
            var v: Int
            var date: String
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: line) else { return nil }
        return try? HistoryDate.decode(envelope.date)
    }

    // MARK: - Files

    private static func read(_ file: Int32, from offset: Int, count: Int? = nil, path: String) throws -> Data {
        var data = Data()
        var position = offset
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while count.map({ data.count < $0 }) ?? true {
            let wanted = min(buffer.count, count.map { $0 - data.count } ?? buffer.count)
            let got = buffer.withUnsafeMutableBytes { pread(file, $0.baseAddress, wanted, off_t(position)) }
            if got < 0, errno == EINTR { continue }
            guard got >= 0 else { throw HistoryError.unusable(path: path, reason: SupportFolder.describe(errno)) }
            guard got > 0 else { break }
            data.append(contentsOf: buffer[0..<got])
            position += got
        }
        return data
    }

    private static func write(_ data: Data, to file: Int32, path: String) throws {
        try data.withUnsafeBytes { bytes in
            var written = 0
            while written < bytes.count {
                let result = Darwin.write(file, bytes.baseAddress! + written, bytes.count - written)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { throw HistoryError.unusable(path: path, reason: SupportFolder.describe(errno)) }
                written += result
            }
        }
    }
}
