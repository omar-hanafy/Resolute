import ResoluteDesign
import ResoluteKit

/// The words of the Keep/Revert dialog (Figma 28:5, 28:82), the notices after it (29:68,
/// 29:78) and the quit confirmation while a revert waits (28:132), built from what they are
/// about. Kept apart from the windows so tests can read them.
enum TrialWording {
    static let title = "Keep this display setting?"
    static let keep = "Keep"
    static let revert = "Revert"
    /// Under the countdown of the app's own trial: the safe choice works blind.
    static let blackScreenHint = "If the screen stays black, wait or press Return."

    /// "DELL U2723QE is trying 2880 × 1620, a mode macOS doesn’t list. It switches back to
    /// 2560 × 1440 in 12 seconds."
    static func message(displayName: String, mode: String, previousMode: String?, secondsLeft: Int) -> String {
        let back = previousMode.map { "switches back to \($0)" } ?? "switches back"
        return "\(displayName) is trying \(mode), a mode macOS doesn’t list. It \(back) in \(seconds(secondsLeft))."
    }

    /// "Claude Code asked for this from Terminal. It can’t see your screen, so only you can
    /// keep it." A command a person typed names the command; an unknown app is left out.
    static func requester(_ requester: Requester) -> String {
        let who = requester.agent ?? "The resolute command"
        let from = requester.app.map { " from \($0)" } ?? ""
        return "\(who) asked for this\(from). It can’t see your screen, so only you can keep it."
    }

    static func keepHint(mode: String) -> String {
        "Keeps \(SpokenText.sizes(mode)) until you log out"
    }

    static func revertHint(previousMode: String?) -> String {
        previousMode.map { "Switches back to \(SpokenText.sizes($0)) now" } ?? "Switches back to the previous mode now"
    }

    /// `text` with each size and count held on one line: "2560 × 1440" is never broken at
    /// the "×", nor "12 seconds" after the number, as Figma lays the descriptions out.
    static func keepingSizesTogether(_ text: String) -> String {
        text.replacingOccurrences(of: " × ", with: "\u{00A0}×\u{00A0}")
            .replacing(#/(\d) (seconds?)/#) { "\($0.output.1)\u{00A0}\($0.output.2)" }
    }

    static func seconds(_ count: Int) -> String {
        count == 1 ? "1 second" : "\(count) seconds"
    }

    // MARK: Notices

    static func noticeTitle(_ outcome: TrialOutcome) -> String {
        switch outcome {
        case .switchedBack: "Switched back"
        case .kept: "Kept"
        }
    }

    /// "DELL U2723QE · 2560 × 1440" after a revert, "2880 × 1620 until you log out" after a keep.
    static func noticeSubtitle(_ outcome: TrialOutcome, displayName: String, mode: String, previousMode: String?) -> String {
        switch outcome {
        case .switchedBack: previousMode.map { "\(displayName) · \($0)" } ?? displayName
        case .kept: "\(mode) until you log out"
        }
    }

    // MARK: Quitting while a revert waits

    static let quitAnyway = "Quit Anyway"
    static let keepRunning = "Keep Running"

    /// "Quit Resolute while DELL U2723QE is waiting to switch back?"
    static func quitTitle(waiting: [QuitWhileWaitingDialog.Waiting]) -> String {
        switch waiting.count {
        case 0: "Quit Resolute while a display is waiting to switch back?"
        case 1: "Quit Resolute while \(waiting[0].displayName) is waiting to switch back?"
        default: "Quit Resolute while \(waiting.count) displays are waiting to switch back?"
        }
    }

    /// "If you quit now, DELL U2723QE stays at 2880 × 1620 until you log out."
    static func quitMessage(waiting: [QuitWhileWaitingDialog.Waiting]) -> String {
        guard !waiting.isEmpty else {
            return "If you quit now, the display stays in the mode it is trying until you log out."
        }
        let clauses = waiting.map { display in
            display.trialMode.map { "\(display.displayName) stays at \($0)" }
                ?? "\(display.displayName) stays in the mode it is trying"
        }
        return "If you quit now, \(list(clauses)) until you log out."
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}
