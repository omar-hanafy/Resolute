import Foundation
import Observation
import ResoluteKit

/// Asks whether to keep a mode on trial, and publishes the question while it is up, so the
/// menu bar icon can turn orange and count down with it.
///
/// `ModeChangeCoordinator` calls `decide()` once the mode on trial shows; the app model hands
/// it over as the coordinator's `decide`, after naming the display and mode in `subject`.
/// `ask` shows the question on the display on trial and returns true only for Keep before
/// the countdown ends.
@MainActor
@Observable
final class TrialPrompt {
    /// What the next trial is about: the display as it was before the switch, and the mode
    /// it tries. Set by the app model just before it switches.
    struct Subject {
        var display: Display
        var mode: DisplayMode
    }

    /// The question being asked; nil while no mode is on trial.
    private(set) var question: TrialQuestion?
    /// The countdown of the question being asked; nil while no mode is on trial.
    var countdown: RevertCountdown? { question?.countdown }
    /// The last question asked, for the notice that says how it ended.
    @ObservationIgnored private(set) var lastQuestion: TrialQuestion?
    /// Why the last trial was reverted, for History: the person chose Revert, or nobody
    /// answered before the countdown ended.
    @ObservationIgnored private(set) var lastRevertReason: HistoryEntry.RevertReason = .unspecified
    @ObservationIgnored var subject: Subject?

    private let length: @MainActor () -> TimeInterval
    private let ask: @MainActor (TrialQuestion) -> Bool

    /// `length` is read at each trial, so a change in Settings applies to the next one.
    init(
        length: @escaping @MainActor () -> TimeInterval,
        ask: @escaping @MainActor (TrialQuestion) -> Bool = { TrialDialog.ask($0) }
    ) {
        self.length = length
        self.ask = ask
    }

    /// A kept mode lasts until logout, as the design's Kept notice says: a hidden mode is
    /// never saved for good.
    func decide() -> ModeSwitcher.Decision {
        let countdown = RevertCountdown(duration: length())
        let question = subject.map { TrialQuestion(display: $0.display, mode: $0.mode, countdown: countdown) }
            ?? TrialQuestion(displayID: 0, displayName: "The display", mode: "the new mode", previousMode: nil, countdown: countdown)
        self.question = question
        lastQuestion = question
        defer { self.question = nil }
        guard ask(question) else {
            lastRevertReason = countdown.isExpired(at: Date()) ? .noAnswer : .declined
            return .revert
        }
        return .keepForSession
    }

    /// Whole seconds left in the question being asked, or nil while none is.
    func secondsLeft(at date: Date = Date()) -> Int? {
        countdown?.secondsRemaining(at: date)
    }
}
