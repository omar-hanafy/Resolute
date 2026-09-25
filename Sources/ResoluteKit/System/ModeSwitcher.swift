import CoreGraphics
import Foundation
import os

/// Switches display modes. A trial (used for hidden modes) is applied for the session
/// first and saved only when someone confirms it; otherwise the previous mode returns.
public struct ModeSwitcher: Sendable {
    private static let log = ResoluteLog.modes

    /// Available hardware identity, independent of CoreGraphics' session display ID.
    /// Identical monitors without distinct serial numbers cannot be distinguished here.
    public struct DisplayIdentity: Equatable, Sendable {
        let vendorID: UInt32
        let productID: UInt32
        let serialNumber: UInt32
        let isBuiltin: Bool

        public init(_ display: Display) {
            vendorID = display.vendorID
            productID = display.productID
            serialNumber = display.serialNumber
            isBuiltin = display.isBuiltin
        }
    }

    /// Mode properties that must survive reconnect; numeric IDs and private indexes may not.
    public struct ModeFingerprint: Equatable, Sendable {
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int
        let refreshKey: Int
        let bitsPerSample: Int?
        let ioFlags: UInt32

        public init(_ mode: DisplayMode) {
            width = mode.width
            height = mode.height
            pixelWidth = mode.pixelWidth
            pixelHeight = mode.pixelHeight
            refreshKey = mode.refreshKey
            bitsPerSample = mode.bitsPerSample
            ioFlags = mode.ioFlags
        }

