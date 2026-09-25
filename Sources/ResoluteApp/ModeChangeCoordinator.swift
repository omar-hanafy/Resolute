import AppKit
import os
import ResoluteKit

/// Applies mode changes chosen in the menu. Hidden modes are tried for the session first
/// and only kept when the person confirms, so a mode the display cannot show reverts.
///
/// A display that cannot show a mode may lose its link during the countdown. Its revert
/// then waits for the display to come back, which `displaysDidChange()` hears about,
/// without holding the main thread and without alerts while the display is away. After
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
    private var waiting: [CGDirectDisplayID: Waiting] = [:]
    /// Switches under way. During one the Keep/Revert countdown may be up, and its timer
    /// ends the innermost modal alert, so no other alert may open: screen changes are taken
    /// up once the switch is over.
    private var switchesUnderWay = 0
    private var hasMissedChanges = false

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
        restoreTimeout: Duration = .seconds(120)
    ) {
        self.service = service
        self.decide = decide
        self.report = report
        self.now = now
        self.restoreTimeout = restoreTimeout
    }

    /// The reverts waiting for their display.
    var pendingRestores: [ModeSwitcher.PendingRestore] {
        waiting.values.map(\.restore).sorted { $0.displayID < $1.displayID }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, needsConfirmation: Bool) {
        // A revert still waiting for this display goes first, so the new switch starts from
        // the mode the person had rather than from the one on trial. Not while another
        // switch is under way, where it could open an alert over that countdown.
        if switchesUnderWay == 0, waiting[displayID] != nil { attempt(displayID) }
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
        case .reverted:
            // Undoing the new trial took the display back to where it was, which can be the
            // earlier trial a refusing display is still in, so that revert keeps waiting.
            if let earlier { waiting[displayID] = earlier }
        case .restorePending(let restore):
            // Undoing both trials means going back to the mode from before the first one.
            wait(for: earlier.map {
                ModeSwitcher.PendingRestore(
                    displayID: restore.displayID, displayName: restore.displayName,
                    modeID: $0.restore.modeID, fallbackModeID: $0.restore.fallbackModeID,
                    trialModeID: restore.trialModeID, failure: restore.failure
                )
            } ?? restore)
        case .alreadyCurrent, .applied, .kept, .keptForSession:
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
            return
        }
        switcher.giveUp(on: entry.restore, after: restoreTimeout)
        // A display that is back but refuses is shown; one that stayed away is only logged.
        if let failure { report(failure) }
    }

    private func wait(for restore: ModeSwitcher.PendingRestore) {
        let deadline = now() + restoreTimeout
        waiting[restore.displayID] = Waiting(restore: restore, deadline: deadline)
        Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            self?.expireRestores()
        }
    }
}
