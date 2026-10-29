import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// The Keep/Revert dialog on the display being tried (Figma: Hidden-mode trial › Dialog
/// 28:5, and 28:82 for a request from `resolute`).
///
/// `ask` is the app's own trial: `ModeChangeCoordinator` decides while the mode on trial
/// shows, synchronously, so the dialog runs a modal session. `present` shows it without one,
/// for a request from `resolute`, which is answered asynchronously.
@MainActor
enum TrialDialog {
    /// Asks on the display on trial whether to keep its mode: true only for Keep before the
    /// countdown ends. Return and Esc revert; the countdown reverts on its own. For
    /// `AppEnvironment.live`'s `askToKeep`.
    static func ask(_ question: TrialQuestion) -> Bool {
        let window = TrialDialogWindow(model: TrialDialogModel(question: question))
        return withExtendedLifetime(window) { window.runModal() == .kept }
    }

    /// Shows `model`'s question without a modal session and returns what closes it. The
    /// window ticks the countdown, so the model answers `.noAnswer` on time, and closes
    /// itself after an answer it takes (a click, a key, the countdown); call the returned
    /// closure after `dismiss()` or any answer given elsewhere.
    static func present(_ model: TrialDialogModel) -> @MainActor () -> Void {
        let window = TrialDialogWindow(model: model)
        window.show(modal: false)
        return { window.close() }
    }
}

/// The dialog's content: the question, the countdown with the hint or who asked, Keep and
/// Revert.
struct TrialDialogView: View {
    let model: TrialDialogModel
    var keep: () -> Void = {}
    var revert: () -> Void = {}

    var body: some View {
        GlassAlert(
            title: TrialWording.title,
            message: TrialWording.keepingSizesTogether(model.message),
            secondary: .init(TrialWording.keep, hint: TrialWording.keepHint(mode: model.question.mode), perform: keep),
            primary: .init(TrialWording.revert, hint: TrialWording.revertHint(previousMode: model.question.previousMode), perform: revert)
        ) {
            VStack(alignment: .leading, spacing: Metrics.Trial.countdownSpacing) {
                CountdownBar(remaining: model.remaining, total: model.total)
                if let note = model.requesterNote {
                    GlassAlertNote(note, symbol: .terminal)
                } else {
                    Text(TrialWording.blackScreenHint)
                        .textBox(.footnote)
                        .foregroundStyle(Palette.labelSecondary)
                }
            }
        }
    }
}

/// The dialog's window: places it on the display on trial, ticks the countdown smoothly,
/// takes the keyboard, and ends with the model's answer.
@MainActor
final class TrialDialogWindow {
    /// How often the countdown moves: smooth enough for the bar.
    static let tickInterval: TimeInterval = 1.0 / 30

    let model: TrialDialogModel
    let panel: GlassAlertPanel
    private var timer: Timer?
    private var isModal = false

    init(model: TrialDialogModel) {
        self.model = model
        // The view's buttons reach the model through the window, which is made next.
        let actions = Actions()
        panel = GlassAlertPanel(
            content: TrialDialogView(model: model, keep: { actions.keep?() }, revert: { actions.revert?() }),
            title: TrialWording.title
        )
        actions.keep = { [weak self] in self?.answer { $0.keep() } }
        actions.revert = { [weak self] in self?.answer { $0.revert() } }
        panel.onKey = { [weak self] event in
            guard TrialDialogModel.answersRevert(event) else { return false }
            self?.answer { $0.revert() }
            return true
        }
    }

    /// Runs the dialog in a modal session until it has an answer.
    func runModal() -> TrialDialogModel.Answer {
        show(modal: true)
        NSApp.runModal(for: panel)
        close()
        return model.answer ?? .noAnswer
    }

    func show(modal: Bool) {
        isModal = modal
        // Clickable while another app-modal alert is up; the modal session itself doesn't need it.
        panel.worksWhenModal = !modal
        panel.center(onDisplay: model.question.displayID)
        // Runs on the main run loop, in every common mode, the modal panel's included. It
        // holds the window until `close()`, so a dialog shown without a modal session stays
        // up and counts down even when nobody else keeps the window.
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAccessibility.post(
            element: panel, notification: .announcementRequested,
            userInfo: [.announcement: model.announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel.orderOut(nil)
    }

    private func tick() {
        model.tick()
        endIfAnswered()
    }

    private func answer(_ choose: (TrialDialogModel) -> Void) {
        choose(model)
        endIfAnswered()
    }

    /// Closes the dialog once answered. A modal session ends unless another alert is over
    /// the dialog: then the next tick tries again.
    private func endIfAnswered() {
        guard model.answer != nil else { return }
        guard isModal else {
            close()
            return
        }
        guard TrialDialogModel.shouldEnd(
            answered: model.answer != nil, modalWindow: NSApp.modalWindow, dialogWindow: panel
        ) else { return }
        isModal = false
        GlassAlertPanel.stopModal()
    }

    /// The buttons' actions, set once the window exists.
    private final class Actions {
        var keep: (() -> Void)?
        var revert: (() -> Void)?
    }
}
