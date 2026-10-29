import Darwin
import Foundation

/// The command's side of the agent channel: is the app there, and what does the person at
/// the display say.
public struct AgentChannelClient: Sendable {
    /// Whether the app can be asked.
    public enum AppStatus: Equatable, Sendable {
        case ready(AgentChannel.Ready)
        /// Nothing listens: the app is not running, or is a version without the channel.
        case notRunning
        /// Something listens but can't be asked; why, in words.
        case unavailable(String)
        /// The app turned the request away: the person doesn't allow hidden modes from the
        /// command line. Why, in words.
        case refused(String)
    }

    public var socket: URL
    /// How long connecting, sending a request and the reply to `hello` may take. The app
    /// replies at once: its listener does not wait for the main thread.
    public var responseTimeout: Duration
    /// How much longer than the trial the command waits for an answer before it stops
    /// waiting and puts the previous mode back itself.
    public var answerGrace: Duration

    public init(socket: URL, responseTimeout: Duration = .seconds(2), answerGrace: Duration = .seconds(5)) {
        self.socket = socket
        self.responseTimeout = responseTimeout
        self.answerGrace = answerGrace
    }

    /// Says hello, before anything changes, to learn whether the app is there to ask and how
    /// long its trial lasts.
    public func checkApp() -> AppStatus {
        let deadline = ContinuousClock.now + responseTimeout
        do {
            let descriptor = try connect(until: deadline)
            defer { close(descriptor) }
            try Self.send(.hello, on: descriptor, until: deadline)
            var buffer = LineBuffer()
            switch try Self.reply(on: descriptor, into: &buffer, until: deadline) {
            case .ready(let ready):
                return .ready(ready)
            case .error(let problem) where problem.code == .refused:
                return .refused(problem.message)
            case .error(let problem):
                return .unavailable(problem.message)
            case .answer:
                return .unavailable("Resolute answered a question it was not asked.")
            }
        } catch AgentChannelError.appNotRunning {
            return .notRunning
        } catch {
            AgentChannel.log.error("Resolute could not be asked: \(error.localizedDescription, privacy: .public)")
            return .unavailable(error.localizedDescription)
        }
    }

    /// Sends `request` and returns it open, for the answer to be awaited.
    public func ask(_ request: ConfirmHiddenModeRequest) throws -> PendingAnswer {
        try request.validate()
        let deadline = ContinuousClock.now + responseTimeout
        let descriptor = try connect(until: deadline)
        do {
            try Self.send(.confirmHiddenMode(request), on: descriptor, until: deadline)
        } catch {
            close(descriptor)
            throw error
        }
        AgentChannel.log.notice("""
            Asked Resolute to confirm mode \(request.modeID) on \(request.display.name, privacy: .public) \
            for \(request.requester.name, privacy: .public)
            """)
        return PendingAnswer(descriptor: descriptor)
    }

    /// Connects, and checks that the app runs as the person whose folder holds the socket.
    private func connect(until deadline: ContinuousClock.Instant) throws -> Int32 {
        let descriptor = try UnixSocket.connect(to: socket, until: deadline)
        let user = UnixSocket.peerUserID(of: descriptor)
        guard let user, user == Self.expectedAppUserID(environment: ProcessInfo.processInfo.environment) else {
            close(descriptor)
            throw AgentChannelError.untrustedPeer(userID: user ?? UInt32.max)
        }
        return descriptor
    }

    /// The app runs as the person using the Mac. Under `sudo` the command runs as root, but
    /// the socket is in the folder of the person who ran sudo, as `SupportLocations` finds it.
    static func expectedAppUserID(environment: [String: String]) -> uid_t {
        let user = geteuid()
        guard user == 0, let sudoUser = environment["SUDO_UID"].flatMap(uid_t.init) else { return user }
        return sudoUser
    }

    /// Sends `message`. An app that turns a connection away, as busy, closes it at once and
    /// may do so before the message goes out; then the reason it already sent is the error.
    static func send(
        _ message: AgentChannel.CommandMessage, on descriptor: Int32, until deadline: ContinuousClock.Instant
    ) throws {
        do {
            try UnixSocket.write(try AgentChannel.line(message), to: descriptor, until: deadline)
        } catch AgentChannelError.closedWithoutAnswer {
            var buffer = LineBuffer()
            if case .error(let problem)? = try? reply(on: descriptor, into: &buffer, until: .now) {
                throw AgentChannelError.refused(problem)
            }
            throw AgentChannelError.closedWithoutAnswer
        }
    }

