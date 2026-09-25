import AppKit
import os
import ResoluteKit

/// Applies mode changes chosen in the menu. Hidden modes are tried for the session first
/// and only kept when the person confirms, so a mode the display cannot show reverts.
///
/// A display that cannot show a mode may lose its link during the countdown. Its revert
/// then waits for the display to come back, which `displaysDidChange()` hears about,
/// without holding the main thread and without alerts while displays reconnect. After
/// `restoreTimeout` the revert is given up; the mode lasts at most until logout.
@MainActor
final class ModeChangeCoordinator {
    /// A revert waiting for its display, and when to stop waiting.
    private struct Waiting {
        var restore: ModeSwitcher.PendingRestore
        var deadline: ContinuousClock.Instant
    }

    private let service: any DisplayControlling
    private let decide: @MainActor () -> ModeSwitcher.Decision
    private let report: @MainActor (any Error) -> Void
    private let now: @MainActor () -> ContinuousClock.Instant
    private let restoreTimeout: Duration
    private var waiting: [CGDirectDisplayID: Waiting] = [:]

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
        // Once the person picks a mode for the display, the one from before must not return.
        if let replaced = waiting.removeValue(forKey: displayID) {
            ResoluteLog.modes.notice("""
                A new mode for \(replaced.restore.displayName, privacy: .public) replaces the restore \
                of mode \(replaced.restore.modeID) that was waiting for it
                """)
        }
        do {
            let outcome = try ModeSwitcher(service: service).apply(modeID: modeID, to: displayID, trial: needsConfirmation) {
                decide()
            }
            if case .restorePending(let restore) = outcome {
                wait(for: restore)
            }
        } catch {
            report(error)
        }
    }

    /// Finishes the reverts whose display is back. Called when the screen configuration
    /// changes, as it does when a display reconnects.
    func displaysDidChange() {
        giveUpOnExpiredRestores()
        let switcher = ModeSwitcher(service: service)
        for displayID in waiting.keys {
            // Taken out first: putting the mode back changes the screen configuration again,
            // and an alert below lets this run again before it returns.
            guard let entry = waiting.removeValue(forKey: displayID) else { continue }
            do {
                if try switcher.finish(entry.restore) == .waiting {
                    waiting[displayID] = entry
                }
            } catch {
                // The display is back, so it is not reconnecting any more.
                report(error)
            }
        }
    }

    /// Gives up on the reverts whose display has not come back in time.
    func giveUpOnExpiredRestores() {
        let switcher = ModeSwitcher(service: service)
        for (displayID, entry) in waiting where now() >= entry.deadline {
            waiting[displayID] = nil
            switcher.giveUp(on: entry.restore, after: restoreTimeout)
        }
    }

    private func wait(for restore: ModeSwitcher.PendingRestore) {
        let deadline = now() + restoreTimeout
        waiting[restore.displayID] = Waiting(restore: restore, deadline: deadline)
        Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            self?.giveUpOnExpiredRestores()
        }
    }
}
