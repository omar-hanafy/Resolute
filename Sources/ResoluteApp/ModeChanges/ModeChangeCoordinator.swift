import AppKit
import Observation
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
///
/// Observable, so the menu bar icon and the panel follow `pendingRestores` and
/// `isChangingMode` as they change.
@MainActor
@Observable
final class ModeChangeCoordinator {
    /// A revert waiting for its display, and when to stop waiting.
    private struct Waiting {
        var restore: ModeSwitcher.PendingRestore
        var deadline: ContinuousClock.Instant
        /// Whether putting the mode back has failed yet; only the first failure is logged.
        var hasFailed = false
    }

    /// How a revert that waited for its display ended, so History can say how its trial did.
    enum WaitEnding {
        /// The display is back and no longer shows the mode on trial: it was put back, or the
        /// display came back in another mode.
        case displayIsBack
        /// A new switch of the display, or a preset, replaced the revert.
        case replaced
        /// Stop Waiting: whatever the display shows when it comes back stays.
        case stopped
        /// Given up: the display stayed away, or came back and took neither mode, as the error says.
        case gaveUp(any Error)
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
    @ObservationIgnored private var hasMissedChanges = false
    /// Displays whose refused revert is due another try.
    @ObservationIgnored private var retrying: Set<CGDirectDisplayID> = []
    /// Work that waits for the switch under way (`afterSwitch(_:)`), oldest first.
    @ObservationIgnored private var waitingForSwitch: [@MainActor () -> Void] = []
    @ObservationIgnored private var isTakingUpWorkSoon = false
    /// Told whenever a revert that waited for its display stops waiting, however it ended, so
    /// History can say how that trial ended.
    @ObservationIgnored var onWaitEnded: @MainActor (ModeSwitcher.PendingRestore, WaitEnding) -> Void = { _, _ in }

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

    /// Switches `displayID` to `modeID`, with a Keep/Revert trial when `needsConfirmation`;
    /// `forSession` switches without one until logout only, as a revert does, so nothing is
    /// saved. Returns how it ended, or nil when it was not tried because a countdown was up.
    /// A failure is reported unless `reportsFailure` is false, for a caller that says so
    /// another way, as Shortcuts does.
    @discardableResult
    func apply(
        modeID: Int32, to displayID: CGDirectDisplayID, needsConfirmation: Bool, forSession: Bool = false,
        reportsFailure: Bool = true
    ) -> Result<ModeSwitcher.Outcome, any Error>? {
        // A switch chosen while the countdown is up could put its own alert or countdown
        // over it, holding up the revert until that one is closed.
        guard switchesUnderWay == 0 else {
            ResoluteLog.modes.notice("Ignored mode \(modeID) for display \(displayID), chosen while a countdown was up")
            return nil
        }
        switchesUnderWay += 1
        // A revert still waiting for this display goes first, so the new switch starts from
        // the mode the person had rather than from the one on trial. What it reports waits
        // for the switch: an alert before the countdown would let a request from `resolute`
        // show its own question meanwhile.
        if waiting[displayID] != nil { attempt(displayID) }
        let result = Result {
            // A switch for the session is a trial nobody is asked about, as `resolute set
            // --session` makes one.
            try ModeSwitcher(service: service).apply(modeID: modeID, to: displayID, trial: needsConfirmation || forSession) {
                needsConfirmation ? decide() : .keepForSession
            }
        }
        switchesUnderWay -= 1
        switch result {
        case .success(let outcome):
            settle(outcome, of: displayID)
        case .failure(let error):
            if reportsFailure { report(error) }
        }
        switchEnded()
        return result
    }

    /// Runs `work` now when no switch is under way, else once the switch is over: an alert,
    /// or a switch of its own, would otherwise go over the countdown and hold up its revert.
    /// Work that waited runs in the order it came, at the main run loop's next turn, so the
    /// caller of the switch has recorded and shown how it ended first.
    func afterSwitch(_ work: @escaping @MainActor () -> Void) {
        guard switchesUnderWay > 0 || !waitingForSwitch.isEmpty else { return work() }
        waitingForSwitch.append(work)
    }

    /// Takes up what waited for the switches that are now over.
    private func switchEnded() {
        guard switchesUnderWay == 0 else { return }
        if hasMissedChanges {
            hasMissedChanges = false
            displaysDidChange()
        }
        guard !waitingForSwitch.isEmpty, !isTakingUpWorkSoon else { return }
        isTakingUpWorkSoon = true
        // The run loop's way also runs inside a modal alert, where work queued on the main
        // actor waits.
        MainRunLoop.perform { [weak self] in
            guard let self else { return }
            isTakingUpWorkSoon = false
            // Not inside a countdown that began meanwhile: its end takes up the rest.
            while switchesUnderWay == 0, !waitingForSwitch.isEmpty {
                waitingForSwitch.removeFirst()()
            }
        }
    }

