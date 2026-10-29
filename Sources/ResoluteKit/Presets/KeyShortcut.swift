import Foundation

/// A keyboard shortcut, kept as a key and modifiers rather than a key code, so the presets
/// file reads the same on every keyboard layout. The app turns it into a hot key.
public struct KeyShortcut: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)

        /// Each modifier with its name in the presets file, its symbol and its spoken name,
        /// in the order macOS menus show them.
        static let all: [(modifier: Modifiers, name: String, symbol: String, spoken: String)] = [
            (.control, "control", "⌃", "Control"),
            (.option, "option", "⌥", "Option"),
            (.shift, "shift", "⇧", "Shift"),
            (.command, "command", "⌘", "Command"),
        ]

        /// The names the presets file uses, in menu order.
        public var names: [String] {
            Self.all.filter { contains($0.modifier) }.map(\.name)
        }

        /// Reads names such as "control" and "option"; nil when one is not a modifier.
        public init?(names: [String]) {
            var modifiers: Modifiers = []
            for name in names {
                guard let match = Self.all.first(where: { $0.name == name.lowercased() }) else { return nil }
                modifiers.insert(match.modifier)
            }
            self = modifiers
        }
    }

    /// Keys that are not a character, by the name the presets file uses, with their symbol
    /// and spoken name.
    static let namedKeys: [String: (symbol: String, spoken: String)] = {
        var keys: [String: (symbol: String, spoken: String)] = [
            "return": ("↩", "Return"), "tab": ("⇥", "Tab"), "space": ("Space", "Space"),
            "delete": ("⌫", "Delete"), "forwarddelete": ("⌦", "Forward Delete"), "escape": ("⎋", "Escape"),
            "left": ("←", "Left Arrow"), "right": ("→", "Right Arrow"), "up": ("↑", "Up Arrow"),
            "down": ("↓", "Down Arrow"), "home": ("↖", "Home"), "end": ("↘", "End"),
            "pageup": ("⇞", "Page Up"), "pagedown": ("⇟", "Page Down"),
        ]
        for number in 1...20 { keys["f\(number)"] = ("F\(number)", "F\(number)") }
        return keys
    }()

    /// A character key as its lowercase character ("1", "a", "/"), or a named key such as
    /// "f1", "space", "return" or "left".
    public let key: String
    public let modifiers: Modifiers

    /// Nil when `key` is neither one visible character nor a named key.
    public init?(key: String, modifiers: Modifiers) {
        let lowercased = key.lowercased()
        if Self.namedKeys[lowercased] != nil {
            self.key = lowercased
        } else {
            guard key.count == 1, lowercased.count == 1, let character = lowercased.first, !character.isWhitespace,
                  !character.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
            else { return nil }
            self.key = String(character)
        }
        self.modifiers = modifiers
    }

    /// "⌃⌥1": the modifiers in the order macOS menus show them, then the key.
    public var displayText: String {
        let symbols = Modifiers.all.filter { modifiers.contains($0.modifier) }.map(\.symbol).joined()
        return symbols + (Self.namedKeys[key]?.symbol ?? key.uppercased())
    }

    /// "Control-Option-1", for VoiceOver, which may read the symbols as shapes.
    public var spokenText: String {
        let names = Modifiers.all.filter { modifiers.contains($0.modifier) }.map(\.spoken)
        return (names + [Self.namedKeys[key]?.spoken ?? key.uppercased()]).joined(separator: "-")
    }
}
