import Darwin
import Foundation

/// Ctrl-C while a hidden mode is on trial. By default it ends the process at once, which
/// leaves the mode until logout, and a mode the display cannot show leaves Ctrl-C as all a
/// person can do. So during a trial Ctrl-C is caught and written to a pipe, where the prompt
/// and the wait for a display that went away look for it.
final class Interrupts: Sendable {
    /// The process's own, which `catchingControlC` connects to SIGINT.
    static let process = Interrupts()

    enum Event: Equatable {
        case interrupted
        case input
        case timedOut
    }

    private let readEnd: Int32
    private let writeEnd: Int32

    init() {
        var ends: [Int32] = [-1, -1]
        if pipe(&ends) == 0 {
            for end in ends { _ = fcntl(end, F_SETFL, O_NONBLOCK) }
        }
        readEnd = ends[0]
        writeEnd = ends[1]
    }

    deinit {
        close(readEnd)
        close(writeEnd)
    }

    /// What Ctrl-C does while it is caught; tests call it in its place.
    func interrupt() {
        var byte: UInt8 = 1
        _ = write(writeEnd, &byte, 1)
    }

    /// Waits up to `timeout` seconds for Ctrl-C, or for `input` to have something to read.
    /// Ctrl-C wins when both came.
    func wait(_ timeout: TimeInterval, orFor input: Int32? = nil) -> Event {
        let deadline = ContinuousClock.now + .milliseconds(Int((timeout * 1_000).rounded()))
        while true {
            var ends = [pollfd(fd: readEnd, events: Int16(POLLIN), revents: 0)]
            if let input { ends.append(pollfd(fd: input, events: Int16(POLLIN), revents: 0)) }
            let left = max(deadline - ContinuousClock.now, .zero).components
            let milliseconds = Int32(left.seconds * 1_000 + left.attoseconds / 1_000_000_000_000_000)
            let ready = poll(&ends, nfds_t(ends.count), milliseconds)
            if ready > 0, ends[0].revents != 0 {
                drain()
                return .interrupted
            }
            if ready > 0 { return .input }
            // A signal can end the wait early; the handler has written to the pipe by then.
            guard ready < 0, errno == EINTR, ContinuousClock.now < deadline else { return .timedOut }
        }
    }

    private func drain() {
        var byte: UInt8 = 0
        while read(readEnd, &byte, 1) == 1 {}
    }

    /// Runs `body` with Ctrl-C caught, when these are the process's own interrupts; others
    /// only ever get `interrupt()`.
    func catchingControlC<T>(_ body: () throws -> T) rethrows -> T {
        guard self === Interrupts.process else { return try body() }
        drain()
        controlCWriteEnd = writeEnd
        let handler: @convention(c) (Int32) -> Void = { _ in
            var byte: UInt8 = 1
            _ = write(controlCWriteEnd, &byte, 1)
        }
        // Closing a terminal or asking the process to terminate must also undo a trial.
        // SIGKILL cannot be handled; logout remains the recovery boundary for that case.
        let previous = [SIGINT, SIGTERM, SIGHUP].map { ($0, signal($0, handler)) }
        defer { for (number, oldHandler) in previous { signal(number, oldHandler) } }
        return try body()
    }
}

/// Where the SIGINT handler writes: a C function cannot capture it. Set before the
/// handler is installed and never changed after, since `process` has one pipe.
nonisolated(unsafe) private var controlCWriteEnd: Int32 = -1
