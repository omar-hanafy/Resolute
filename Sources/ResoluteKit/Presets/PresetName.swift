import Foundation

/// What a preset may be called, and when two names are the same preset.
public enum PresetName {
    /// Room for any sensible name, short enough for a chip in the panel.
    public static let maximumLength = 64

    /// `name` without the spaces around it. Throws `PresetError.invalidName` for a name that
    /// is empty, too long, or has a line break or another control character, none of which
    /// a menu, a chip or a shell command shows well.
    public static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PresetError.invalidName(name, .empty) }
        guard trimmed.count <= maximumLength else { throw PresetError.invalidName(trimmed, .tooLong) }
        let breaks: [Unicode.GeneralCategory] = [.control, .lineSeparator, .paragraphSeparator]
        guard !trimmed.unicodeScalars.contains(where: { breaks.contains($0.properties.generalCategory) }) else {
            throw PresetError.invalidName(trimmed, .controlCharacters)
        }
        return trimmed
    }

    /// Whether two names belong to the same preset: case and the spaces around them don't count.
    public static func same(_ lhs: String, _ rhs: String) -> Bool {
        key(lhs) == key(rhs)
    }

    /// The names among `names` close enough to `name` to be what was meant, best first: one
    /// that starts with what was typed, one that contains it, then one or two letters off.
    public static func suggestions(for name: String, among names: [String]) -> [String] {
        let typed = key(name)
        guard !typed.isEmpty else { return [] }
        let ranked = names.enumerated().compactMap { offset, candidate -> (rank: Int, offset: Int, name: String)? in
            let other = key(candidate)
            guard other != typed else { return nil }
            if typed.count >= 3, other.hasPrefix(typed) { return (0, offset, candidate) }
            if other.count >= 3, typed.hasPrefix(other) { return (0, offset, candidate) }
            if typed.count >= 3, other.contains(typed) { return (1, offset, candidate) }
            let distance = editDistance(typed, other)
            // One letter is a lot in a short name.
            let allowed = typed.count <= 3 ? 1 : 2
            return distance <= allowed ? (1 + distance, offset, candidate) : nil
        }
        return ranked.sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }.prefix(3).map(\.name)
    }

    /// The form names are compared in.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive], locale: nil)
    }

    static func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs), right = Array(rhs)
        guard !left.isEmpty, !right.isEmpty else { return max(left.count, right.count) }
        var previous = Array(0...right.count)
        for i in 1...left.count {
            var current = [i] + Array(repeating: 0, count: right.count)
            for j in 1...right.count {
                let substitution = previous[j - 1] + (left[i - 1] == right[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            previous = current
        }
        return previous[right.count]
    }
}
