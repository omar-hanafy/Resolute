import Foundation

/// Why a preset could not be found, saved, read or written.
public enum PresetError: Error, Hashable, Sendable {
    /// What is wrong with a name.
    public enum NameProblem: Hashable, Sendable {
        case empty
        case tooLong
        case controlCharacters
    }

    /// No preset has this name; `suggestions` are names close to it.
    case notFound(String, suggestions: [String])
    /// The preset was changed by its ID, but it is gone: another process deleted it.
    case noLongerExists(UUID)
    case nameTaken(String)
    case invalidName(String, NameProblem)
    case shortcutTaken(KeyShortcut, by: String)
    /// No display could be saved; `reasons` say why for each display that was left out.
    case nothingToSave(reasons: [String])
    case unreadableFile(path: String, reason: String)
    /// The file has a format this version of Resolute does not write.
    case newerFile(path: String, version: Int)
    /// Another process held the presets lock for too long.
    case busy(path: String)
    case lockUnavailable(path: String, reason: String)
    case writeFailed(path: String, reason: String)
}

extension PresetError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound(let name, let suggestions):
            suggestions.isEmpty
                ? "There is no preset named “\(name)”."
                : "There is no preset named “\(name)”. Did you mean \(Self.either(suggestions.map { "“\($0)”" }))?"
        case .noLongerExists:
            "The preset no longer exists. It may have been deleted from the command line."
        case .nameTaken(let name):
            "There is already a preset named “\(name)”."
        case .invalidName(_, .empty):
            "A preset needs a name."
        case .invalidName(let name, .tooLong):
            "“\(name)” is too long for a preset name: names go up to \(PresetName.maximumLength) characters."
        case .invalidName(_, .controlCharacters):
            "A preset name can’t have line breaks, tabs or other control characters."
        case .shortcutTaken(let shortcut, let name):
            "\(shortcut.displayText) is already the shortcut for “\(name)”."
        case .nothingToSave(let reasons):
            reasons.isEmpty
                ? "There is nothing to save: the preset sets no display and leaves mirroring as it is."
                : "There is nothing to save. " + reasons.joined(separator: " ")
        case .unreadableFile(let path, let reason):
            "Could not read the presets in \(path): \(Self.clause(reason)). Fix the file, or move it away to start a new one."
        case .newerFile(let path, let version):
            "\(path) is in a newer format (version \(version)) than this version of Resolute writes, so it was left as it is. Update Resolute to change presets."
        case .busy:
            "Another Resolute process has been changing presets for too long. Try again when it has finished."
        case .lockUnavailable(let path, let reason):
            "Could not use the lock file \(path): \(Self.clause(reason))."
        case .writeFailed(let path, let reason):
            "Could not save the presets to \(path): \(Self.clause(reason))."
        }
    }

    /// `text` without a final full stop, to go inside a sentence: Foundation's own error
    /// messages end with one.
    static func clause(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }

    /// "a", "a or b", "a, b or c"
    static func either(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items[items.count - 1]
    }
}
