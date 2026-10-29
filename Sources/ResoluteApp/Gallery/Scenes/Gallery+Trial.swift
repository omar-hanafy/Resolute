import Foundation
import ResoluteDesign
import ResoluteKit
import SwiftUI

extension AppGallery {
    /// Scenes owned by the hidden-mode trial dialog and HUDs owner: the Keep/Revert dialog at
    /// points of its countdown, a request from `resolute`, the notices after a trial and the
    /// quit confirmation while a revert waits. Each sits on the wallpaper, as Figma's crops do.
    static var trialScenes: [GalleryScene] {
        let dialogSize = CGSize(width: 620, height: 520)
        let noticeSize = CGSize(width: 620, height: 400)
        return [
            GalleryScene(id: "trial.dialog", title: "Keep or revert, 12 of 15 seconds left", figmaNode: "28:5", size: dialogSize, backdrop: .wallpaper) {
                TrialGallery.dialog(secondsLeft: 12, of: 15)
            },
            GalleryScene(id: "trial.dialog.start", title: "Keep or revert, as it opens", figmaNode: "28:5", size: dialogSize, backdrop: .wallpaper) {
                TrialGallery.dialog(secondsLeft: 15, of: 15)
            },
            GalleryScene(id: "trial.dialog.last-second", title: "Keep or revert, 1 second left", figmaNode: "28:5", size: dialogSize, backdrop: .wallpaper) {
                TrialGallery.dialog(secondsLeft: 0.6, of: 15)
            },
            GalleryScene(id: "trial.agent", title: "Request from an agent, 8 of 16 seconds left", figmaNode: "28:82", size: dialogSize, backdrop: .wallpaper) {
                TrialGallery.dialog(secondsLeft: 8, of: 16, requester: Requester(agent: "Claude Code", app: "Terminal"))
            },
            GalleryScene(id: "trial.agent.typed", title: "Request typed in a terminal, previous mode unknown", figmaNode: "28:82", size: dialogSize, backdrop: .wallpaper) {
                TrialGallery.dialog(secondsLeft: 30, of: 30, requester: Requester(agent: nil, app: "Ghostty"), previousMode: nil)
            },
            GalleryScene(id: "trial.notice.switched-back", title: "Switched back", figmaNode: "29:68", size: noticeSize, backdrop: .wallpaper) {
                TrialNotice.card(.switchedBack, TrialGallery.question(secondsLeft: 0, of: 15)).glassBlending(.withinWindow)
            },
            GalleryScene(id: "trial.notice.kept", title: "Kept until you log out", figmaNode: "29:78", size: noticeSize, backdrop: .wallpaper) {
                TrialNotice.card(.kept, TrialGallery.question(secondsLeft: 0, of: 15)).glassBlending(.withinWindow)
            },
            GalleryScene(id: "trial.quit", title: "Quit while a revert is waiting", figmaNode: "28:132", size: dialogSize, backdrop: .wallpaper) {
                QuitWhileWaitingView(waiting: [.init(displayName: "DELL U2723QE", trialMode: "2880 × 1620")])
                    .glassBlending(.withinWindow)
            },
            GalleryScene(id: "trial.quit.several", title: "Quit while two reverts are waiting", figmaNode: "28:132", size: dialogSize, backdrop: .wallpaper) {
                QuitWhileWaitingView(waiting: [
                    .init(displayName: "DELL U2723QE", trialMode: "2880 × 1620"),
                    .init(displayName: "LG HDR 4K", trialMode: nil),
                ])
                .glassBlending(.withinWindow)
            },
        ]
    }
}

/// The trial scenes' sample question: Figma's DELL U2723QE trying 2880 × 1620.
@MainActor
private enum TrialGallery {
    static let start = Date(timeIntervalSinceReferenceDate: 0)

    static func question(secondsLeft: TimeInterval, of total: TimeInterval, requester: Requester? = nil, previousMode: String? = "2560 × 1440") -> TrialQuestion {
        TrialQuestion(
            displayID: 3, displayName: "DELL U2723QE", mode: "2880 × 1620", previousMode: previousMode,
            countdown: RevertCountdown(start: start, duration: total), requester: requester
        )
    }

    /// The dialog frozen with `secondsLeft` of `total` left.
    static func dialog(
        secondsLeft: TimeInterval, of total: TimeInterval, requester: Requester? = nil, previousMode: String? = "2560 × 1440"
    ) -> some View {
        let question = question(secondsLeft: secondsLeft, of: total, requester: requester, previousMode: previousMode)
        let now = start.addingTimeInterval(total - secondsLeft)
        return TrialDialogView(model: TrialDialogModel(question: question, total: total, clock: { now }))
            .glassBlending(.withinWindow)
    }
}
