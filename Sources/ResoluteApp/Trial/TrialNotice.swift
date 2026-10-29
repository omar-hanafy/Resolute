import AppKit
import ResoluteDesign
import SwiftUI

/// The two-second notice on the display a trial was on, saying how it ended (Figma:
/// Switched back 29:68, Kept 29:78). It takes no clicks or keys and VoiceOver announces it.
@MainActor
enum TrialNotice {
    /// How long a notice stays before it fades.
    static let duration: TimeInterval = 2
    private static var current: NoticeWindow?

    /// Shows the notice, replacing one still up. For `AppEnvironment.live`'s
    /// `showTrialOutcome`.
    static func show(_ outcome: TrialOutcome, _ question: TrialQuestion) {
        current?.close()
        let window = NoticeWindow(card: card(outcome, question), displayID: question.displayID)
        current = window
        window.show(for: duration) {
            if current === window { current = nil }
        }
        NSAccessibility.post(
            element: window.panel, notification: .announcementRequested,
            userInfo: [.announcement: announcement(outcome, question), .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    static func card(_ outcome: TrialOutcome, _ question: TrialQuestion) -> HUDCard {
        let subtitle = TrialWording.noticeSubtitle(
            outcome, displayName: question.displayName, mode: question.mode, previousMode: question.previousMode
        )
        return switch outcome {
        case .switchedBack: HUDCard(TrialWording.noticeTitle(outcome), subtitle: subtitle, symbol: .arrowUturnBackward)
        case .kept: HUDCard(TrialWording.noticeTitle(outcome), subtitle: subtitle, symbol: .checkmarkCircleFill, tone: .positive)
        }
    }

    /// "Switched back. DELL U2723QE, 2560 by 1440."
    static func announcement(_ outcome: TrialOutcome, _ question: TrialQuestion) -> String {
        let card = card(outcome, question)
        return "\(card.title). \(SpokenText.sizes(card.subtitle))."
    }
}

/// One notice on screen: it fades in, stays, and fades out.
@MainActor
private final class NoticeWindow {
    let panel: GlassAlertPanel
    private var timer: Timer?

    init(card: HUDCard, displayID: CGDirectDisplayID) {
        panel = GlassAlertPanel(content: card, title: card.title, takesKeyboard: false)
        panel.center(onDisplay: displayID)
    }

    func show(for duration: TimeInterval, closed: @escaping @MainActor () -> Void) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        // In every common mode, so the notice also goes while a modal alert is up.
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; self.panel.animator().alphaValue = 0 }) {
                    MainActor.assumeIsolated {
                        self.close()
                        closed()
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }
}
