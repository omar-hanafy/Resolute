import CoreGraphics
import Foundation
import os

/// Switches display modes. A trial (used for hidden modes) is applied for the session
/// first and saved only when someone confirms it; otherwise the previous mode returns.
public struct ModeSwitcher: Sendable {
    private static let log = ResoluteLog.modes

    /// What to do with a mode on trial.
    public enum Decision: Equatable, Sendable {
        /// Save it, like a change made in System Settings.
        case keep
        /// Leave it until the user logs out.
        case keepForSession
        /// Go back to the previous mode.
        case revert
    }

    /// How a switch ended.
    public enum Outcome: Equatable, Sendable {
        case alreadyCurrent
        /// Saved without a trial.
        case applied
        case kept
        case keptForSession
        case reverted(to: Int32)
        /// The display went away before the previous mode could be put back. Finish the
        /// restore with `finish(_:)` once the display is back.
        case restorePending(PendingRestore)
    }

    /// A revert that waits for its display. A display that cannot show a mode may lose its
    /// link and reconnect, and it can come back in the mode on trial.
    public struct PendingRestore: Equatable, Sendable {
        public let displayID: CGDirectDisplayID
        /// The display's name before it went away, for messages while it is away.
        public let displayName: String
        /// The mode to put back: the one in use before the trial.
        public let modeID: Int32
        /// Put back when `modeID` cannot be: the display's default mode.
        public let fallbackModeID: Int32?
        /// The mode on trial. Only it is undone: a display back in another mode, whether
        /// its saved one, one chosen since or another display given the same ID, is left
        /// as it is.
        public let trialModeID: Int32
        /// What to report once the display is back: why the switch failed, when the mode on
        /// trial never showed.
        public let failure: ResoluteError?

        public init(
            displayID: CGDirectDisplayID,
            displayName: String,
            modeID: Int32,
            fallbackModeID: Int32?,
            trialModeID: Int32,
            failure: ResoluteError? = nil
        ) {
            self.displayID = displayID
            self.displayName = displayName
            self.modeID = modeID
            self.fallbackModeID = fallbackModeID
            self.trialModeID = trialModeID
            self.failure = failure
        }
    }

    /// Where a pending restore stands.
    public enum RestoreProgress: Equatable, Sendable {
        /// The display is still away.
        case waiting
        /// The display is back and uses this mode again, until the user logs out.
        case restored(to: Int32)
        /// The display is back in a mode other than the one on trial, so it was left as it is.
        case leftAlone(current: Int32)
    }

    private let service: any DisplayControlling
    /// Also checks that a listed mode on trial took, as a hidden one is checked. Only the
    /// live tests set it, to run the hidden-mode path on a Mac without hidden modes;
    /// CoreGraphics reports its own failures for listed modes.
    var verifiesListedModes = false
    /// How long a trial and the way back from it last. Only the live tests change it, to
    /// `.app`, so CoreGraphics undoes their trial when the test process ends.
    var trialScope = ConfigurationScope.session

    public init(service: any DisplayControlling) {
        self.service = service
    }

    /// Switches `displayID` to `modeID`. For a trial, `decide` is asked, after the switch,
    /// whether to keep the mode. When the display goes away before a trial can be undone,
    /// the outcome is `restorePending`; before a kept mode is saved, `displayWentAway` is
    /// thrown.
    public func apply(
        modeID: Int32,
        to displayID: CGDirectDisplayID,
        trial: Bool,
        decide: () -> Decision
    ) throws -> Outcome {
        // The full snapshot knows the current mode even when it is a hidden one.
        let before = service.displays().first { $0.id == displayID }
        let previous = before?.currentModeID ?? service.currentModeID(of: displayID)
        guard previous != modeID else { return .alreadyCurrent }
        let name = before?.name ?? "Display \(displayID)"
        let scope = trial ? trialScope : .permanent
        let from = previous.map { "mode \($0)" } ?? "an unknown mode"
        Self.log.notice("""
            Switching \(name, privacy: .public) (display \(displayID)) from \(from, privacy: .public) \
            to mode \(modeID), scope \(scope.rawValue, privacy: .public)\(trial ? ", on trial" : "", privacy: .public)
            """)

        try service.apply(modeID: modeID, to: displayID, scope: scope)
        guard trial else { return .applied }
        let restore = { (failure: ResoluteError?) in
            Self.restore(on: displayID, named: name, before: before, previous: previous, trial: modeID, failure: failure)
        }
        // SkyLight reports no errors, so check that a hidden mode really took before asking
        // whether to keep it; CoreGraphics reports its own failures for listed modes.
        let isListed = before?.modes.first { $0.modeID == modeID }?.origin == .system
        if !isListed || verifiesListedModes {
            guard waitUntilCurrent(modeID, on: displayID) else {
                Self.log.error("\(name, privacy: .public) did not report mode \(modeID) within half a second")
                let notShown = ResoluteError.modeNotApplied(display: before?.name ?? "The display")
                // Put the previous mode back in case the switch lands after all; when it never
                // happened this changes nothing.
                let undone = try revert(restore(notShown), name: name)
                if case .restorePending = undone { return undone }
                throw notShown
            }
            Self.log.info("\(name, privacy: .public) reports mode \(modeID); asking whether to keep it")
        }

        switch decide() {
        case .keep:
            do {
                try service.apply(modeID: modeID, to: displayID, scope: .permanent)
            } catch where !isOnline(displayID) {
                Self.log.error("\(name, privacy: .public) went away before mode \(modeID) could be saved")
                throw ResoluteError.displayWentAway(display: name)
            }
            Self.log.notice("Kept mode \(modeID) on \(name, privacy: .public)")
            return .kept
        case .keepForSession:
            Self.log.notice("Kept mode \(modeID) on \(name, privacy: .public) until logout")
            return .keptForSession
        case .revert:
            return try revert(restore(nil), name: name)
        }
    }

