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

        public init(displayID: CGDirectDisplayID, displayName: String, modeID: Int32, fallbackModeID: Int32?) {
            self.displayID = displayID
            self.displayName = displayName
            self.modeID = modeID
            self.fallbackModeID = fallbackModeID
        }
    }

    /// Where a pending restore stands.
    public enum RestoreProgress: Equatable, Sendable {
        /// The display is still away.
        case waiting
        /// The display is back and uses this mode again, until the user logs out.
        case restored(to: Int32)
    }

    private let service: any DisplayControlling
    /// Also checks that a listed mode on trial took, as a hidden one is checked. Only the
    /// live tests set it, to run the hidden-mode path on a Mac without hidden modes;
    /// CoreGraphics reports its own failures for listed modes.
    var verifiesListedModes = false

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
        let scope: ConfigurationScope = trial ? .session : .permanent
        let from = previous.map { "mode \($0)" } ?? "an unknown mode"
        Self.log.notice("""
            Switching \(name, privacy: .public) (display \(displayID)) from \(from, privacy: .public) \
            to mode \(modeID), scope \(scope.rawValue, privacy: .public)\(trial ? ", on trial" : "", privacy: .public)
            """)

        try service.apply(modeID: modeID, to: displayID, scope: scope)
        guard trial else { return .applied }
        let restore = Self.restore(on: displayID, named: name, before: before, previous: previous, leaving: modeID)
        // SkyLight reports no errors, so check that a hidden mode really took before asking
        // whether to keep it; CoreGraphics reports its own failures for listed modes.
        let isListed = before?.modes.first { $0.modeID == modeID }?.origin == .system
        if !isListed || verifiesListedModes {
            guard waitUntilCurrent(modeID, on: displayID) else {
                Self.log.error("\(name, privacy: .public) did not report mode \(modeID) within half a second")
                // Put the previous mode back in case the switch lands after all; when it never
                // happened this changes nothing.
                let undone = try revert(restore, name: name)
                if case .restorePending = undone { return undone }
                throw ResoluteError.modeNotApplied(display: before?.name ?? "The display")
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
            return try revert(restore, name: name)
        }
    }

    /// Finishes a restore that waited for its display. While the display is away nothing
    /// changes; once it is back, the previous mode (else the default one) returns for the
    /// session. Throws `revertFailed` when the display is back but takes neither mode.
    public func finish(_ pending: PendingRestore) throws -> RestoreProgress {
        guard let modeID = try putBack(pending) else { return .waiting }
        Self.log.notice("\(pending.displayName, privacy: .public) is back; put mode \(modeID) back for the session")
        return .restored(to: modeID)
    }

    /// Notes that `pending` will not be finished: its display stayed away for `wait`.
    public func giveUp(on pending: PendingRestore, after wait: Duration) {
        Self.log.error("""
            \(pending.displayName, privacy: .public) did not come back within \(wait.components.seconds) seconds, \
            so mode \(pending.modeID) was not put back
            """)
    }

    /// What undoing a trial of `modeID` puts back: the mode in use before, else the default
    /// one. Nil when neither is known.
    private static func restore(
        on displayID: CGDirectDisplayID,
        named name: String,
        before: Display?,
        previous: Int32?,
        leaving modeID: Int32
    ) -> PendingRestore? {
        let fallback = before?.modes.first { $0.origin == .system && $0.isDefault }?.modeID
        let candidates = [previous, fallback].compactMap { $0 }.filter { $0 != modeID }
        guard let first = candidates.first else { return nil }
        return PendingRestore(
            displayID: displayID, displayName: name, modeID: first,
            fallbackModeID: candidates.dropFirst().first { $0 != first }
        )
    }

    /// Undoes a trial for the session only (the saved setting was never touched), or hands
    /// the restore back to finish later when the display went away.
    private func revert(_ restore: PendingRestore?, name: String) throws -> Outcome {
        guard let restore else { throw ResoluteError.revertFailed(display: name) }
        guard let modeID = try putBack(restore) else {
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
    private func putBack(_ restore: PendingRestore) throws -> Int32? {
        guard isOnline(restore.displayID) else { return nil }
        for candidate in [restore.modeID, restore.fallbackModeID].compactMap({ $0 }) {
            do {
                try service.apply(modeID: candidate, to: restore.displayID, scope: .session)
                return candidate
            } catch {
                Self.log.error("""
                    Could not put mode \(candidate) back on \(restore.displayName, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """)
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
