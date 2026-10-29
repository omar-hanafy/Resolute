import AppKit
import Observation
import ResoluteDesign
import ResoluteKit

/// One Keep/Revert question while it is up: the countdown, the words, and the answer, which
/// is given once. The dialog's window drives it (its timer calls `tick()`, its buttons
/// `keep()` and `revert()`); tests drive it the same way with a clock of their own.
@MainActor
@Observable
final class TrialDialogModel {
    /// How the question ended.
    enum Answer: Equatable, Sendable {
        /// A person chose Keep before the countdown ended.
        case kept
        /// A person chose Revert, or pressed Return or Esc.
        case reverted
        /// The countdown ended first. A Keep at or after the deadline counts as this.
        case noAnswer
        /// The question was withdrawn: the command that asked stopped waiting or went away.
        case dismissed

        /// Whether a person answered, so a notice may say how it ended.
        var isPersons: Bool { self == .kept || self == .reverted }
    }

    let question: TrialQuestion
    /// The length of the whole countdown, for the bar.
    let total: TimeInterval
    /// The time the dialog shows, as of the last tick.
    private(set) var now: Date
    private(set) var answer: Answer?
    /// Told once, when the question ends.
    @ObservationIgnored var onAnswer: (@MainActor (Answer) -> Void)?
    @ObservationIgnored private let clock: @MainActor () -> Date

    /// `total` defaults to the time left when the dialog opens, in whole seconds: the
    /// question is asked as soon as it is made, so that is the trial's length.
    init(question: TrialQuestion, total: TimeInterval? = nil, clock: @escaping @MainActor () -> Date = TrialClock.monotonic()) {
        let now = clock()
        self.question = question
        self.clock = clock
        self.now = now
        self.total = total ?? max(0, question.countdown.deadline.timeIntervalSince(now).rounded(.up))
    }

    var isExpired: Bool { question.countdown.isExpired(at: now) }
    var remaining: TimeInterval { max(0, question.countdown.deadline.timeIntervalSince(now)) }
    var secondsLeft: Int { question.countdown.secondsRemaining(at: now) }

    var message: String {
        TrialWording.message(
            displayName: question.displayName, mode: question.mode, previousMode: question.previousMode, secondsLeft: secondsLeft
        )
    }

    /// Who asked, for a request from `resolute`; nil for the app's own trial.
    var requesterNote: String? { question.requester.map(TrialWording.requester) }

    /// What VoiceOver says when the dialog opens.
    var announcement: String {
        "\(TrialWording.title) \(SpokenText.sizes(message)) Revert is the default button."
    }

    /// Moves the countdown on; at the deadline nobody answered.
    func tick() {
        now = clock()
        if isExpired { finish(.noAnswer) }
    }

    /// Keep counts only before the deadline: a click can arrive after it but before the
    /// next tick.
    func keep() {
        now = clock()
        finish(isExpired ? .noAnswer : .kept)
    }

    func revert() {
        finish(.reverted)
    }

    func dismiss() {
        finish(.dismissed)
    }

    private func finish(_ answer: Answer) {
        guard self.answer == nil else { return }
        self.answer = answer
        onAnswer?(answer)
    }

    // MARK: Rules for the window

    /// Whether `event` answers Revert: Return, Enter and Esc, with no modifier but Fn. No
    /// key chooses Keep, so a person who can't read the screen can only go back.
    static func answersRevert(_ event: NSEvent) -> Bool {
        let returnKey: UInt16 = 36, enter: UInt16 = 76, escape: UInt16 = 53
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return event.type == .keyDown && modifiers.isEmpty && [returnKey, enter, escape].contains(event.keyCode)
    }

    /// Whether the dialog's modal session may end now. Ending a modal session ends the
    /// innermost one, so while another alert is over the dialog it waits for that one to
    /// close rather than end it in the dialog's place.
    static func shouldEnd(answered: Bool, modalWindow: NSWindow?, dialogWindow: NSWindow) -> Bool {
        answered && modalWindow === dialogWindow
    }
}

/// Clocks for the countdown.
enum TrialClock {
    /// Today's date moved on by a monotonic clock from now: a wall-clock correction must not
    /// lengthen a trial of a mode that may be unreadable. Dates keep the countdown's terms.
    static func monotonic() -> @MainActor () -> Date {
        let started = ContinuousClock.now
        let initialDate = Date()
        return {
            let elapsed = started.duration(to: .now).components
            return initialDate.addingTimeInterval(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        }
    }
}
