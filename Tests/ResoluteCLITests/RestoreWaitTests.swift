import CoreGraphics
import Foundation
import ResoluteKit
import Testing
@testable import resolute

/// A display that cannot show a hidden mode may lose its link during the prompt and
/// reconnect; `set` waits for it before putting the previous mode back.
@Suite struct RestoreWaitTests {
    let base = FakeDisplays([Sample.monitor])
    let service: ReconnectingDisplays
    let arguments = ["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"]

    init() {
        service = ReconnectingDisplays(base, displayID: 2)
    }

    /// Runs `arguments` as the command line would, answering the prompt with `answer`,
    /// and waiting at most a fifth of a second for a display to come back.
    func run(
        _ arguments: [String], answering answer: @escaping @Sendable () -> ModeSwitcher.Decision
    ) async -> (transcript: Transcript, message: String?, code: Int32) {
        let transcript = Transcript()
        var context = transcript.context(service: service, isRoot: false, decision: .revert)
        context.confirmHiddenMode = answer
        context.restoreTimeout = 0.2
        context.restorePollInterval = 0.001
        let result = await ResoluteCommand.execute(arguments, in: context)
        return (transcript, result.message, result.code)
    }

    @Test func waitsForTheDisplayAndPutsThePreviousModeBack() async {
        let service = service
        let result = await run(arguments) {
            service.disconnect(forSnapshots: 3)
            return .revert
        }
        #expect(result.code == 0)
        #expect(result.transcript.errors
            == "DELL P2419H went away. Waiting for it to come back to restore the previous mode…")
        #expect(result.transcript.output == "DELL P2419H is back. Restored the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
        #expect(base.changes == [
            .init(displayID: 2, modeID: 90, scope: .session), .init(displayID: 2, modeID: 1, scope: .session),
        ])
    }

    @Test func givesTheWayBackWhenTheDisplayDoesNotReturn() async {
        let service = service
        let result = await run(arguments) {
            service.disconnect()
            return .revert
        }
        #expect(result.code == 1)
        #expect(result.message == """
            Error: DELL P2419H has not come back, so its previous mode could not be restored. \
            It comes back when you log out, or run `resolute set --default`.
            """)
        #expect(result.transcript.errors
            == "DELL P2419H went away. Waiting for it to come back to restore the previous mode…")
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    @Test func saysAKeptModeWasNotSavedWhenTheDisplayWentAway() async {
        let service = service
        let result = await run(arguments) {
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
        let service = service
        let result = await run(arguments + ["--session"]) {
            service.disconnect()
            return .keep
        }
        #expect(result.code == 0)
        #expect(result.transcript.errors == "warning: DELL P2419H went away, so its new mode could not be checked.")
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    @Test func revertsStraightAwayWhileTheDisplayStays() async {
        let result = await run(arguments) { .revert }
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

    init(_ base: any DisplayControlling, displayID: CGDirectDisplayID) {
        self.base = base
        self.displayID = displayID
    }

    /// Takes the display away for the next `snapshots` snapshots, or for good.
    func disconnect(forSnapshots snapshots: Int? = nil) {
        lock.withLock { snapshotsAway = snapshots }
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
    }

    func setMirroring(_ enabled: Bool) throws {
        try base.setMirroring(enabled)
    }
}
