import Foundation
import os

/// The channel `resolute` uses to ask the running app for what only a person at the screen
/// can give: keeping a hidden mode on trial.
///
/// JSON lines over a Unix domain socket at `SupportLocations.agentSocket`. Every message is
/// one JSON object on one line and carries the protocol version. A connection carries one
/// request. `hello` is answered with `ready` at once, so the command learns that the app is
/// there before it changes anything. `confirmHiddenMode` is answered once a person decides
/// or the trial runs out; until then the command may send `dismiss` on the same connection,
/// and the app closes its dialog. Only the person who owns the support folder can connect:
/// the folder is private, the socket is 0600 and each side checks the other's user ID.
public enum AgentChannel {
    /// Written in every message. A side that receives another version says so instead of
    /// guessing what the other side meant.
    public static let version = 1
    /// The longest line either side reads, newline included. A request is a few hundred bytes.
    public static let maximumMessageSize = 16 * 1024
    /// The trial lengths a request may ask for, in seconds.
    public static let trialSecondsRange = 1...600
    /// How long a hidden mode is on trial when the app does not say otherwise.
    public static let defaultTrialSeconds = 15

    static let log = Logger(subsystem: ResoluteLog.subsystem, category: "agents")

    /// Why the command no longer needs an answer.
    public enum DismissReason: String, Codable, Sendable {
        /// Ctrl-C, a hangup or a request to terminate. The command puts the previous mode back.
        case interrupted
        /// The trial ran out, and the grace after it, without an answer. The command puts the
        /// previous mode back.
        case stoppedWaiting
    }

    /// How a request ended without its answer reaching the command.
    public enum Abandonment: Equatable, Sendable {
        /// The command said it stopped waiting; it puts the previous mode back itself.
        case dismissed(DismissReason)
        /// The connection closed without a word: the command was killed or crashed, so
        /// nothing puts the previous mode back unless the app does.
        case disconnected
    }

    /// The app's reply to `hello`.
    public struct Ready: Equatable, Sendable {
        /// The app's version, such as "0.3.0".
        public var appVersion: String
        /// How long the app gives a person to keep a hidden mode. The command asks for this
        /// trial length, so its message and the dialog's countdown agree.
        public var trialSeconds: Int

        public init(appVersion: String, trialSeconds: Int) {
            self.appVersion = appVersion
            self.trialSeconds = trialSeconds
        }
    }

    /// Why the app did not take a request.
    public struct Problem: Equatable, Sendable {
        public enum Code: String, Codable, Sendable {
            /// The message was written for another protocol version.
            case unsupportedVersion
            /// The message could not be read, or asked for something out of bounds.
            case badRequest
            /// The app is answering as many requests as it takes at once.
            case busy
            /// The person doesn't allow hidden modes asked for from the command line (Resolute's
            /// Settings › Command Line & Agents), so nothing may change.
            case refused
        }

        public var code: Code
        /// In words, for the command to show.
        public var message: String

        public init(_ code: Code, _ message: String) {
            self.code = code
            self.message = message
        }
    }

    /// What the command sends.
    public enum CommandMessage: Equatable, Sendable {
        case hello
        case confirmHiddenMode(ConfirmHiddenModeRequest)
        /// Only on the connection of a `confirmHiddenMode` the app has not answered.
        case dismiss(DismissReason)
    }

    /// What the app sends back.
    public enum AppMessage: Equatable, Sendable {
        case ready(Ready)
        case answer(ConfirmHiddenModeResponse)
        case error(Problem)
    }

    /// `message` as one line of JSON, newline included.
    public static func line(_ message: some Encodable) throws -> [UInt8] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var bytes = [UInt8](try encoder.encode(message))
        bytes.append(UInt8(ascii: "\n"))
        guard bytes.count <= maximumMessageSize else {
            throw AgentChannelError.unreadableMessage("the message is longer than \(maximumMessageSize) bytes")
        }
        return bytes
    }

    /// Reads one line, without its newline, as `type`. Throws `unsupportedVersion` for a
    /// message of another version and `unreadableMessage` for anything else it can't read.
    public static func decode<Message: Decodable>(_ type: Message.Type, from line: [UInt8]) throws -> Message {
        do {
            return try JSONDecoder().decode(type, from: Data(line))
        } catch let error as AgentChannelError {
            throw error
        } catch DecodingError.keyNotFound(let key, _) {
            throw AgentChannelError.unreadableMessage("it has no “\(key.stringValue)”")
        } catch DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context) {
            throw AgentChannelError.unreadableMessage("“\(context.codingPath.map(\.stringValue).joined(separator: "."))” has the wrong type")
        } catch DecodingError.dataCorrupted(let context) where !context.codingPath.isEmpty {
            throw AgentChannelError.unreadableMessage("“\(context.codingPath.map(\.stringValue).joined(separator: "."))” has an unknown value")
        } catch {
            throw AgentChannelError.unreadableMessage("it is not JSON")
        }
    }
}

// MARK: - Wire format

/// Keys every message has, besides its payload's own.
private enum EnvelopeKey: String, CodingKey {
    case version, type, reason
}

/// Reads the version first, so a message of another version is reported as such rather
/// than as whatever field it lacks.
private func envelope(_ decoder: any Decoder) throws -> (KeyedDecodingContainer<EnvelopeKey>, type: String) {
    let container = try decoder.container(keyedBy: EnvelopeKey.self)
    let version = try container.decode(Int.self, forKey: .version)
    guard version == AgentChannel.version else { throw AgentChannelError.unsupportedVersion(version) }
    return (container, try container.decode(String.self, forKey: .type))
}

