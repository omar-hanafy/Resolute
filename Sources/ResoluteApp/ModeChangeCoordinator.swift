import AppKit
import os
import ResoluteKit

/// Applies mode changes chosen in the menu. Hidden modes are tried for the session first
/// and only kept when the person confirms, so a mode the display cannot show reverts.
///
/// A display that cannot show a mode may lose its link during the countdown. Its revert
/// then waits for the display to come back, which `displaysDidChange()` hears about.
/// A connected display that refuses its previous mode is retried too, without holding
/// the main thread or showing repeated alerts during recovery. After
/// `restoreTimeout` the revert gets one last try and is given up; the mode lasts at most
/// until logout.
@MainActor
final class ModeChangeCoordinator {
    /// A revert waiting for its display, and when to stop waiting.
    private struct Waiting {
        var restore: ModeSwitcher.PendingRestore
        var deadline: ContinuousClock.Instant
        /// Whether putting the mode back has failed yet; only the first failure is logged.
        var hasFailed = false
    }

    private let service: any DisplayControlling
    private let decide: @MainActor () -> ModeSwitcher.Decision
    private let report: @MainActor (any Error) -> Void
    private let now: @MainActor () -> ContinuousClock.Instant
    private let restoreTimeout: Duration
    private let retryInterval: Duration
    private var waiting: [CGDirectDisplayID: Waiting] = [:]
    /// Switches under way. During one the Keep/Revert countdown may be up, and an alert
    /// over it would hold up its revert until closed, so no other alert may open: screen
    /// changes are taken up once the switch is over.
    private var switchesUnderWay = 0
    private var hasMissedChanges = false
    /// Displays whose refused revert is due another try.
    private var retrying: Set<CGDirectDisplayID> = []

    /// `decide` shows the Keep/Revert countdown and `report` an alert; tests pass their own,
    /// with their own clock.
    init(
        service: any DisplayControlling,
        decide: @escaping @MainActor () -> ModeSwitcher.Decision = {
            ConfirmationPanel.keepNewMode(countdown: RevertCountdown()) ? .keep : .revert
        },
        report: @escaping @MainActor (any Error) -> Void = {
            Alerts.show($0, title: "The display mode could not be changed")
        },
        now: @escaping @MainActor () -> ContinuousClock.Instant = { .now },
        restoreTimeout: Duration = .seconds(120),
        retryInterval: Duration = .seconds(1)
    ) {
        self.service = service
        self.decide = decide
        self.report = report
        self.now = now
        self.restoreTimeout = restoreTimeout
        self.retryInterval = retryInterval
    }

    /// No other menu action or termination may interrupt a mode trial.
    var isChangingMode: Bool { switchesUnderWay > 0 }

    /// Reverts waiting for their display to reconnect or accept its previous mode.
    var pendingRestores: [ModeSwitcher.PendingRestore] {
        waiting.values.map(\.restore).sorted { $0.displayID < $1.displayID }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, needsConfirmation: Bool) {
        // A switch chosen while the countdown is up could put its own alert or countdown
        // over it, holding up the revert until that one is closed.
        guard switchesUnderWay == 0 else {
            ResoluteLog.modes.notice("Ignored mode \(modeID) for display \(displayID), chosen while a countdown was up")
            return
        }
        // A revert still waiting for this display goes first, so the new switch starts from
        // the mode the person had rather than from the one on trial.
        if waiting[displayID] != nil { attempt(displayID) }
        switchesUnderWay += 1
        let result = Result {
            try ModeSwitcher(service: service).apply(modeID: modeID, to: displayID, trial: needsConfirmation) {
                decide()
            }
        }
        switchesUnderWay -= 1
        switch result {
        case .success(let outcome):
            settle(outcome, of: displayID)
        case .failure(let error):
            report(error)
        }
        if switchesUnderWay == 0, hasMissedChanges {
            hasMissedChanges = false
            displaysDidChange()
        }
    }

