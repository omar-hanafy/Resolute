import AppKit
import ResoluteDesign

/// What the menu bar icon shows (Figma: Status Item 17:135, its states 25:2439).
enum StatusItemState: Equatable, Sendable {
    /// Resting: the display symbol alone.
    case normal
    /// The panel is showing. The icon is drawn as at rest and highlighted like an open menu.
    case open
    /// A hidden mode is on trial: orange, counting down on every display's menu bar.
    case trial(secondsLeft: Int)
    /// The main display's resolution next to the icon, when Settings › General asks for it.
    case resolution(String)
    /// A revert is waiting for its display to come back.
    case waiting

    /// The state for what is going on, most urgent first: a trial's countdown, then a revert
    /// waiting for its display. The resolution, when shown, stays while the panel is open:
    /// the panel hangs under the icon, which must not change width under it.
    static func resolve(
        trialSecondsLeft: Int?, isWaiting: Bool, isPanelOpen: Bool, resolutionText: String?
    ) -> StatusItemState {
        if let trialSecondsLeft { return .trial(secondsLeft: max(0, trialSecondsLeft)) }
        if isWaiting { return .waiting }
        if let resolutionText { return .resolution(resolutionText) }
        return isPanelOpen ? .open : .normal
    }

    /// "0:12": the time left in a trial, as the icon shows it.
    static func countdownText(secondsLeft: Int) -> String {
        let seconds = max(0, secondsLeft)
        return "\(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)"
    }

    /// What VoiceOver reads for the icon. Sizes say "by": "×" is read as "multiplied by".
    var accessibilityLabel: String {
        switch self {
        case .normal, .open:
            "Resolute"
        case .trial(let secondsLeft):
            "Resolute, hidden mode on trial, \(secondsLeft) second\(secondsLeft == 1 ? "" : "s") left"
        case .resolution(let text):
            "Resolute, \(text.replacingOccurrences(of: " × ", with: " by "))"
        case .waiting:
            "Resolute, a revert is waiting for its display"
        }
    }

    /// The icon's tooltip.
    var toolTip: String {
        switch self {
        case .normal, .open, .resolution:
            "Resolute"
        case .trial(let secondsLeft):
            "Hidden mode on trial, \(secondsLeft) s left"
        case .waiting:
            "A revert is waiting for its display"
        }
    }
}

extension StatusItemState {
    /// The design system's drawing of this state, `height` points tall. The open panel is
    /// drawn as at rest, since macOS highlights the button.
    func image(height: CGFloat = Metrics.MenuBar.statusItemHeight) -> StatusItemImage {
        switch self {
        case .normal, .open: StatusItemImage(.symbol, height: height)
        case .trial(let secondsLeft): StatusItemImage(.trial(secondsLeft: secondsLeft), height: height)
        case .resolution(let text): StatusItemImage(.resolution(text), height: height)
        case .waiting: StatusItemImage(.waiting, height: height)
        }
    }
}
