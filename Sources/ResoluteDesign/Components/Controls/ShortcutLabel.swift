import AppKit
import SwiftUI

/// A keyboard shortcut, written the way macOS writes them: "⌃⌥1" on a preset card, "⌘,"
/// in a panel row, "⌃⌥R" in Settings. VoiceOver reads it in words ("Control-Option-1").
public struct ShortcutLabel: View {
    public enum Style: Sendable {
        /// A key chip: `macOS/Footnote Emphasized` on `surface/track` (Figma 37:2289's
        /// preset cards).
        case chip
        /// At the end of a panel row, like a menu item's key equivalent: `macOS/Body` in
        /// `Labels/Tertiary` (Figma 20:156).
        case menuItem
        /// The value of a form row: `macOS/Body` in `Labels/Secondary` (Figma 40:149).
        case formRow
    }

    public var keys: String
    public var style: Style

    /// - Parameter keys: the shortcut as macOS writes it, modifiers first ("⌃⌥1").
    public init(_ keys: String, style: Style = .chip) {
        self.keys = keys
        self.style = style
    }

    public init(key: String, modifiers: NSEvent.ModifierFlags, style: Style = .chip) {
        self.init(Self.text(key: key, modifiers: modifiers), style: style)
    }

    public var body: some View {
        label
            .fixedSize()
            .accessibilityLabel(Text(Self.spokenText(keys)))
    }

    @ViewBuilder private var label: some View {
        switch style {
        case .chip:
            Text(keys)
                .textBox(.footnoteEmphasized)
                .lineLimit(1)
                .foregroundStyle(Palette.labelSecondary)
                .padding(.horizontal, Metrics.ShortcutChip.horizontalPadding)
                .padding(.vertical, Metrics.ShortcutChip.verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.ShortcutChip.cornerRadius, style: .continuous)
                        .fill(Palette.surfaceTrack)
                )
        case .menuItem:
            Text(keys).textBox(.body).lineLimit(1).foregroundStyle(Palette.labelTertiary)
        case .formRow:
            Text(keys).textBox(.body).lineLimit(1).foregroundStyle(Palette.labelSecondary)
        }
    }

    /// The modifiers' symbols in the order macOS writes them (⌃⌥⇧⌘), then the key; a
    /// letter key is written in capitals, as menus show it.
    public static func text(key: String, modifiers: NSEvent.ModifierFlags) -> String {
        let symbols = modifierWords.filter { modifiers.contains($0.flag) }.map(\.symbol)
        let written = key.count == 1 && key.first?.isLetter == true ? key.uppercased() : key
        return String(symbols) + written
    }

    /// The shortcut in words, for VoiceOver: "⌃⌥1" is "Control-Option-1", "⌘," is
    /// "Command-Comma".
    public static func spokenText(_ keys: String) -> String {
        SpokenText.shortcut(keys)
    }

    private static let modifierWords: [(flag: NSEvent.ModifierFlags, symbol: Character, word: String)] = [
        (.control, "⌃", "Control"),
        (.option, "⌥", "Option"),
        (.shift, "⇧", "Shift"),
        (.command, "⌘", "Command"),
    ]
}
