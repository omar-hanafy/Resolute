import AppKit
import ResoluteKit

/// The Keep/Revert question for callers that know only the countdown: the coordinator's and
/// `TrialPrompt`'s default `decide`. It shows `TrialDialog` on the main display, naming no
/// display or mode; the app model asks through `TrialDialog.ask` with the whole question.
@MainActor
enum ConfirmationPanel {
    /// Returns true only when the person chooses Keep before the countdown ends.
    static func keepNewMode(countdown: RevertCountdown) -> Bool {
        TrialDialog.ask(TrialQuestion(
            displayID: CGMainDisplayID(), displayName: "The display", mode: "the new mode", previousMode: nil,
            countdown: countdown
        ))
    }
}