    /// Puts back what `restore` names, for a trial no switch of the app's will finish (a
    /// killed command's): now when its display is here and takes it, else once it is back,
    /// waiting as a trial's revert does. Returns how it went now, `.waiting` while it waits,
    /// or nil when it was not tried because a countdown was up. Throws when it can't wait:
    /// another display has its display ID now, with a revert of its own waiting, and an ID
    /// holds one revert, which the display that is here keeps.
    @discardableResult
    func putBack(_ restore: ModeSwitcher.PendingRestore) throws -> ModeSwitcher.RestoreProgress? {
        guard switchesUnderWay == 0 else { return nil }
        // The revert of another display that has this ID now goes first, as before a switch:
        // finished, it leaves the ID to this one.
        if let other = waiting[restore.displayID], other.restore.displayIdentity != restore.displayIdentity {
            attempt(restore.displayID)
        }
        let progress: ModeSwitcher.RestoreProgress
        do {
            progress = try ModeSwitcher(service: service).finish(restore)
        } catch {
            // The display is here but refused both modes: tried again, as a trial's revert is.
            progress = .waiting
        }
        if progress == .waiting {
            if let other = waiting[restore.displayID], other.restore.displayIdentity != restore.displayIdentity {
                ResoluteLog.modes.error("""
                    \(other.restore.displayName, privacy: .public) has the display ID of \
                    \(restore.displayName, privacy: .public) and a revert waiting, so mode \(restore.modeID) \
                    can't be put back on it
                    """)
                throw DisplayIDTaken(display: restore.displayName)
            }
            // Joined with a revert still waiting for the display, as a new trial's is.
            settle(.restorePending(restore), of: restore.displayID)
        } else if waiting[restore.displayID] != nil {
            // A revert still waiting for the display goes after, unlike before a switch: the
            // command's trial began from the earlier trial's mode, which is back only now.
            attempt(restore.displayID)
        }
        return progress
    }

    /// Applies `preset`, unless a countdown is up. Reverts still waiting for their display
    /// go first, so the preset starts from the modes the person had. Presets use listed
    /// modes only, so nothing needs Keep or Revert.
    func applyPreset(_ preset: Preset) -> PresetResult? {
        guard switchesUnderWay == 0 else {
            ResoluteLog.modes.notice("Ignored the preset \(preset.name, privacy: .public), chosen while a countdown was up")
            return nil
        }
        switchesUnderWay += 1
        for displayID in waiting.keys { attempt(displayID) }
        let result = PresetApplier(service: service).apply(preset)
        switchesUnderWay -= 1
        // The preset's switches replace the reverts of the displays it switched.
        for change in result.displays where change.outcome.isSwitch {
            guard let display = change.display, let entry = waiting[display.id], Self.waits(entry.restore, for: display) else {
                continue
            }
            waiting.removeValue(forKey: display.id)
            onWaitEnded(entry.restore, .replaced)
        }
        switchEnded()
        return result
    }

    /// Whether `restore` waits for `display`, the one at its display ID now. CoreGraphics
    /// may give the ID of a display that is away to another display, whose own switches
    /// leave that revert waiting.
    private static func waits(_ restore: ModeSwitcher.PendingRestore, for display: Display?) -> Bool {
        guard let identity = restore.displayIdentity else { return true }
        return display.map { ModeSwitcher.DisplayIdentity($0) == identity } ?? false
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
                if let earlier {
                    // Another display has the ID of the one still away, whose revert is lost.
                    ResoluteLog.modes.error("""
                        \(restore.displayName, privacy: .public) took the display ID of \
                        \(earlier.restore.displayName, privacy: .public), so mode \(earlier.restore.modeID) \
                        can't be put back on it
                        """)
                    onWaitEnded(earlier.restore, .gaveUp(ResoluteError.displayDidNotReturn(display: earlier.restore.displayName)))
                }
                wait(for: restore)
            }
        case .applied, .kept, .keptForSession:
            guard let earlier else { break }
            // Another display that took the ID of one still away leaves its revert waiting.
            guard Self.waits(earlier.restore, for: service.displays().first(where: { $0.id == displayID })) else {
                waiting[displayID] = earlier
                break
            }
            // The person's new choice replaces the earlier revert.
            ResoluteLog.modes.notice("""
                A new mode for \(earlier.restore.displayName, privacy: .public) replaces the restore \
                of mode \(earlier.restore.modeID) that was waiting for it
                """)
            onWaitEnded(earlier.restore, .replaced)
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

    /// Stops waiting for `displayID` (Stop Waiting in the panel): whatever the display shows
    /// when it comes back stays. Nothing changes while a switch is under way, since its
    /// countdown may be about to settle that revert.
    func stopWaiting(for displayID: CGDirectDisplayID) {
        guard switchesUnderWay == 0, let entry = waiting.removeValue(forKey: displayID) else { return }
        ResoluteLog.modes.notice("""
            Stopped waiting to put mode \(entry.restore.modeID) back on \(entry.restore.displayName, privacy: .public), \
            as the person asked
            """)
        onWaitEnded(entry.restore, .stopped)
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
                onWaitEnded(entry.restore, .displayIsBack)
                // A mode that never showed is reported once the display is back, as it is
                // when the display stays.
                if let notShown = entry.restore.failure { reportOnceNoSwitchIsUnderWay(notShown) }
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
        onWaitEnded(entry.restore, .gaveUp(failure ?? ResoluteError.displayDidNotReturn(display: entry.restore.displayName)))
        // A display that is back but refuses is shown; one that stayed away is only logged.
        if let failure { reportOnceNoSwitchIsUnderWay(failure) }
    }

    /// Shows `error` now, or once the switch under way is over when a revert finished as it
    /// began: an alert before its countdown, or over it, would hold up a question.
    private func reportOnceNoSwitchIsUnderWay(_ error: any Error) {
        afterSwitch { [weak self] in self?.report(error) }
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

/// Why a revert for a display that is away could not wait: another display has its ID now,
/// with a revert of its own waiting.
struct DisplayIDTaken: LocalizedError {
    var display: String

    var errorDescription: String? {
        "Another display took the place of \(display) while it was away, so its previous mode was not put back."
    }
}
