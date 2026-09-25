import CoreGraphics
import Foundation
@testable import ResoluteKit

/// Lets one display of another service drop off and come back, as a display does when it
/// loses its link to a mode it cannot show. While away it is missing from snapshots,
/// reports no mode and cannot be switched, like a display that is not online.
final class ReconnectingDisplays: DisplayControlling, @unchecked Sendable {
    /// Which mode the display says it shows.
    private enum Shown {
        /// Whatever the wrapped service says.
        case asWrapped
        /// This mode, or none, until the display is switched.
        case mode(Int32?)
    }

    private let base: any DisplayControlling
    private let displayID: CGDirectDisplayID
    private let lock = NSLock()
    /// Snapshots the display still misses; nil while it is away until `reconnect()`.
    private var snapshotsAway: Int? = 0
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

    func reconnect() {
        lock.withLock { snapshotsAway = 0 }
    }

    /// Brings the display back showing `modeID`, or saying nothing about its mode when nil,
    /// as a display may after reconnecting.
    func reconnect(showing modeID: Int32?) {
        lock.withLock {
            snapshotsAway = 0
            shown = .mode(modeID)
        }
    }

    private var isAway: Bool {
        lock.withLock { snapshotsAway != 0 }
    }

    func displays() -> [Display] {
        let (away, shown) = lock.withLock { () -> (Bool, Shown) in
            guard let remaining = snapshotsAway else { return (true, shown) }
            guard remaining > 0 else { return (false, shown) }
            snapshotsAway = remaining - 1
            return (true, shown)
        }
        return base.displays().compactMap { display in
            guard display.id == displayID else { return display }
            guard !away else { return nil }
            guard case .mode(let modeID) = shown else { return display }
            var display = display
            display.currentModeID = modeID
            return display
        }
    }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        guard displayID == self.displayID else { return base.currentModeID(of: displayID) }
        let (away, shown) = lock.withLock { (snapshotsAway != 0, shown) }
        if away { return nil }
        guard case .mode(let modeID) = shown else { return base.currentModeID(of: displayID) }
        return modeID
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        guard displayID != self.displayID || !isAway else {
            throw ResoluteError.displayNotFound("id:\(displayID)")
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