        func resolve(preferredID: Int32, in display: Display) -> Int32? {
            if let sameID = display.modes.first(where: { $0.modeID == preferredID }), Self(sameID) == self {
                return preferredID
            }
            let matches = display.modes.filter { Self($0) == self }
            return matches.count == 1 ? matches[0].modeID : nil
        }
    }

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
        /// The display went away or refused the restore. Retry with `finish(_:)` once it
        /// is ready; the recovery target is retained even after a transient failure.
        case restorePending(PendingRestore)
        /// The display showed another mode than the one on trial when the answer came, so
        /// nothing was undone.
        case leftAlone(current: Int32)
    }

    /// A revert that waits for its display to become ready. A display that cannot show a
    /// mode may lose its link, or briefly refuse changes, and remain in the mode on trial.
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
        /// Generated restores are bound to the original display and mode properties.
        /// Nil defaults preserve callers that explicitly construct a legacy restore.
        public let displayIdentity: DisplayIdentity?
        public let previousMode: ModeFingerprint?
        public let fallbackMode: ModeFingerprint?
        public let trialMode: ModeFingerprint?

        public init(
            displayID: CGDirectDisplayID,
            displayName: String,
            modeID: Int32,
            fallbackModeID: Int32?,
            trialModeID: Int32,
            failure: ResoluteError? = nil,
            displayIdentity: DisplayIdentity? = nil,
            previousMode: ModeFingerprint? = nil,
            fallbackMode: ModeFingerprint? = nil,
            trialMode: ModeFingerprint? = nil
        ) {
            self.displayID = displayID
            self.displayName = displayName
            self.modeID = modeID
            self.fallbackModeID = fallbackModeID
            self.trialModeID = trialModeID
            self.failure = failure
            self.displayIdentity = displayIdentity
            self.previousMode = previousMode
            self.fallbackMode = fallbackMode
            self.trialMode = trialMode
        }

        /// Find the original display after reconnect. A changed display ID requires a
        /// nonzero serial and exactly one identity match; model IDs alone are not unique.
        public func resolveDisplay(in displays: [Display]) -> Display? {
            guard let displayIdentity else { return displays.first { $0.id == displayID } }
            if let original = displays.first(where: { $0.id == displayID }), DisplayIdentity(original) == displayIdentity {
                return original
            }
            guard displayIdentity.serialNumber != 0 else { return nil }
            let matches = displays.filter { DisplayIdentity($0) == displayIdentity }
            return matches.count == 1 ? matches[0] : nil
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
    /// whether to keep the mode. When the display goes away or refuses to undo a trial,
    /// the outcome is `restorePending`; before a kept mode is saved, `displayWentAway` is
    /// thrown. The answer is about the mode on trial: a display showing another mode by
    /// then, because it came back in one or was switched elsewhere, keeps what it shows.
    public func apply(
        modeID: Int32,
        to displayID: CGDirectDisplayID,
        trial: Bool,
        decide: () -> Decision
    ) throws -> Outcome {
        // The full snapshot knows the current mode even when it is a hidden one.
        guard let before = service.displays().first(where: { $0.id == displayID }) else {
            throw ResoluteError.displayNotFound("id:\(displayID)")
        }
        let previous = before.currentModeID ?? service.currentModeID(of: displayID)
        guard previous != modeID else { return .alreadyCurrent }
        let name = before.name
        let identity = DisplayIdentity(before)
        let trialMode = before.modes.first { $0.modeID == modeID }.map(ModeFingerprint.init)
        let scope = trial ? trialScope : .permanent
        let from = previous.map { "mode \($0)" } ?? "an unknown mode"
        Self.log.notice("""
            Switching \(name, privacy: .public) (display \(displayID)) from \(from, privacy: .public) \
            to mode \(modeID), scope \(scope.rawValue, privacy: .public)\(trial ? ", on trial" : "", privacy: .public)
            """)

        let restore = { (failure: ResoluteError?) in
            Self.restore(on: displayID, named: name, before: before, previous: previous, trial: modeID, failure: failure)
        }
        if trial {
            guard trialMode != nil else { throw ResoluteError.modeNotFound("mode \(modeID)", suggestions: []) }
            guard let recovery = restore(nil), recovery.previousMode != nil || recovery.fallbackMode != nil else {
                throw ResoluteError.usage("Cannot try a mode on \(name): no previous or default mode is available for recovery.")
            }
        }
        try service.apply(modeID: modeID, to: displayID, scope: scope)
        guard trial else { return .applied }
        // SkyLight reports no errors, so check that a hidden mode really took before asking
        // whether to keep it; CoreGraphics reports its own failures for listed modes.
        let isListed = before.modes.first { $0.modeID == modeID }?.origin == .system
        let checksShownMode = !isListed || verifiesListedModes
        if checksShownMode {
            guard waitUntilCurrent(modeID, on: displayID) else {
                Self.log.error("\(name, privacy: .public) did not report mode \(modeID) within half a second")
                let notShown = ResoluteError.modeNotApplied(display: name)
                // Put the previous mode back in case the switch lands after all; when it never
                // happened this changes nothing.
                let undone = try revert(restore(notShown), name: name)
                if case .restorePending = undone { return undone }
                throw notShown
            }
            Self.log.info("\(name, privacy: .public) reports mode \(modeID); asking whether to keep it")
        }

        let decision = decide()
        // A mode seen on the display before asking is looked for again at the answer.
        let answeredOn = service.displays().first { $0.id == displayID }
        switch decision {
        case .keep, .keepForSession:
            // Saving the mode on trial over another one would switch the display back to
            // what may have made it drop off.
            guard let answeredOn else { throw ResoluteError.displayWentAway(display: name) }
            if identity != DisplayIdentity(answeredOn)
                || (answeredOn.currentModeID ?? service.currentModeID(of: displayID)) != modeID
                || (trialMode != nil && answeredOn.currentMode.map(ModeFingerprint.init) != trialMode) {
                Self.log.error("\(name, privacy: .public) no longer showed mode \(modeID) at the answer, so it was not kept")
                throw ResoluteError.displayChangedDuringTrial(display: name)
            }
            guard decision == .keep else {
                Self.log.notice("Kept mode \(modeID) on \(name, privacy: .public) until logout")
                return .keptForSession
            }
            do {
                try service.apply(modeID: modeID, to: displayID, scope: .permanent)
            } catch where !isOnline(displayID) {
                Self.log.error("\(name, privacy: .public) went away before mode \(modeID) could be saved")
                throw ResoluteError.displayWentAway(display: name)
            }
            Self.log.notice("Kept mode \(modeID) on \(name, privacy: .public)")
            return .kept
        case .revert:
            if let answeredOn, identity == DisplayIdentity(answeredOn),
               let current = Self.otherModeShown(by: answeredOn, than: modeID, fingerprint: trialMode) {
                Self.log.notice("\(name, privacy: .public) showed mode \(current) at the answer, not the mode on trial, so it is left as it is")
                return .leftAlone(current: current)
            }
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
        guard let display = pending.resolveDisplay(in: service.displays()) else { return .waiting }
        if let current = Self.otherModeShown(by: display, than: pending.trialModeID, fingerprint: pending.trialMode) {
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
        if pending.resolveDisplay(in: service.displays()) != nil {
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
    private static func otherModeShown(
        by display: Display, than trialModeID: Int32, fingerprint: ModeFingerprint? = nil
    ) -> Int32? {
        if let fingerprint {
            guard let current = display.currentMode, current.width > 1, current.height > 1 else { return nil }
            return ModeFingerprint(current) == fingerprint ? nil : current.modeID
        }
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
        before: Display,
        previous: Int32?,
        trial modeID: Int32,
        failure: ResoluteError?
    ) -> PendingRestore? {
        let fallback = before.modes.first { $0.origin == .system && $0.isDefault }?.modeID
        let candidates = [previous, fallback].compactMap { $0 }.filter { $0 != modeID }
        guard let first = candidates.first else { return nil }
        let fallbackID = candidates.dropFirst().first { $0 != first }
        func fingerprint(_ id: Int32?) -> ModeFingerprint? {
            before.modes.first { $0.modeID == id }.map(ModeFingerprint.init)
        }
        return PendingRestore(
            displayID: displayID, displayName: name, modeID: first,
            fallbackModeID: fallbackID, trialModeID: modeID, failure: failure,
            displayIdentity: DisplayIdentity(before), previousMode: fingerprint(first),
            fallbackMode: fingerprint(fallbackID), trialMode: fingerprint(modeID)
        )
    }

    /// Undoes a trial for the session only (the saved setting was never touched), or hands
    /// the restore back to finish later when the display went away or refused it.
    private func revert(_ restore: PendingRestore?, name: String) throws -> Outcome {
        guard let restore else { throw ResoluteError.revertFailed(display: name) }
        let modeID: Int32?
        do {
            modeID = try putBack(restore, logsFailures: true)
        } catch ResoluteError.revertFailed {
            Self.log.error("\(restore.displayName, privacy: .public) refused the restore; retaining it for retry")
            return .restorePending(restore)
        }
        guard let modeID else { return .restorePending(restore) }
        Self.log.notice("Put mode \(modeID) back on \(restore.displayName, privacy: .public) for the session")
        return .reverted(to: modeID)
    }

    /// Puts the mode `restore` names back for the session, else its fallback. Returns nil,
    /// having changed nothing, while the display is away.
    private func putBack(_ restore: PendingRestore, logsFailures: Bool) throws -> Int32? {
        guard let display = restore.resolveDisplay(in: service.displays()) else { return nil }
        let candidates: [(Int32?, ModeFingerprint?)] = [
            (restore.modeID, restore.previousMode), (restore.fallbackModeID, restore.fallbackMode),
        ]
        for (requestedID, fingerprint) in candidates {
            guard let requestedID else { continue }
            // A generated restore never reuses an ID whose properties were unknown or
            // changed. Resolve a renumbered mode only when its fingerprint is unique.
            let resolved = fingerprint?.resolve(preferredID: requestedID, in: display)
            guard let candidate = restore.displayIdentity == nil ? requestedID : resolved else { continue }
            do {
                try service.apply(modeID: candidate, to: display.id, scope: trialScope)
                // Private setters have no error result, including on the way back. A
                // successful transaction alone must not suppress the fallback mode.
                if display.modes.first(where: { $0.modeID == candidate })?.origin != .system,
                   !waitUntilCurrent(candidate, on: display.id) {
                    throw ResoluteError.modeNotApplied(display: restore.displayName)
                }
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
        guard restore.resolveDisplay(in: service.displays()) != nil else { return nil }
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
        guard let display = service.displays().first(where: { $0.id == displayID }) else { return nil }
        return display.currentModeID ?? service.currentModeID(of: displayID)
    }
}
