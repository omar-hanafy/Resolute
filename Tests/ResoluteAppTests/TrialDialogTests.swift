import AppKit
import Testing
import ResoluteKit
@testable import ResoluteApp

/// A clock tests move by hand.
@MainActor
final class TrialTestClock {
    var now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_000)) {
        self.now = now
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    var read: @MainActor () -> Date { { self.now } }
}

@MainActor
func trialQuestion(start: Date, seconds: TimeInterval = 15, requester: Requester? = nil, previousMode: String? = "2560 × 1440") -> TrialQuestion {
    TrialQuestion(
        displayID: 3, displayName: "DELL U2723QE", mode: "2880 × 1620", previousMode: previousMode,
        countdown: RevertCountdown(start: start, duration: seconds), requester: requester
    )
}

func trialKeyDown(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil,
        characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
    ))
}

/// The Keep/Revert dialog's rules, driven through its model as its window drives it: the
/// countdown, the answer given once, and the keys. Nothing is shown.
@MainActor
@Suite struct TrialDialogTests {
    let clock = TrialTestClock()

    func model(seconds: TimeInterval = 15, requester: Requester? = nil) -> TrialDialogModel {
        TrialDialogModel(question: trialQuestion(start: clock.now, seconds: seconds, requester: requester), clock: clock.read)
    }

    // MARK: Answers (ported from ConfirmationPanelTests)

    /// Keep counts only before the deadline: a click can arrive after it but before the
    /// next tick.
    @Test(arguments: [(14.99, TrialDialogModel.Answer.kept), (15, .noAnswer), (16, .noAnswer)])
    func refusesKeepAtOrAfterTheDeadline(after seconds: TimeInterval, answer: TrialDialogModel.Answer) {
        let dialog = model()
        clock.advance(seconds)
        dialog.keep()
        #expect(dialog.answer == answer)
    }

    @Test func revertIsAPersonsAnswer() {
        let dialog = model()
        dialog.revert()
        #expect(dialog.answer == .reverted)
        #expect(dialog.answer?.isPersons == true)
    }

    /// Nothing clicked: the countdown answers on its own at the deadline.
    @Test func revertsOnTimeWhenNobodyAnswers() {
        let dialog = model()
        var told: [TrialDialogModel.Answer] = []
        dialog.onAnswer = { told.append($0) }
        clock.advance(14.9)
        dialog.tick()
        #expect(dialog.answer == nil)
        clock.advance(0.1)
        dialog.tick()
        #expect(dialog.answer == .noAnswer)
        #expect(told == [.noAnswer])
    }

    /// The first answer stands, and is told once: a late click or the next tick changes nothing.
    @Test func answersOnce() {
        let dialog = model()
        var told: [TrialDialogModel.Answer] = []
        dialog.onAnswer = { told.append($0) }
        dialog.revert()
        dialog.keep()
        clock.advance(20)
        dialog.tick()
        dialog.dismiss()
        #expect(dialog.answer == .reverted)
        #expect(told == [.reverted])
    }

    @Test func dismissalIsNotAPersonsAnswer() {
        let dialog = model()
        dialog.dismiss()
        #expect(dialog.answer == .dismissed)
        #expect(dialog.answer?.isPersons == false)
    }

    // MARK: Countdown

    @Test func countsDownTheWholeTrial() {
        let dialog = model()
        #expect(dialog.total == 15)
        #expect(dialog.secondsLeft == 15)
        clock.advance(3.2)
        dialog.tick()
        #expect(dialog.secondsLeft == 12)
        #expect(abs(dialog.remaining - 11.8) < 0.0001)
        #expect(dialog.message.hasSuffix("It switches back to 2560 × 1440 in 12 seconds."))
    }

    /// The question is made just before it is asked; the bar's length is the trial's,
    /// in whole seconds, not the moment less.
    @Test func takesTheTrialLengthFromTheQuestion() {
        let question = trialQuestion(start: clock.now, seconds: 30)
        clock.advance(0.004)
        #expect(TrialDialogModel(question: question, clock: clock.read).total == 30)
    }

    // MARK: Keys and the modal session

