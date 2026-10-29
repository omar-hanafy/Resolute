import AppKit
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// What the shortcut recorder does with each key pressed while it records.
@Suite struct ShortcutRecorderTests {
    let free: (KeyShortcut) -> String? = { _ in nil }

    func code(_ key: String) throws -> UInt16 {
        try #require(KeyShortcut.keyCodes[key])
    }

    @Test func recordsAKeyWithAModifier() throws {
        #expect(ShortcutCapture.handle(keyCode: try code("r"), modifierFlags: [.control, .option], conflict: free) == .record(.openPanel))
        let f5 = try #require(KeyShortcut(key: "f5", modifiers: [.command, .shift]))
        // Caps Lock and Fn don't count, and the order of the modifiers doesn't matter.
        #expect(ShortcutCapture.handle(keyCode: try code("f5"), modifierFlags: [.shift, .command, .capsLock, .function], conflict: free) == .record(f5))
    }

    @Test func escCancelsAndDeleteClears() throws {
        #expect(ShortcutCapture.handle(keyCode: try code("escape"), modifierFlags: [], conflict: free) == .cancel)
        #expect(ShortcutCapture.handle(keyCode: try code("delete"), modifierFlags: [], conflict: free) == .clear)
        #expect(ShortcutCapture.handle(keyCode: try code("forwarddelete"), modifierFlags: [.capsLock], conflict: free) == .clear)
        // With a modifier they are shortcuts like any other key.
        let commandDelete = try #require(KeyShortcut(key: "delete", modifiers: [.command]))
        #expect(ShortcutCapture.handle(keyCode: try code("delete"), modifierFlags: [.command], conflict: free) == .record(commandDelete))
    }

    @Test func refusesAKeyThatWouldTakeAwayTyping() throws {
        #expect(ShortcutCapture.handle(keyCode: try code("a"), modifierFlags: [], conflict: free) == .refuse(ShortcutCapture.needsModifier))
        #expect(ShortcutCapture.handle(keyCode: try code("a"), modifierFlags: [.shift], conflict: free) == .refuse(ShortcutCapture.needsModifier))
        // 0x3F is Fn, which Resolute can't register.
        #expect(ShortcutCapture.handle(keyCode: 0x3F, modifierFlags: [.command], conflict: free) == .refuse(ShortcutCapture.unsupportedKey))
    }

    @Test func refusesAShortcutSomethingElseHas() throws {
        let taken: (KeyShortcut) -> String? = { $0 == .openPanel ? "⌃⌥R already opens the panel." : nil }
        #expect(ShortcutCapture.handle(keyCode: try code("r"), modifierFlags: [.control, .option], conflict: taken) == .refuse("⌃⌥R already opens the panel."))
        #expect(ShortcutCapture.handle(keyCode: try code("t"), modifierFlags: [.control, .option], conflict: taken) != .refuse("⌃⌥R already opens the panel."))
    }

    @Test func saysTheShortcutInWordsForVoiceOver() throws {
        #expect(KeyShortcut.openPanel.spokenText == "Control-Option-R")
        #expect(try #require(KeyShortcut(key: "left", modifiers: [.command, .shift])).spokenText == "Shift-Command-Left Arrow")
    }
}
