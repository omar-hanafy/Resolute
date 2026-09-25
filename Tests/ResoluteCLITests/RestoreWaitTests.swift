import CoreGraphics
import Foundation
import ResoluteKit
import Testing
@testable import resolute

/// A display that cannot show a hidden mode may lose its link during the prompt and
/// reconnect; `set` waits for it before undoing the trial.
@Suite struct RestoreWaitTests {
    let arguments = ["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"]
    let waiting = "DELL P2419H went away. Waiting for it to come back to restore the previous mode…"

    /// Runs `arguments` as the command line would against `service`, answering the prompt
    /// with `answer` and waiting at most a fifth of a second for a display to come back.
    func run(
        _ arguments: [String],
        on service: ReconnectingDisplays,
        answering answer: @escaping @Sendable () -> ModeSwitcher.Decision
    ) async -> (transcript: Transcript, message: String?, code: Int32) {
        let transcript = Transcript()
        var context = transcript.context(service: service, isRoot: false, decision: .revert)
        context.confirmHiddenMode = answer
        context.restoreTimeout = 0.2
        context.restorePollInterval = 0.001
        let result = await ResoluteCommand.execute(arguments, in: context)
        return (transcript, result.message, result.code)
    }

    /// The monitor, which goes away while the person is asked, and comes back as `setUp`
    /// arranges.
    func monitor(currentModeID: Int32 = 1, _ setUp: (ReconnectingDisplays) -> Void = { _ in }) -> (FakeDisplays, ReconnectingDisplays) {
        var display = Sample.monitor
        display.currentModeID = currentModeID
        let base = FakeDisplays([display])
        let service = ReconnectingDisplays(base, displayID: 2)
        setUp(service)
        return (base, service)
    }

