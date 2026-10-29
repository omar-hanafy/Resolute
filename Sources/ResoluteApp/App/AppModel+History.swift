import CoreGraphics
import Foundation
import ResoluteKit

/// History in the app: every switch from the panel, the menus, the window, the Dock and
/// Shortcuts is recorded where `resolute` records its own, and any change can be undone.
extension AppModel {
    /// A trial whose revert waits for its display, as History will record it once the
    /// display is back.
    struct AwaitedTrial {
        var display: Display
        var mode: DisplayMode
        var source: HistoryEntry.Source
    }

    /// What History shows, worked out from `historyEntries`.
    var historyTimeline: HistoryTimeline {
        HistoryTimeline(entries: historyEntries)
    }

    /// The panel's activity row: the newest change from Terminal, an agent or Shortcuts that
    /// is still in place, with its Undo.
    func lastOutsideActivity(now: Date = Date()) -> HistoryActivity? {
        historyTimeline.lastOutsideActivity(now: now)
    }

    /// Records changes asked for from `source`. A history that can't be written is only
    /// logged: the change itself is done.
    func history(from source: HistoryEntry.Source) -> HistoryRecorder {
        HistoryRecorder(store: historyStore, source: source)
    }

    /// Records how switching `display` (as it was before) to `mode` ended.
    func record(
        _ result: Result<ModeSwitcher.Outcome, any Error>, switching display: Display, to mode: DisplayMode,
        from source: HistoryEntry.Source
    ) {
        let recorder = history(from: source)
        switch result {
        case .success(let outcome):
            if case .restorePending = outcome {
                recordWhenRevertEnds(switching: display, to: mode, from: source)
            } else {
                recorder.record(outcome, switching: display, to: mode, revertReason: trial.lastRevertReason)
            }
        case .failure(let error):
            recorder.record(error, switching: display, to: mode)
        }
        reloadHistory()
    }

    /// Records the trial of `mode` on `display` (as it was before) once its revert, which waits
    /// for the display, stops waiting, however that ends.
    func recordWhenRevertEnds(switching display: Display, to mode: DisplayMode, from source: HistoryEntry.Source) {
        trialsAwaitingRestore[display.id, default: []].append(AwaitedTrial(display: display, mode: mode, source: source))
    }

    /// The revert of a display that went dark during its trial stopped waiting: History says
    /// how each trial it undoes ended, as `resolute set` does.
    func trialWaitEnded(_ restore: ModeSwitcher.PendingRestore, _ ending: ModeChangeCoordinator.WaitEnding) {
        guard let awaited = trialsAwaitingRestore.removeValue(forKey: restore.displayID) else { return }
        let outcome: HistoryEntry.Outcome
        switch ending {
        case .displayIsBack, .replaced:
            outcome = .reverted(.displayWentDark)
        case .stopped:
            outcome = .failed(message: "You stopped waiting, so the previous mode was not put back.")
        case .gaveUp(let reason):
            outcome = .failed(message: reason.localizedDescription)
        }
        for trial in awaited {
            history(from: trial.source).recordSwitch(of: trial.display, to: trial.mode, outcome: outcome)
        }
        reloadHistory()
    }

    /// Resolute is quitting with reverts still waiting for their display, as Quit Anyway
    /// allows: History says those trials were not put back, as `resolute set` does when it
    /// stops waiting.
    func recordTrialsLeftWaiting() {
        for restore in modeChanges.pendingRestores {
            trialWaitEnded(restore, .gaveUp(QuitWhileWaiting()))
        }
    }

    /// Why an Undo that tries a hidden mode can't start while the dialog of a request from
    /// `resolute` is up.
    static let undoWaitsForAQuestion = "Resolute is asking about another display setting. Try again once it’s answered."

    /// Undo: puts back what `entry` replaced, asked for from `source`. A hidden mode is tried
    /// first, as any hidden mode is. Says why when it can't be undone.
    func undo(_ entry: HistoryEntry, from source: HistoryEntry.Source = .panel) {
        guard !modeChanges.isChangingMode else { return }
        reloadHistory()
        let plan = HistoryUndo.plan(for: entry, in: historyTimeline, displays: displays)
        let recorder = history(from: source)
        switch plan {
        case .switchMode(let display, let mode):
            switch switchMode(of: display, to: mode, needsConfirmation: plan.needsTrial) {
            case .success(.restorePending)?:
                recordWhenRevertEnds(switching: display, to: mode, from: source)
            case .success(let outcome)?:
                recorder.recordUndo(of: entry, plan: plan, outcome: outcome, revertReason: trial.lastRevertReason)
            case .failure(let error)?:
                recorder.recordFailedUndo(of: entry, plan: plan, error: error)
            case nil:
                // A request from `resolute` is being asked about, and its dialog holds trials.
                showError(UndoUnavailable(reason: Self.undoWaitsForAQuestion), "The change could not be undone")
                return
            }
        case .setMirroring(let isOn):
            do {
                try service.setMirroring(isOn)
                recorder.recordUndo(of: entry, plan: plan)
            } catch {
                recorder.recordFailedUndo(of: entry, plan: plan, error: error)
                showError(error, "The change could not be undone")
            }
        case .alreadyCurrent:
            recorder.recordUndo(of: entry, plan: plan)
        case .unavailable(let reason):
            showError(UndoUnavailable(reason: reason), "The change can’t be undone")
        }
        refresh()
    }
}

/// Why a trial's revert never happened: Resolute quit while it waited.
struct QuitWhileWaiting: LocalizedError {
    var errorDescription: String? { "Resolute quit before it could put the previous mode back." }
}

/// Why Undo can't put a change back, as History's plan words it.
struct UndoUnavailable: LocalizedError {
    var reason: String

    var errorDescription: String? { reason }
}
