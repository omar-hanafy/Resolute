import Darwin
import Foundation

/// Bytes read from a connection, split into lines of at most `limit` bytes, newline
/// included.
struct LineBuffer {
    enum Next: Equatable {
        case line([UInt8])
        /// No newline yet.
        case incomplete
        /// No newline within `limit` bytes.
        case tooLong
    }

    let limit: Int
    private var bytes: [UInt8] = []

    init(limit: Int = AgentChannel.maximumMessageSize) {
        self.limit = limit
    }

    var count: Int { bytes.count }

    mutating func append(_ chunk: some Sequence<UInt8>) {
        bytes.append(contentsOf: chunk)
    }

    /// The first complete line, without its newline, taken out of the buffer.
    mutating func next() -> Next {
        guard let newline = bytes.firstIndex(of: UInt8(ascii: "\n")) else {
            return bytes.count >= limit ? .tooLong : .incomplete
        }
        guard newline < limit else { return .tooLong }
        let line = Array(bytes[..<newline])
        bytes.removeSubrange(...newline)
        return .line(line)
    }
}

/// The socket calls the channel makes, with failures in the channel's terms. Every socket
/// is nonblocking, so a wait always has a deadline.
enum UnixSocket {
    /// `url` as a socket address, which holds 103 bytes of path.
    static func address(of url: URL) throws -> sockaddr_un {
        let path = url.path(percentEncoded: false)
        let bytes = Array(path.utf8)
        var address = sockaddr_un()
        guard !bytes.isEmpty, !bytes.contains(0), bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw AgentChannelError.pathTooLong(path)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    static func withAddress<Result>(
        _ address: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Result
    ) -> Result {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    /// A stream socket.
    static func makeSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw failure("create a socket") }
        do {
            try configure(descriptor)
        } catch {
            close(descriptor)
            throw error
        }
        return descriptor
    }

    /// Makes `descriptor` nonblocking, keeps it from child processes, and turns a write to
    /// a closed connection into an error rather than a SIGPIPE that would end the process.
    static func configure(_ descriptor: Int32) throws {
        var one: Int32 = 1
        let flags = fcntl(descriptor, F_GETFL)
        guard setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size)) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0
        else { throw failure("set up a socket") }
    }

    /// Connects to the socket at `url`. No socket there, or one nobody listens on any more,
    /// means the app is not running.
    static func connect(to url: URL, until deadline: ContinuousClock.Instant) throws -> Int32 {
        let address = try address(of: url)
        let descriptor = try makeSocket()
        let result = withAddress(address) { Darwin.connect(descriptor, $0, $1) }
        var code = result == 0 ? 0 : errno
        // A local connection is normally made at once; a nonblocking one may say it is
        // still under way.
        if code == EINPROGRESS || code == EINTR {
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            if wait(for: Int16(POLLOUT), on: descriptor, until: deadline),
               getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0 {
                code = socketError
            } else {
                code = ETIMEDOUT
            }
        }
        guard code != 0 else { return descriptor }
        close(descriptor)
        switch code {
        case ENOENT, ECONNREFUSED: throw AgentChannelError.appNotRunning
        case ETIMEDOUT: throw AgentChannelError.timedOut
        default: throw AgentChannelError.system("connect to \(url.path(percentEncoded: false))", code: code)
        }
    }

    /// The user ID of the process at the other end of `descriptor`.
    static func peerUserID(of descriptor: Int32) -> uid_t? {
        var user: uid_t = 0
        var group: gid_t = 0
        return getpeereid(descriptor, &user, &group) == 0 ? user : nil
    }

    /// Writes all of `bytes`, waiting for room until `deadline`.
    static func write(_ bytes: [UInt8], to descriptor: Int32, until deadline: ContinuousClock.Instant) throws {
        var written = 0
        while written < bytes.count {
            let count = bytes[written...].withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                written += count
                continue
            }
            switch errno {
            case EINTR:
                continue
            case EAGAIN:
                guard wait(for: Int16(POLLOUT), on: descriptor, until: deadline) else { throw AgentChannelError.timedOut }
            case EPIPE, ECONNRESET:
                throw AgentChannelError.closedWithoutAnswer
            case let code:
                throw AgentChannelError.system("send a message", code: code)
            }
        }
    }

    enum ReadResult: Equatable {
        /// Everything there was is in the buffer, and more may come.
        case open
        case endOfFile
        case failed(Int32)
    }

    /// Moves what can be read now into `buffer`, stopping once it holds more than a line.
    static func read(from descriptor: Int32, into buffer: inout LineBuffer) -> ReadResult {
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count <= buffer.limit {
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                buffer.append(chunk[..<count])
                continue
            }
            if count == 0 { return .endOfFile }
            switch errno {
            case EINTR: continue
            case EAGAIN: return .open
            case let code: return .failed(code)
            }
        }
        return .open
    }

    /// Waits until `descriptor` has something to read, or was closed, or `deadline` passes.
    static func waitUntilReadable(_ descriptor: Int32, until deadline: ContinuousClock.Instant) -> Bool {
        wait(for: Int16(POLLIN), on: descriptor, until: deadline)
    }

    private static func wait(for events: Int16, on descriptor: Int32, until deadline: ContinuousClock.Instant) -> Bool {
        while true {
            var entry = pollfd(fd: descriptor, events: events, revents: 0)
            let ready = poll(&entry, 1, milliseconds(until: deadline))
            if ready > 0 { return true }
            // A signal can end the wait early.
            guard ready < 0, errno == EINTR, ContinuousClock.now < deadline else { return false }
        }
    }

    /// Whole milliseconds until `deadline`, rounded up so a wait never spins.
    static func milliseconds(until deadline: ContinuousClock.Instant) -> Int32 {
        let left = deadline - ContinuousClock.now
        guard left > .zero else { return 0 }
        let (seconds, attoseconds) = left.components
        let total = seconds * 1_000 + (attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
        return Int32(clamping: total)
    }

    /// `duration` for a Dispatch timer.
    static func interval(_ duration: Duration) -> DispatchTimeInterval {
        let (seconds, attoseconds) = duration.components
        let (nanoseconds, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        return overflow ? .never : .nanoseconds(Int(clamping: nanoseconds + attoseconds / 1_000_000_000))
    }

    private static func failure(_ operation: String) -> AgentChannelError {
        AgentChannelError.system(operation, code: errno)
    }
}
