import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// "Quit Resolute while DELL U2723QE is waiting to switch back?" (Figma 28:132): asked before
/// quitting while a revert waits for its display, since quitting gives the revert up. Keep
/// Running is the default; Return and Esc choose it.
@MainActor
enum QuitWhileWaitingDialog {
    /// A display whose revert waits, as the dialog names it.
    struct Waiting: Equatable {
        var displayName: String
        /// The mode it stays in if Resolute quits; nil when it is not known.
        var trialMode: String?
    }

    enum Choice: Equatable {
        case quitAnyway
        case keepRunning
    }

    /// Asks in a modal session on the main screen; true for Quit Anyway. For
    /// `ShellController.confirm(.pendingRestores)`.
    static func confirm(model: AppModel) -> Bool {
        ask(waiting(in: model)) == .quitAnyway
    }

    static func ask(_ waiting: [Waiting]) -> Choice {
        var choice: Choice?
        func choose(_ answer: Choice) {
            guard choice == nil else { return }
            choice = answer
            GlassAlertPanel.stopModal()
        }
        let panel = GlassAlertPanel(
            content: QuitWhileWaitingView(
                waiting: waiting,
                quitAnyway: { choose(.quitAnyway) },
                keepRunning: { choose(.keepRunning) }
            ),
            title: TrialWording.quitTitle(waiting: waiting)
        )
        panel.onKey = { event in
            guard let answer = response(to: event) else { return false }
            choose(answer)
            return true
        }
        panel.center(onDisplay: nil)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAccessibility.post(
            element: panel, notification: .announcementRequested,
            userInfo: [.announcement: announcement(waiting), .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return choice ?? .keepRunning
    }

    /// The displays whose revert waits, with the mode each stays in.
    static func waiting(in model: AppModel) -> [Waiting] {
        model.pendingRestores.map { restore in
            let trialMode = model.trialsAwaitingRestore[restore.displayID]?.last?.mode.sizeText
                ?? model.displays.first { $0.id == restore.displayID }?
                    .modes.first { $0.modeID == restore.trialModeID }?.sizeText
            return Waiting(displayName: restore.displayName, trialMode: trialMode)
        }
    }

    /// Return and Esc keep Resolute running; no key quits.
    static func response(to event: NSEvent) -> Choice? {
        TrialDialogModel.answersRevert(event) ? .keepRunning : nil
    }

    static func announcement(_ waiting: [Waiting]) -> String {
        let text = "\(TrialWording.quitTitle(waiting: waiting)) \(TrialWording.quitMessage(waiting: waiting))"
        return "\(SpokenText.sizes(text)) Keep Running is the default button."
    }
}

/// The quit confirmation's content.
struct QuitWhileWaitingView: View {
    let waiting: [QuitWhileWaitingDialog.Waiting]
    var quitAnyway: () -> Void = {}
    var keepRunning: () -> Void = {}

    var body: some View {
        GlassAlert(
            title: TrialWording.quitTitle(waiting: waiting),
            message: TrialWording.keepingSizesTogether(TrialWording.quitMessage(waiting: waiting)),
            secondary: .init(TrialWording.quitAnyway, hint: "Quits Resolute and stops waiting to switch back", perform: quitAnyway),
            primary: .init(TrialWording.keepRunning, hint: "Keeps Resolute running so it can switch back", perform: keepRunning)
        )
    }
}
