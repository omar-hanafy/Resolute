import Foundation

/// Errors Resolute reports to people.
public enum ResoluteError: Error, Equatable, Sendable {
    case noDisplays
    case displayNotFound(String)
    case ambiguousDisplay(String, matches: [String])
    case modeNotFound(String, suggestions: [String])
    case refreshRateNotOffered(resolution: String, rate: String, offered: [String])
    case hiddenModeNeedsConfirmation(String)
    case currentModeUnknown(display: String)
    case revertFailed(display: String)
    case modeNotApplied(display: String)
    case coreGraphics(code: Int32, operation: String)
    case mirroringNeedsTwoDisplays
    case invalidResolution(String)
    case invalidFlags(String)
    case invalidEntry(String)
    case overrideUnreadable(path: String, reason: String)
    case commandFailed(status: Int32, message: String)
    case cancelled
    case needsRoot
}

extension ResoluteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noDisplays:
            "No online displays were found."
        case .displayNotFound(let selector):
            "No display matches “\(selector)”. Run `resolute displays` to list them."
        case .ambiguousDisplay(let selector, let matches):
            "“\(selector)” matches more than one display: \(matches.joined(separator: ", "))."
        case .modeNotFound(let query, let suggestions):
            suggestions.isEmpty
                ? "No display mode matches \(query)."
                : "No display mode matches \(query). Closest: \(suggestions.joined(separator: ", "))."
        case .refreshRateNotOffered(let resolution, let rate, let offered):
            "\(resolution) has no \(rate) mode. It offers \(ListFormat.and(offered))."
        case .hiddenModeNeedsConfirmation(let query):
            "\(query) is a hidden mode that macOS does not list. Pass --allow-hidden to use it."
        case .revertFailed(let display):
            "The previous mode of \(display) could not be restored. It comes back when you log out, or run `resolute set --default`."
        case .modeNotApplied(let display):
            "\(display) did not switch to that mode, so it was left as it was. The display may not support the mode."
        case .currentModeUnknown(let display):
            "The current mode of \(display) is unknown, so there is no resolution to keep. Give one, for example 1920x1080."
        case .coreGraphics(let code, let operation):
            "CoreGraphics could not \(operation): \(CGErrorName.name(for: code)) (\(code))."
        case .mirroringNeedsTwoDisplays:
            "Mirroring needs at least two displays."
        case .invalidResolution(let text):
            "“\(text)” is not a resolution. Use WIDTHxHEIGHT, optionally followed by one @2x or @1x and one refresh rate, for example 1920x1080@2x@60."
        case .invalidFlags(let text):
            "“\(text)” is not a flags value. Use two 32-bit hex words, for example 00000009 00a00000."
        case .invalidEntry(let message):
            message
        case .overrideUnreadable(let path, let reason):
            "Could not read \(path): \(reason)"
        case .commandFailed(let status, let message):
            message.isEmpty ? "The command failed with status \(status)." : message
        case .cancelled:
            "The operation was cancelled."
        case .needsRoot:
            "Writing display overrides needs administrator rights. Run the command with sudo, or use the Resolute app."
        }
    }
}

/// Names for CoreGraphics error codes (`CGError`).
public enum CGErrorName {
    public static func name(for code: Int32) -> String {
        switch code {
        case 0: "success"
        case 1000: "failure"
        case 1001: "illegal argument"
        case 1002: "invalid connection"
        case 1003: "invalid context"
        case 1004: "cannot complete"
        case 1006: "not implemented"
        case 1007: "range check"
        case 1008: "type check"
        case 1010: "invalid operation"
        case 1011: "none available"
        default: "error"
        }
    }
}

/// Joining words for messages.
enum ListFormat {
    /// "a", "a and b", "a, b and c"
    static func and(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}
