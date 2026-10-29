import AppKit
import ResoluteKit

/// Shortcuts that work from anywhere: the panel's (Settings › General) and each preset's.
/// They are the presets file's `KeyShortcut`, with what registering one needs: the key's
/// virtual key code and AppKit's modifier flags. Keys are named by their place on a US
/// keyboard ("r", "f1", "left"), so a shortcut means the same key on every layout.
extension KeyShortcut {
    /// The panel's shortcut until the person changes it (Figma: Settings › General, Open the panel).
    static let openPanel = KeyShortcut(key: "r", modifiers: [.control, .option])!

    /// A shortcut that can work from anywhere: a key Resolute can register and at least one
    /// modifier besides Shift, so it never takes a key away from typing.
    var isGlobal: Bool {
        Self.keyCodes[key] != nil && !modifiers.subtracting(.shift).isEmpty
    }

    /// Reads a spec such as "control+option+r", as the preferences keep it. Only a shortcut
    /// that can work from anywhere is read.
    init?(spec: String) {
        var parts = spec.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let key = parts.popLast() else { return nil }
        var modifiers: Modifiers = []
        for part in parts {
            guard let modifier = Self.modifierNames[part.lowercased()], !modifiers.contains(modifier) else { return nil }
            modifiers.insert(modifier)
        }
        guard let shortcut = KeyShortcut(key: key, modifiers: modifiers), shortcut.isGlobal else { return nil }
        self = shortcut
    }

    /// The shortcut of a key pressed in a shortcut recorder; nil for a key that can't work
    /// from anywhere.
    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        guard let key = Self.keyCodes.first(where: { $0.value == keyCode })?.key else { return nil }
        var modifiers: Modifiers = []
        if modifierFlags.contains(.control) { modifiers.insert(.control) }
        if modifierFlags.contains(.option) { modifiers.insert(.option) }
        if modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if modifierFlags.contains(.command) { modifiers.insert(.command) }
        guard let shortcut = KeyShortcut(key: key, modifiers: modifiers), shortcut.isGlobal else { return nil }
        self = shortcut
    }

    /// "control+option+r": how the preferences store it.
    var spec: String {
        (modifiers.names + [key]).joined(separator: "+")
    }

    /// The macOS virtual key code (`kVK_…`), which shortcut registration takes.
    var keyCode: UInt16 { Self.keyCodes[key] ?? 0 }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.command) { flags.insert(.command) }
        return flags
    }

    private static let modifierNames: [String: Modifiers] = [
        "control": .control, "option": .option, "shift": .shift, "command": .command,
    ]

    /// Keys by their US-keyboard names, with the virtual key codes of HIToolbox's Events.h.
    static let keyCodes: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "return": 0x24, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28,
        ";": 0x29, "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "tab": 0x30,
        "space": 0x31, "`": 0x32, "delete": 0x33, "escape": 0x35,
        "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
        "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F, "f13": 0x69, "f14": 0x6B, "f15": 0x71,
        "f16": 0x6A, "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
        "home": 0x73, "pageup": 0x74, "forwarddelete": 0x75, "end": 0x77, "pagedown": 0x79,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
}