    /// Updates the revert still waiting for `displayID`, if any, after a new switch of it.
    private func settle(_ outcome: ModeSwitcher.Outcome, of displayID: CGDirectDisplayID) {
        let earlier = waiting.removeValue(forKey: displayID)
        switch outcome {
        case .reverted, .leftAlone, .alreadyCurrent:
            // Undoing the new trial took the display back to where it was, which can be the
            // earlier trial a refusing display is still in, so that revert keeps waiting. So
            // does choosing the mode on trial again, which answers no countdown.
            if let earlier { waiting[displayID] = earlier }
        case .restorePending(let restore):
            // Undo both trials only when they belong to the same physical display.
            // CoreGraphics may reuse the old display ID after a disconnect.
            if let earlier, earlier.restore.displayIdentity == restore.displayIdentity {
                wait(for: ModeSwitcher.PendingRestore(
                    displayID: restore.displayID, displayName: restore.displayName,
                    modeID: earlier.restore.modeID, fallbackModeID: earlier.restore.fallbackModeID,
                    trialModeID: restore.trialModeID, failure: restore.failure,
                    displayIdentity: earlier.restore.displayIdentity,
                    previousMode: earlier.restore.previousMode, fallbackMode: earlier.restore.fallbackMode,
                    trialMode: restore.trialMode
                ))
            } else {
                wait(for: restore)
            }
        case .applied, .kept, .keptForSession:
            // The person's new choice replaces the earlier revert.
            if let earlier {
                ResoluteLog.modes.notice("""
                    A new mode for \(earlier.restore.displayName, privacy: .public) replaces the restore \
                    of mode \(earlier.restore.modeID) that was waiting for it
                    """)
            }
        }
    }

    /// Finishes the reverts whose display is back. Called when the screen configuration
    /// changes, as it does when a display reconnects.
    func displaysDidChange() {
        guard switchesUnderWay == 0 else {
            hasMissedChanges = true
            return
        }
        for displayID in waiting.keys {
            attempt(displayID)
        }
    }

    /// Ends the waits that are due: each revert gets one last try, in case a screen change
    /// was missed, and is then given up.
    func expireRestores() {
        guard switchesUnderWay == 0 else {
            hasMissedChanges = true
            return
        }
        for (displayID, entry) in waiting where now() >= entry.deadline {
            attempt(displayID)
        }
    }

    /// Tries to finish the revert waiting for `displayID`. A display that refuses the mode
    /// is tried again on the next change, since one that has only just come back may not
    /// take a mode yet; once the wait is over, this was the last try.
    private func attempt(_ displayID: CGDirectDisplayID) {
        // Taken out first: putting the mode back changes the screen configuration again, and
        // an alert below lets this run again before it returns.
        guard var entry = waiting.removeValue(forKey: displayID) else { return }
        let switcher = ModeSwitcher(service: service)
        var failure: (any Error)?
        do {
            if try switcher.finish(entry.restore, logsFailures: !entry.hasFailed) != .waiting {
                // A mode that never showed is reported once the display is back, as it is
                // when the display stays.
                if let notShown = entry.restore.failure { report(notShown) }
                return
            }
        } catch {
            failure = error
            entry.hasFailed = true
        }
        guard now() >= entry.deadline else {
            waiting[displayID] = entry
            if failure != nil { retrySoon(displayID) }
            return
        }
        switcher.giveUp(on: entry.restore, after: restoreTimeout)
        // A display that is back but refuses is shown; one that stayed away is only logged.
        if let failure { report(failure) }
    }

    /// A display that has only just come back may refuse a mode for a moment and then
    /// change nothing more, so a refused revert is tried again after `retryInterval`, as
    /// `resolute set` does.
    private func retrySoon(_ displayID: CGDirectDisplayID) {
        guard retrying.insert(displayID).inserted else { return }
        Task { [weak self, retryInterval] in
            try? await Task.sleep(for: retryInterval)
            self?.retry(displayID)
        }
    }

    private func retry(_ displayID: CGDirectDisplayID) {
        retrying.remove(displayID)
        guard switchesUnderWay == 0 else {
            hasMissedChanges = true
            return
        }
        if waiting[displayID] != nil { attempt(displayID) }
    }

    private func wait(for restore: ModeSwitcher.PendingRestore) {
        let deadline = now() + restoreTimeout
        waiting[restore.displayID] = Waiting(restore: restore, deadline: deadline)
        // A connected display can briefly refuse the previous mode without emitting a
        // further screen notification. Start recovery promptly in that case too.
        retrySoon(restore.displayID)
        Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            self?.expireRestores()
        }
    }
}