    /// Finishes a restore that waited for its display. While the display is away nothing
    /// changes. Once it is back and shows the mode on trial, or does not say which mode it
    /// shows, the previous mode (else the default one) returns for the session; a display
    /// back in any other mode is left as it is. Throws `revertFailed` when the display takes
    /// neither mode, which one that has only just come back may do for a moment, so callers
    /// try again; `logsFailures` lets them log only the first failure.
    public func finish(_ pending: PendingRestore, logsFailures: Bool = true) throws -> RestoreProgress {
        // Both questions go to one snapshot: CoreGraphics reports a placeholder mode for a
        // display that has gone away, so its mode is only read while it is listed.
        guard let display = service.displays().first(where: { $0.id == pending.displayID }) else { return .waiting }
        if let current = Self.otherModeShown(by: display, than: pending.trialModeID) {
            Self.log.notice("""
                \(pending.displayName, privacy: .public) is back in mode \(current), not the mode on trial, \
                so it is left as it is
                """)
            return .leftAlone(current: current)
        }
        guard let modeID = try putBack(pending, logsFailures: logsFailures) else { return .waiting }
        Self.log.notice("\(pending.displayName, privacy: .public) is back; put mode \(modeID) back for the session")
        return .restored(to: modeID)
    }

    /// Notes that `pending` will not be finished after `wait`: its display stayed away, or
    /// came back but took neither mode.
    public func giveUp(on pending: PendingRestore, after wait: Duration) {
        let seconds = wait.components.seconds
        if isOnline(pending.displayID) {
            Self.log.error("""
                Gave up putting mode \(pending.modeID) back on \(pending.displayName, privacy: .public): \
                it is back but took neither that mode nor its default one within \(seconds) seconds
                """)
        } else {
            Self.log.error("""
                \(pending.displayName, privacy: .public) did not come back within \(seconds) seconds, \
                so mode \(pending.modeID) was not put back
                """)
        }
    }

    /// The mode `display` shows when it is one it lists other than `trialModeID`. Judged only
    /// when the display lists that mode too: one that dropped off while its snapshot was
    /// taken lists only CoreGraphics' placeholder, which says nothing about its mode.
    private static func otherModeShown(by display: Display, than trialModeID: Int32) -> Int32? {
        let lists = { (modeID: Int32) in display.modes.contains { $0.modeID == modeID } }
        guard lists(trialModeID), let current = display.currentModeID, current != trialModeID, lists(current) else {
            return nil
        }
        return current
    }

    /// What undoing a trial of `modeID` puts back: the mode in use before, else the default
    /// one. Nil when neither is known.
    private static func restore(
        on displayID: CGDirectDisplayID,
        named name: String,
        before: Display?,
        previous: Int32?,
        trial modeID: Int32,
        failure: ResoluteError?
    ) -> PendingRestore? {
        let fallback = before?.modes.first { $0.origin == .system && $0.isDefault }?.modeID
        let candidates = [previous, fallback].compactMap { $0 }.filter { $0 != modeID }
        guard let first = candidates.first else { return nil }
        return PendingRestore(
            displayID: displayID, displayName: name, modeID: first,
            fallbackModeID: candidates.dropFirst().first { $0 != first }, trialModeID: modeID, failure: failure
        )
    }

    /// Undoes a trial for the session only (the saved setting was never touched), or hands
    /// the restore back to finish later when the display went away.
    private func revert(_ restore: PendingRestore?, name: String) throws -> Outcome {
        guard let restore else { throw ResoluteError.revertFailed(display: name) }
        guard let modeID = try putBack(restore, logsFailures: true) else {
            Self.log.notice("""
                \(restore.displayName, privacy: .public) went away before mode \(restore.modeID) could be put back; \
                the restore waits for it to come back
                """)
            return .restorePending(restore)
        }
        Self.log.notice("Put mode \(modeID) back on \(restore.displayName, privacy: .public) for the session")
        return .reverted(to: modeID)
    }

    /// Puts the mode `restore` names back for the session, else its fallback. Returns nil,
    /// having changed nothing, while the display is away.
    private func putBack(_ restore: PendingRestore, logsFailures: Bool) throws -> Int32? {
        guard isOnline(restore.displayID) else { return nil }
        for candidate in [restore.modeID, restore.fallbackModeID].compactMap({ $0 }) {
            do {
                try service.apply(modeID: candidate, to: restore.displayID, scope: trialScope)
                return candidate
            } catch where logsFailures {
                Self.log.error("""
                    Could not put mode \(candidate) back on \(restore.displayName, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """)
            } catch {
                continue
            }
        }
        // The display can go away while the modes are being put back.
        guard isOnline(restore.displayID) else { return nil }
        throw ResoluteError.revertFailed(display: restore.displayName)
    }

    /// Whether a fresh snapshot, which lists only online displays, has `displayID`.
    private func isOnline(_ displayID: CGDirectDisplayID) -> Bool {
        service.displays().contains { $0.id == displayID }
    }

    /// Whether `displayID` reports `modeID` within half a second: a display may report a
    /// switch a moment late.
    private func waitUntilCurrent(_ modeID: Int32, on displayID: CGDirectDisplayID) -> Bool {
        for check in 1...6 {
            if currentModeID(of: displayID) == modeID { return true }
            if check < 6 { Thread.sleep(forTimeInterval: 0.1) }
        }
        return false
    }

    /// The mode `displayID` uses now. The full snapshot also knows hidden modes, which
    /// CoreGraphics may not report.
    public func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        service.displays().first { $0.id == displayID }?.currentModeID ?? service.currentModeID(of: displayID)
    }
}
