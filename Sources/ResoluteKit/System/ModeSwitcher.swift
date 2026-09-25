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
    }

    private let service: any DisplayControlling

    public init(service: any DisplayControlling) {
        self.service = service
    }

    /// Switches `displayID` to `modeID`. For a trial, `decide` is asked, after the switch,
    /// whether to keep the mode.
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
        // SkyLight reports no errors, so check that a hidden mode really took before asking
        // whether to keep it; CoreGraphics reports its own failures for listed modes.
        let isListed = before?.modes.first { $0.modeID == modeID }?.origin == .system
        if !isListed {
            guard waitUntilCurrent(modeID, on: displayID) else {
                Self.log.error("\(name, privacy: .public) did not report mode \(modeID) within half a second")
                // Put the previous mode back in case the switch lands after all; when it never
                // happened this changes nothing.
                _ = try restore(before: before, previous: previous, leaving: modeID, on: displayID)
                throw ResoluteError.modeNotApplied(display: before?.name ?? "The display")
            }
            Self.log.info("\(name, privacy: .public) reports mode \(modeID); asking whether to keep it")
        }

        switch decide() {
        case .keep:
            try service.apply(modeID: modeID, to: displayID, scope: .permanent)
            Self.log.notice("Kept mode \(modeID) on \(name, privacy: .public)")
            return .kept
        case .keepForSession:
            Self.log.notice("Kept mode \(modeID) on \(name, privacy: .public) until logout")
            return .keptForSession
        case .revert:
            return .reverted(to: try restore(before: before, previous: previous, leaving: modeID, on: displayID))
        }
    }

    /// Switches back for the session only (the saved setting was never touched): to the
    /// previous mode, else the default one. Returns the mode it restored.
    private func restore(
        before: Display?,
        previous: Int32?,
        leaving modeID: Int32,
        on displayID: CGDirectDisplayID
    ) throws -> Int32 {
        let name = before?.name ?? "Display \(displayID)"
        let fallback = before?.modes.first { $0.origin == .system && $0.isDefault }?.modeID
        for candidate in [previous, fallback].compactMap({ $0 }) where candidate != modeID {
            do {
                try service.apply(modeID: candidate, to: displayID, scope: .session)
                Self.log.notice("Put mode \(candidate) back on \(name, privacy: .public) for the session")
                return candidate
            } catch {
                Self.log.error("""
                    Could not put mode \(candidate) back on \(name, privacy: .public): \
                    \(error.localizedDescription, privacy: .public)
                    """)
            }
        }
        throw ResoluteError.revertFailed(display: before?.name ?? "the display")
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