    /// NSAlert gave Escape only to a button titled Cancel; here Return, Enter and Escape all
    /// revert, the safe choice on a screen that can't be read.
    @Test(arguments: [("\r", UInt16(36)), ("\u{3}", UInt16(76)), ("\u{1B}", UInt16(53))])
    func returnEnterAndEscapeRevert(characters: String, keyCode: UInt16) throws {
        #expect(TrialDialogModel.answersRevert(try trialKeyDown(characters, keyCode: keyCode)))
    }

    /// No key chooses Keep, and shortcuts with modifiers are left to the menus.
    @Test func leavesOtherKeysAlone() throws {
        #expect(!TrialDialogModel.answersRevert(try trialKeyDown("k", keyCode: 40)))
        #expect(!TrialDialogModel.answersRevert(try trialKeyDown(" ", keyCode: 49)))
        #expect(!TrialDialogModel.answersRevert(try trialKeyDown("\r", keyCode: 36, modifiers: .command)))
    }

    /// Ending a modal session ends the innermost one. One opened over the dialog would be
    /// ended in its place, leaving the dialog up with no revert, so the dialog waits until
    /// it is on top again.
    @Test func endsOnlyItsOwnModalSession() {
        let window = { NSWindow(contentRect: .zero, styleMask: .titled, backing: .buffered, defer: true) }
        let (dialog, other) = (window(), window())
        #expect(TrialDialogModel.shouldEnd(answered: true, modalWindow: dialog, dialogWindow: dialog))
        #expect(!TrialDialogModel.shouldEnd(answered: true, modalWindow: other, dialogWindow: dialog))
        #expect(!TrialDialogModel.shouldEnd(answered: false, modalWindow: dialog, dialogWindow: dialog))
    }

    // MARK: Placement

    @Test func findsTheScreenOfTheDisplayOrTheOneItMirrors() {
        let noMirror: (CGDirectDisplayID) -> CGDirectDisplayID = { _ in kCGNullDirectDisplay }
        #expect(TrialPlacement.index(of: 3, in: [1, 3], mirroring: noMirror) == 1)
        #expect(TrialPlacement.index(of: 4, in: [1, 3], mirroring: noMirror) == nil)
        #expect(TrialPlacement.index(of: 4, in: [1, 3], mirroring: { _ in 3 }) == 1)
        #expect(TrialPlacement.index(of: 4, in: [1, nil], mirroring: { $0 }) == nil)
    }

    @Test func centersOnTheScreenClearOfTheMenuBar() {
        let frame = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let visible = CGRect(x: 1512, y: 0, width: 2560, height: 1406)
        let size = CGSize(width: 300, height: 303)
        #expect(TrialPlacement.origin(centering: size, in: frame, within: visible) == CGPoint(x: 2642, y: 569))
        // A screen too short for the dialog keeps its top clear of the menu bar.
        let short = CGRect(x: 0, y: 0, width: 800, height: 300)
        #expect(TrialPlacement.origin(centering: size, in: short, within: CGRect(x: 0, y: 0, width: 800, height: 270)).y == 0)
    }
}

