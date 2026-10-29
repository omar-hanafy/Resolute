/// Text as VoiceOver should read it. VoiceOver reads "×" as "multiplied by", "→" as
/// "right arrow" and a shortcut's "⌃⌥" as nothing useful, and the middle dot that
/// separates facts on screen reads better as a pause.
public enum SpokenText {
    /// Sizes and changes in words: "2560 × 1440 → 2880 × 1620" reads as "2560 by 1440 to
    /// 2880 by 1620", "Low Resolution (1×)" as "Low Resolution (1x)", "Larger Text ↔ More
    /// Space" as "Larger Text to More Space" and "2560 × 1440 · 60 Hz" as "2560 by 1440,
    /// 60 Hz". Everything else is left as it is.
    public static func sizes(_ written: String) -> String {
        written
            .replacing(#/(\d)\s*×\s*(\d)/#) { "\($0.output.1) by \($0.output.2)" }
            .replacingOccurrences(of: "×", with: "x")
            .replacing(#/\s*[→↔]\s*/#) { _ in " to " }
            .replacingOccurrences(of: " · ", with: ", ")
    }

    /// A shortcut as macOS names it in menus: "⌃⌥1" reads as "Control-Option-1", "⌘," as
    /// "Command-Comma".
    public static func shortcut(_ keys: String) -> String {
        var words: [String] = []
        var rest = Substring(keys)
        while let first = rest.first, let modifier = modifierWords[first] {
            words.append(modifier)
            rest = rest.dropFirst()
        }
        if !rest.isEmpty {
            words.append(keyWords[String(rest)] ?? String(rest))
        }
        return words.joined(separator: "-")
    }

    private static let modifierWords: [Character: String] = [
        "⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command",
    ]

    /// Keys whose written form VoiceOver would read as punctuation or not at all.
    private static let keyWords: [String: String] = [
        ",": "Comma", ".": "Period", "/": "Slash", "\\": "Backslash", ";": "Semicolon",
        "'": "Quote", "`": "Grave Accent", "-": "Minus", "=": "Equals", "[": "Left Bracket",
        "]": "Right Bracket", "↩": "Return", "⌅": "Enter", "⇥": "Tab", "⌫": "Delete",
        "⌦": "Forward Delete", "⎋": "Escape", "␣": "Space", "←": "Left Arrow",
        "→": "Right Arrow", "↑": "Up Arrow", "↓": "Down Arrow", "⇞": "Page Up",
        "⇟": "Page Down", "↖": "Home", "↘": "End",
    ]
}
