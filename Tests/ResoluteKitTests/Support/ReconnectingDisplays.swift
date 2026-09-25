import CoreGraphics
import Foundation
@testable import ResoluteKit

/// Lets one display of another service drop off and come back, as a display does when it
/// loses its link to a mode it cannot show. While away it is missing from snapshots,
/// reports no mode and cannot be switched, like a display that is not online.
final class ReconnectingDisplays: DisplayControlling, @unchecked Sendable {
    private let base: any DisplayControlling
    private let displayID: CGDirectDisplayID
    private let lock = NSLock()
    /// Snapshots the display still misses; nil while it is away until `reconnect()`.
    private var snapshotsAway: Int? = 0
    /// A switch that makes the display drop off.
    private var drop: (modeID: Int32, snapshots: Int?)?

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

    private var isAway: Bool {
        lock.withLock { snapshotsAway != 0 }
    }

    func displays() -> [Display] {
        let away = lock.withLock { () -> Bool in
            guard let remaining = snapshotsAway else { return true }
            guard remaining > 0 else { return false }
            snapshotsAway = remaining - 1
            return true
        }
        let list = base.displays()
        return away ? list.filter { $0.id != displayID } : list
    }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        displayID == self.displayID && isAway ? nil : base.currentModeID(of: displayID)
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        guard displayID != self.displayID || !isAway else {
            throw ResoluteError.displayNotFound("id:\(displayID)")
        }
        try base.apply(modeID: modeID, to: displayID, scope: scope)
        lock.withLock {
            guard let drop, drop.modeID == modeID else { return }
            snapshotsAway = drop.snapshots
            self.drop = nil
        }
    }

    func setMirroring(_ enabled: Bool) throws {
        try base.setMirroring(enabled)
    }
}
