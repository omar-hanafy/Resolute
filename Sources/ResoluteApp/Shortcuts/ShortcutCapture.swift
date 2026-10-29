import AppKit
import ResoluteKit

/// What a key pressed while the shortcut recorder records does. Esc alone cancels and
/// Delete alone clears; a key with Control, Option or Command becomes the shortcut unless
/// something else has it already.
enum ShortcutCapture: Equatable {
    /// The new shortcut.
    case record(KeyShortcut)
    /// Stop recording and keep the shortcut there was.
    case cancel
    /// Stop recording and leave no shortcut.
    case clear
    /// Keep recording and say why the key can't be the shortcut.
    case refuse(String)

    /// The modifiers a shortcut is made of; Caps Lock, Fn and the like don't count.
    static let shortcutModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// What pressing `keyCode` with `modifierFlags` does. `conflict` says what already uses a
    /// shortcut, or nil when it is free.
    static func handle(
        keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, conflict: (KeyShortcut) -> String?
    ) -> ShortcutCapture {
        let modifiers = modifierFlags.intersection(shortcutModifiers)
        if modifiers.isEmpty {
            let name = KeyShortcut.keyCodes.first { $0.value == keyCode }?.key
            if name == "escape" { return .cancel }
            if name == "delete" || name == "forwarddelete" { return .clear }
        }
        guard let shortcut = KeyShortcut(keyCode: keyCode, modifierFlags: modifiers) else {
            return KeyShortcut.keyCodes.values.contains(keyCode) ? .refuse(needsModifier) : .refuse(unsupportedKey)
        }
        if let conflict = conflict(shortcut) { return .refuse(conflict) }
        return .record(shortcut)
    }

    /// A key without Control, Option or Command would take the key away from typing.
    static let needsModifier = "Use Control, Option or Command with the key."
    /// Keys such as Fn, the media keys and keypad keys.
    static let unsupportedKey = "That key can’t be part of a shortcut."
}
