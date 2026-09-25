import CoreGraphics
import Foundation
@testable import ResoluteKit

/// Lets one display of another service drop off and come back, as a display does when it
/// loses its link to a mode it cannot show. While away it is missing from snapshots and
/// cannot be switched, and CoreGraphics reports the placeholder mode 0 as its current mode,
/// as it does for a display that is not online.
final class ReconnectingDisplays: DisplayControlling, @unchecked Sendable {
    /// Which mode the display says it shows.
    private enum Shown {
        /// Whatever the wrapped service says.
        case asWrapped
        /// This mode, or none, until the display is switched.
        case mode(Int32?)
        /// CoreGraphics' 1 × 1 placeholder, as the only mode it lists, as for a display that
        /// dropped off while a snapshot was taken.
        case placeholder
    }

    /// The mode CoreGraphics lists, and reports as current, for a display that went away.
    static let placeholder = DisplayMode(modeID: 0, width: 1, height: 1, pixelWidth: 1, pixelHeight: 1, refreshRate: 60)

    private let base: any DisplayControlling
    private let displayID: CGDirectDisplayID
    private let lock = NSLock()
    /// Snapshots the display still misses; nil while it is away until `reconnect()`.
    private var snapshotsAway: Int? = 0
    /// Snapshots the display is back for before it drops off again; nil for as long as it likes.
    private var snapshotsBack: Int?
    /// A switch that makes the display drop off.
    private var drop: (modeID: Int32, snapshots: Int?)?
    private var shown = Shown.asWrapped

    init(_ base: any DisplayControlling, displayID: CGDirectDisplayID) {
        self.base = base
        self.displayID = displayID
    }

    /// Takes the display away for the next `snapshots` snapshots, or until `reconnect()`.
    func disconnect(forSnapshots snapshots: Int? = nil) {
        lock.withLock { snapshotsAway = snapshots }
    }

    /// Takes the display away as soon as it switches to `modeID`.
    func disconnect(whenSwitchedTo modeID: Int32, forSnapshots snapshots: Int? = nil) {
        lock.withLock { drop = (modeID, snapshots) }
    }

    /// Brings the display back, for the next `snapshots` snapshots before it drops off again
    /// when given, as a display with a failing link may.
    func reconnect(forSnapshots snapshots: Int? = nil) {
        lock.withLock {
            snapshotsAway = 0
            snapshotsBack = snapshots
        }
    }

    /// Brings the display back showing `modeID`, or saying nothing about its mode when nil,
    /// as a display may after reconnecting.
    func reconnect(showing modeID: Int32?) {
        lock.withLock {
            snapshotsAway = 0
            shown = .mode(modeID)
        }
    }

    /// Brings the display back listing only CoreGraphics' placeholder, as a snapshot does
    /// for a display that dropped off while it was taken.
    func reconnectWithPlaceholder() {
        lock.withLock {
            snapshotsAway = 0
            shown = .placeholder
        }
    }

    private var isAway: Bool {
        lock.withLock { snapshotsAway != 0 }
    }

    func displays() -> [Display] {
        let (away, shown) = lock.withLock { () -> (Bool, Shown) in
            if snapshotsAway == 0, let back = snapshotsBack {
                if back > 0 {
                    snapshotsBack = back - 1
                } else {
                    snapshotsBack = nil
                    snapshotsAway = nil
                }
            }
            guard let remaining = snapshotsAway else { return (true, self.shown) }
            guard remaining > 0 else { return (false, self.shown) }
            snapshotsAway = remaining - 1
            return (true, self.shown)
        }
        return base.displays().compactMap { display in
            guard display.id == displayID else { return display }
            guard !away else { return nil }
            var display = display
            switch shown {
            case .asWrapped:
                break
            case .mode(let modeID):
                display.currentModeID = modeID
            case .placeholder:
                display.currentModeID = Self.placeholder.modeID
                display.modes = [Self.placeholder]
            }
            return display
        }
    }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        guard displayID == self.displayID else { return base.currentModeID(of: displayID) }
        let (away, shown) = lock.withLock { () -> (Bool, Shown) in
            (snapshotsAway != 0, self.shown)
        }
        if away { return Self.placeholder.modeID }
        switch shown {
        case .asWrapped: return base.currentModeID(of: displayID)
        case .mode(let modeID): return modeID
        case .placeholder: return Self.placeholder.modeID
        }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        guard displayID != self.displayID || !isAway else {
            throw ResoluteError.displayNotFound("id:\(displayID)")
        }
        if displayID == self.displayID, case .placeholder = lock.withLock({ shown }) {
            throw ResoluteError.modeNotFound("mode \(modeID)", suggestions: [])
        }
        try base.apply(modeID: modeID, to: displayID, scope: scope)
        guard displayID == self.displayID else { return }
        lock.withLock {
            shown = .asWrapped
            guard let drop, drop.modeID == modeID else { return }
            snapshotsAway = drop.snapshots
            self.drop = nil
        }
    }

    func setMirroring(_ enabled: Bool) throws {
        try base.setMirroring(enabled)
    }
}