    @Test func waitsForTheDisplayAndPutsThePreviousModeBack() async {
        let (base, service) = monitor()
        let result = await run(arguments, on: service) {
            service.disconnect(forSnapshots: 3)
            return .revert
        }
        #expect(result.code == 0)
        #expect(result.transcript.errors == waiting)
        #expect(result.transcript.output == "DELL P2419H is back. Restored the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
        #expect(base.changes == [
            .init(displayID: 2, modeID: 90, scope: .session), .init(displayID: 2, modeID: 1, scope: .session),
        ])
    }

    @Test func givesTheWayBackWhenTheDisplayDoesNotReturn() async {
        let (base, service) = monitor()
        let result = await run(arguments, on: service) {
            service.disconnect()
            return .revert
        }
        #expect(result.code == 1)
        #expect(result.message == """
            Error: DELL P2419H did not come back in time, so its previous mode was not restored. \
            The previous mode comes back when you log out, or run `resolute set --default` once the display is back.
            """)
        #expect(result.transcript.errors == waiting)
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    /// Only the mode on trial is undone.
    @Test func leavesADisplayThatCameBackInThePreviousModeAlone() async {
        let (base, service) = monitor()
        let result = await run(arguments, on: service) {
            service.disconnect(forSnapshots: 3, returningIn: 1)
            return .revert
        }
        #expect(result.code == 0)
        #expect(result.transcript.output == "DELL P2419H is back with the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    /// A display that has only just come back may not take a mode yet.
    @Test func triesAgainWhenTheReturningDisplayRefusesAtFirst() async {
        let (base, service) = monitor { $0.refuse(modeID: 1, times: 2) }
        let result = await run(arguments, on: service) {
            service.disconnect(forSnapshots: 3)
            return .revert
        }
        #expect(result.code == 0)
        #expect(result.transcript.output == "DELL P2419H is back. Restored the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
        #expect(base.changes.last == .init(displayID: 2, modeID: 1, scope: .session))
    }

    @Test func explainsARestoreTheReturningDisplayKeepsRefusing() async {
        let (_, service) = monitor { $0.refuse(modeID: 1) }
        let result = await run(arguments, on: service) {
            service.disconnect(forSnapshots: 3)
            return .revert
        }
        #expect(result.code == 1)
        #expect(result.message == """
            Error: The previous mode of DELL P2419H could not be restored. \
            It comes back when you log out, or run `resolute set --default`.
            """)
    }

    @Test func saysWhenTheDefaultModeCameBackInstead() async {
        let (_, service) = monitor(currentModeID: 2) { $0.refuse(modeID: 2) }
        let result = await run(arguments, on: service) {
            service.disconnect(forSnapshots: 3)
            return .revert
        }
        #expect(result.code == 0)
        #expect(result.transcript.output == "DELL P2419H is back. Restored its default mode: 1920 × 1080 @ 60 Hz, mode 1.")
    }

    /// A mode that never showed is an error whether or not the display went away, but only
    /// once the previous mode is back.
    @Test func reportsAModeThatNeverShowedOnceTheDisplayIsBack() async {
        // Away for the half second the switch is checked, and a little longer.
        let (base, service) = monitor { $0.disconnect(whenSwitchedTo: 90, forSnapshots: 12) }
        let result = await run(arguments, on: service) { .keep }
        #expect(result.code == 1)
        #expect(result.message
            == "Error: DELL P2419H did not switch to that mode, so it was left as it was. The display may not support the mode.")
        #expect(result.transcript.errors == waiting)
        #expect(base.changes == [
            .init(displayID: 2, modeID: 90, scope: .session), .init(displayID: 2, modeID: 1, scope: .session),
        ])
    }

    @Test func saysAKeptModeWasNotSavedWhenTheDisplayWentAway() async {
        let (base, service) = monitor()
        let result = await run(arguments, on: service) {
            service.disconnect()
            return .keep
        }
        #expect(result.code == 1)
        #expect(result.message == """
            Error: DELL P2419H went away before the new mode could be saved, so it was not saved. \
            If the display comes back in that mode, it lasts until you log out.
            """)
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    /// --session keeps a confirmed mode without saving it, so there is nothing to fail,
    /// but the mode can no longer be checked.
    @Test func saysWhenADisplayKeptForTheSessionWentAway() async {
        let (base, service) = monitor()
        let result = await run(arguments + ["--session"], on: service) {
            service.disconnect()
            return .keep
        }
        #expect(result.code == 0)
        #expect(result.transcript.errors == "warning: DELL P2419H went away, so its new mode could not be checked.")
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    @Test func revertsStraightAwayWhileTheDisplayStays() async {
        let (_, service) = monitor()
        let result = await run(arguments, on: service) { .revert }
        #expect(result.code == 0)
        #expect(result.transcript.errors.isEmpty)
        #expect(result.transcript.output == "Kept the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
    }
}

/// Lets one display of another service drop off and come back, as a display does when it
/// loses its link to a mode it cannot show. While away it is missing from snapshots,
/// reports no mode and cannot be switched, like a display that is not online.
final class ReconnectingDisplays: DisplayControlling, @unchecked Sendable {
    private let base: any DisplayControlling
    private let displayID: CGDirectDisplayID
    private let lock = NSLock()
    /// Snapshots the display still misses; nil while it is away for good.
    private var snapshotsAway: Int? = 0
    /// The mode it reports once back, until it is switched; nil for what the base reports.
    private var returningModeID: Int32?
    private var drop: (modeID: Int32, snapshots: Int?)?
    /// Modes it refuses, and how many more times; nil for every time.
    private var refusals: [Int32: Int?] = [:]

    init(_ base: any DisplayControlling, displayID: CGDirectDisplayID) {
        self.base = base
        self.displayID = displayID
    }

    /// Takes the display away for the next `snapshots` snapshots, or for good, and brings
    /// it back reporting `returningIn` when given.
    func disconnect(forSnapshots snapshots: Int? = nil, returningIn modeID: Int32? = nil) {
        lock.withLock {
            snapshotsAway = snapshots
            returningModeID = modeID
        }
    }

    /// Takes the display away as soon as it switches to `modeID`.
    func disconnect(whenSwitchedTo modeID: Int32, forSnapshots snapshots: Int? = nil) {
        lock.withLock { drop = (modeID, snapshots) }
    }

    /// Makes switching the display to `modeID` fail the next `times` times, or always.
    func refuse(modeID: Int32, times: Int? = nil) {
        lock.withLock { refusals[modeID] = .some(times) }
    }

    private var isAway: Bool {
        lock.withLock { snapshotsAway != 0 }
    }

    func displays() -> [Display] {
        let (away, returning) = lock.withLock { () -> (Bool, Int32?) in
            guard let remaining = snapshotsAway else { return (true, nil) }
            guard remaining > 0 else { return (false, returningModeID) }
            snapshotsAway = remaining - 1
            return (true, nil)
        }
        return base.displays().compactMap { display in
            guard display.id == displayID else { return display }
            guard !away else { return nil }
            var display = display
            if let returning { display.currentModeID = returning }
            return display
        }
    }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        guard displayID == self.displayID else { return base.currentModeID(of: displayID) }
        let (away, returning) = lock.withLock { (snapshotsAway != 0, returningModeID) }
        if away { return nil }
        return returning ?? base.currentModeID(of: displayID)
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        guard displayID == self.displayID else { return try base.apply(modeID: modeID, to: displayID, scope: scope) }
        guard !isAway else { throw ResoluteError.displayNotFound("id:\(displayID)") }
        let refused = lock.withLock { () -> Bool in
            guard let remaining = refusals[modeID] else { return false }
            if let remaining, remaining > 1 {
                refusals[modeID] = .some(remaining - 1)
            } else if remaining != nil {
                refusals.removeValue(forKey: modeID)
            }
            return true
        }
        guard !refused else { throw ResoluteError.coreGraphics(code: 1001, operation: "select the display mode") }
        try base.apply(modeID: modeID, to: displayID, scope: scope)
        lock.withLock {
            returningModeID = nil
            guard let drop, drop.modeID == modeID else { return }
            snapshotsAway = drop.snapshots
            self.drop = nil
        }
    }

    func setMirroring(_ enabled: Bool) throws {
        try base.setMirroring(enabled)
    }
}
