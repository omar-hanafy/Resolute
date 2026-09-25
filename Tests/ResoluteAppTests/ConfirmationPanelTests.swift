import AppKit
import Testing
@testable import ResoluteApp

@MainActor
@Suite struct ConfirmationPanelTests {
    func keyDown(_ characters: String, keyCode: UInt16) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }

    /// NSAlert gives Escape only to a button titled Cancel, so in "Keep this display
    /// mode?" it did nothing. Revert is the first button.
    @Test func escapeReverts() throws {
        #expect(ConfirmationPanel.response(to: try keyDown("\u{1B}", keyCode: 53)) == .alertFirstButtonReturn)
    }

    /// Return already belongs to Revert, the default button, and no key may choose Keep.
    @Test(arguments: [("\r", UInt16(36)), ("k", UInt16(40))])
    func leavesOtherKeysToTheAlert(characters: String, keyCode: UInt16) throws {
        #expect(ConfirmationPanel.response(to: try keyDown(characters, keyCode: keyCode)) == nil)
    }
}