    /// The first message on `descriptor`, waiting for it until `deadline`.
    static func reply(
        on descriptor: Int32, into buffer: inout LineBuffer, until deadline: ContinuousClock.Instant
    ) throws -> AgentChannel.AppMessage {
        while true {
            let read = UnixSocket.read(from: descriptor, into: &buffer)
            switch buffer.next() {
            case .line(let line):
                return try AgentChannel.decode(AgentChannel.AppMessage.self, from: line)
            case .tooLong:
                throw AgentChannelError.unreadableMessage("the reply is longer than \(buffer.limit) bytes")
            case .incomplete:
                guard read == .open else { throw AgentChannelError.closedWithoutAnswer }
                guard UnixSocket.waitUntilReadable(descriptor, until: deadline) else { throw AgentChannelError.timedOut }
            }
        }
    }
}

/// A request the app is answering. Poll `fileDescriptor` and call `readAnswer()` when it is
/// readable, or call `waitForAnswer(until:)`. Closing it, or dismissing it, closes the
/// app's dialog if it is still up.
public final class PendingAnswer {
    public enum Progress: Equatable, Sendable {
        /// Nothing complete has arrived yet.
        case waiting
        case answered(ConfirmHiddenModeResponse)
        /// No answer will come; why.
        case failed(AgentChannelError)
    }

    /// Readable once the app answers or closes the connection. Valid until `close()`.
    public let fileDescriptor: Int32
    private var buffer = LineBuffer()
    private var isOpen = true
    /// The answer or failure, once there is one.
    private var outcome: Progress?

    init(descriptor: Int32) {
        fileDescriptor = descriptor
    }

    deinit {
        close()
    }

    /// Reads what has arrived, without waiting.
    public func readAnswer() -> Progress {
        if let outcome { return outcome }
        guard isOpen else { return .failed(.closedWithoutAnswer) }
        let read = UnixSocket.read(from: fileDescriptor, into: &buffer)
        let progress: Progress
        switch buffer.next() {
        case .line(let line):
            do {
                switch try AgentChannel.decode(AgentChannel.AppMessage.self, from: line) {
                case .answer(let response): progress = .answered(response)
                case .error(let problem): progress = .failed(.refused(problem))
                case .ready: progress = .failed(.unreadableMessage("the app said hello instead of answering"))
                }
            } catch let error as AgentChannelError {
                progress = .failed(error)
            } catch {
                progress = .failed(.unreadableMessage(error.localizedDescription))
            }
        case .tooLong:
            progress = .failed(.unreadableMessage("the answer is longer than \(buffer.limit) bytes"))
        case .incomplete:
            guard read != .open else { return .waiting }
            progress = .failed(.closedWithoutAnswer)
        }
        outcome = progress
        if case .answered(let response) = progress {
            AgentChannel.log.notice("""
                Resolute answered \(response.answer.rawValue, privacy: .public)\
                \(response.reason.map { ": " + $0 } ?? "", privacy: .public)
                """)
        }
        return progress
    }

    /// Waits for the answer until `deadline`, for callers without a wait of their own.
    public func waitForAnswer(until deadline: ContinuousClock.Instant) -> Progress {
        while true {
            let progress = readAnswer()
            guard progress == .waiting else { return progress }
            guard UnixSocket.waitUntilReadable(fileDescriptor, until: deadline) else { return .failed(.timedOut) }
        }
    }

    /// Tells the app the answer is no longer needed, so it closes its dialog, and closes
    /// the connection. The caller puts the previous mode back.
    public func dismiss(_ reason: AgentChannel.DismissReason) {
        guard isOpen else { return }
        if outcome == nil, let line = try? AgentChannel.line(AgentChannel.CommandMessage.dismiss(reason)) {
            // The app may have closed the connection already; a closed one is a dismissal too.
            try? UnixSocket.write(line, to: fileDescriptor, until: .now + .milliseconds(500))
        }
        AgentChannel.log.notice("Stopped waiting for Resolute's answer: \(reason.rawValue, privacy: .public)")
        close()
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        Darwin.close(fileDescriptor)
    }
}