/// What the dialog, the notices and the quit confirmation say (Figma 28:5, 28:82, 28:132,
/// 29:68, 29:78).
@MainActor
@Suite struct TrialWordingTests {
    @Test func describesTheTrialAsFigmaDoes() {
        #expect(TrialWording.message(displayName: "DELL U2723QE", mode: "2880 × 1620", previousMode: "2560 × 1440", secondsLeft: 12)
            == "DELL U2723QE is trying 2880 × 1620, a mode macOS doesn’t list. It switches back to 2560 × 1440 in 12 seconds.")
        #expect(TrialWording.message(displayName: "DELL U2723QE", mode: "2880 × 1620", previousMode: nil, secondsLeft: 1)
            == "DELL U2723QE is trying 2880 × 1620, a mode macOS doesn’t list. It switches back in 1 second.")
    }

    @Test func namesWhoAsked() {
        #expect(TrialWording.requester(Requester(agent: "Claude Code", app: "Terminal"))
            == "Claude Code asked for this from Terminal. It can’t see your screen, so only you can keep it.")
        #expect(TrialWording.requester(Requester(agent: "Codex", app: nil))
            == "Codex asked for this. It can’t see your screen, so only you can keep it.")
        #expect(TrialWording.requester(Requester(agent: nil, app: "Ghostty"))
            == "The resolute command asked for this from Ghostty. It can’t see your screen, so only you can keep it.")
        #expect(TrialWording.requester(Requester())
            == "The resolute command asked for this. It can’t see your screen, so only you can keep it.")
    }

    /// The app's own trial shows the hint under the bar; a request shows who asked instead.
    @Test func showsTheHintOrWhoAsked() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(TrialDialogModel(question: trialQuestion(start: start), clock: { start }).requesterNote == nil)
        let asked = TrialDialogModel(question: trialQuestion(start: start, requester: Requester(agent: "Claude Code")), clock: { start })
        #expect(asked.requesterNote?.hasPrefix("Claude Code asked for this.") == true)
    }

    @Test func keepsSizesAndCountsOnOneLine() {
        #expect(TrialWording.keepingSizesTogether("back to 2560 × 1440 in 12 seconds.") == "back to 2560\u{A0}×\u{A0}1440 in 12\u{A0}seconds.")
    }

    @Test func notices() {
        let question = trialQuestion(start: Date())
        let back = TrialNotice.card(.switchedBack, question)
        #expect(back.title == "Switched back")
        #expect(back.subtitle == "DELL U2723QE · 2560 × 1440")
        #expect(back.symbol == .arrowUturnBackward)
        let kept = TrialNotice.card(.kept, question)
        #expect(kept.title == "Kept")
        #expect(kept.subtitle == "2880 × 1620 until you log out")
        #expect(kept.tone == .positive)
        #expect(TrialNotice.announcement(.kept, question) == "Kept. 2880 by 1620 until you log out.")
        #expect(TrialNotice.card(.switchedBack, trialQuestion(start: Date(), previousMode: nil)).subtitle == "DELL U2723QE")
    }

    @Test func announcesTheQuestionWithItsDefault() {
        let start = Date(timeIntervalSince1970: 0)
        let dialog = TrialDialogModel(question: trialQuestion(start: start), clock: { start })
        #expect(dialog.announcement == "Keep this display setting? DELL U2723QE is trying 2880 by 1620, a mode macOS doesn’t list. "
            + "It switches back to 2560 by 1440 in 15 seconds. Revert is the default button.")
    }

    @Test func quitWhileOneRevertWaits() {
        let one = [QuitWhileWaitingDialog.Waiting(displayName: "DELL U2723QE", trialMode: "2880 × 1620")]
        #expect(TrialWording.quitTitle(waiting: one) == "Quit Resolute while DELL U2723QE is waiting to switch back?")
        #expect(TrialWording.quitMessage(waiting: one) == "If you quit now, DELL U2723QE stays at 2880 × 1620 until you log out.")
    }

    @Test func quitWhileSeveralRevertsWait() {
        let two = [
            QuitWhileWaitingDialog.Waiting(displayName: "DELL U2723QE", trialMode: "2880 × 1620"),
            QuitWhileWaitingDialog.Waiting(displayName: "LG HDR 4K", trialMode: nil),
        ]
        #expect(TrialWording.quitTitle(waiting: two) == "Quit Resolute while 2 displays are waiting to switch back?")
        #expect(TrialWording.quitMessage(waiting: two)
            == "If you quit now, DELL U2723QE stays at 2880 × 1620 and LG HDR 4K stays in the mode it is trying until you log out.")
    }

    /// Keep Running is the default: Return and Esc choose it, and no key quits.
    @Test func quitKeysKeepRunning() throws {
        #expect(QuitWhileWaitingDialog.response(to: try trialKeyDown("\r", keyCode: 36)) == .keepRunning)
        #expect(QuitWhileWaitingDialog.response(to: try trialKeyDown("\u{1B}", keyCode: 53)) == .keepRunning)
        #expect(QuitWhileWaitingDialog.response(to: try trialKeyDown("q", keyCode: 12)) == nil)
    }
}
