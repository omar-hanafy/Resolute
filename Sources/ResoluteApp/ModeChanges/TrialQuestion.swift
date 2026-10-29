import CoreGraphics
import ResoluteKit

/// What the Keep/Revert dialog asks about (Figma: Hidden-mode trial › Dialog, 28:5): the
/// display on trial, the mode tried, the mode that comes back unless the person keeps it,
/// and the countdown. A request from `resolute` also names who asked (28:82).
struct TrialQuestion: Equatable {
    var displayID: CGDirectDisplayID
    var displayName: String
    /// "2880 × 1620", with its refresh rate or scale when that tells it from the previous mode.
    var mode: String
    /// The mode that comes back; nil when it is not known.
    var previousMode: String?
    var countdown: RevertCountdown
    /// Who asked, for a request from `resolute`; nil when the person chose the mode here.
    var requester: Requester?

    /// The question for trying `mode` on `display`, as it was before the switch.
    init(display: Display, mode: DisplayMode, countdown: RevertCountdown) {
        let previous = display.currentMode
        self.init(
            displayID: display.id, displayName: display.name,
            mode: ConfirmHiddenModeRequest.describe(mode, distinctFrom: previous),
            previousMode: previous.map { ConfirmHiddenModeRequest.describe($0, distinctFrom: mode) },
            countdown: countdown
        )
    }

    init(
        displayID: CGDirectDisplayID, displayName: String, mode: String, previousMode: String?, countdown: RevertCountdown,
        requester: Requester? = nil
    ) {
        self.displayID = displayID
        self.displayName = displayName
        self.mode = mode
        self.previousMode = previousMode
        self.countdown = countdown
        self.requester = requester
    }
}

/// How a trial ended, as the notice on its display says for two seconds (Figma: Switched
/// back 29:68, Kept 29:78).
enum TrialOutcome: Equatable, Sendable {
    case switchedBack
    case kept
}