extension AgentChannel.CommandMessage: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EnvelopeKey.self)
        try container.encode(AgentChannel.version, forKey: .version)
        switch self {
        case .hello:
            try container.encode("hello", forKey: .type)
        case .confirmHiddenMode(let request):
            try container.encode("confirmHiddenMode", forKey: .type)
            try request.encode(to: encoder)
        case .dismiss(let reason):
            try container.encode("dismiss", forKey: .type)
            try container.encode(reason, forKey: .reason)
        }
    }

    public init(from decoder: any Decoder) throws {
        let (container, type) = try envelope(decoder)
        switch type {
        case "hello":
            self = .hello
        case "confirmHiddenMode":
            self = .confirmHiddenMode(try ConfirmHiddenModeRequest(from: decoder))
        case "dismiss":
            // A reason this version does not know still dismisses.
            let reason = (try? container.decodeIfPresent(AgentChannel.DismissReason.self, forKey: .reason)) ?? nil
            self = .dismiss(reason ?? .stoppedWaiting)
        default:
            throw AgentChannelError.unreadableMessage("“\(type)” is not a request")
        }
    }
}

extension AgentChannel.AppMessage: Codable {
    private enum ReadyKey: String, CodingKey {
        case app, trialSeconds
    }

    private enum ErrorKey: String, CodingKey {
        case code, message
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EnvelopeKey.self)
        try container.encode(AgentChannel.version, forKey: .version)
        switch self {
        case .ready(let ready):
            try container.encode("ready", forKey: .type)
            var fields = encoder.container(keyedBy: ReadyKey.self)
            try fields.encode(ready.appVersion, forKey: .app)
            try fields.encode(ready.trialSeconds, forKey: .trialSeconds)
        case .answer(let response):
            try container.encode("answer", forKey: .type)
            try response.encode(to: encoder)
        case .error(let problem):
            try container.encode("error", forKey: .type)
            var fields = encoder.container(keyedBy: ErrorKey.self)
            try fields.encode(problem.code, forKey: .code)
            try fields.encode(problem.message, forKey: .message)
        }
    }

    public init(from decoder: any Decoder) throws {
        let (_, type) = try envelope(decoder)
        switch type {
        case "ready":
            let fields = try decoder.container(keyedBy: ReadyKey.self)
            let seconds = try fields.decode(Int.self, forKey: .trialSeconds)
            guard AgentChannel.trialSecondsRange.contains(seconds) else {
                throw AgentChannelError.unreadableMessage("a trial of \(seconds) seconds is out of bounds")
            }
            self = .ready(AgentChannel.Ready(appVersion: try fields.decode(String.self, forKey: .app), trialSeconds: seconds))
        case "answer":
            self = .answer(try ConfirmHiddenModeResponse(from: decoder))
        case "error":
            let fields = try decoder.container(keyedBy: ErrorKey.self)
            self = .error(AgentChannel.Problem(
                try fields.decode(AgentChannel.Problem.Code.self, forKey: .code),
                try fields.decode(String.self, forKey: .message)
            ))
        default:
            throw AgentChannelError.unreadableMessage("“\(type)” is not a reply")
        }
    }
}

// MARK: - Errors

/// Why talking over the channel failed.
public enum AgentChannelError: Error, Equatable, Sendable {
    /// Nobody listens at the socket: the app is not running, or is a version without the channel.
    case appNotRunning
    /// The socket's path is longer than a Unix socket address holds (103 bytes).
    case pathTooLong(String)
    /// The other side did not connect, reply or take a message in time.
    case timedOut
    /// The app closed the connection before it answered.
    case closedWithoutAnswer
    /// The other side runs as another user.
    case untrustedPeer(userID: UInt32)
    /// A message that is not JSON of this protocol, or is too long.
    case unreadableMessage(String)
    /// A message of another protocol version.
    case unsupportedVersion(Int)
    /// A request with a value out of bounds.
    case invalidRequest(String)
    /// The app turned the request down.
    case refused(AgentChannel.Problem)
    /// Another app already listens at the socket.
    case alreadyListening(String)
    /// The socket's folder or path is not safe to use.
    case unsafeLocation(String)
    /// A system call failed.
    case system(String, code: Int32)
}

extension AgentChannelError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .appNotRunning:
            "Resolute is not running."
        case .pathTooLong(let path):
            "The socket path is too long for a Unix socket: \(path)."
        case .timedOut:
            "Resolute did not reply in time."
        case .closedWithoutAnswer:
            "Resolute closed the request without an answer."
        case .untrustedPeer(let userID):
            "The other end of the agent channel runs as another user (\(userID))."
        case .unreadableMessage(let reason):
            "A message on the agent channel could not be read: \(reason)."
        case .unsupportedVersion(let version):
            "A message used version \(version) of the agent channel; this Resolute speaks version \(AgentChannel.version)."
        case .invalidRequest(let reason):
            "The request is not valid: \(reason)."
        case .refused(let problem):
            problem.message
        case .alreadyListening(let path):
            "Another Resolute already listens at \(path)."
        case .unsafeLocation(let reason):
            reason
        case .system(let operation, let code):
            "Could not \(operation): \(String(cString: strerror(code)))."
        }
    }
}
