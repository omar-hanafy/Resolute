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
    let wayBack = "To restore DELL P2419H to 1920 × 1080 @ 60 Hz, reconnect it and run resolute displays, then resolute modes -d <current-display>. "
        + "Use the current display and mode IDs with resolute set --mode-id <current-mode> -d <current-display> --session. "
        + "Do not reuse IDs from before the reconnect; add --all and --allow-hidden if the previous mode was hidden."

    /// Runs `arguments` as the command line would against `service`, answering the prompt
    /// with `answer` and waiting at most a fifth of a second for a display to come back.
    func run(
        _ arguments: [String],
        on service: ReconnectingDisplays,
        interrupts: Interrupts = Interrupts(),
        answering answer: @escaping @Sendable () -> ModeSwitcher.Decision
    ) async -> (transcript: Transcript, message: String?, code: Int32) {
        let transcript = Transcript()
        var context = transcript.context(service: service, isRoot: false, decision: .revert)
        context.confirmHiddenMode = answer
        context.interrupts = interrupts
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

    @Test func describesThePreviousModeAfterReconnectRenumbersModes() throws {
        let original = Sample.monitor
        var returned = original
        returned.modes = original.modes.map { mode in
            var renumbered = mode
            renumbered.modeID += 100
            return renumbered
        }
        returned.currentModeID = 190
        let previous = try #require(original.currentMode)
        let trial = try #require(original.modes.first { $0.modeID == 90 })
        let pending = ModeSwitcher.PendingRestore(
            displayID: original.id, displayName: original.name, modeID: previous.modeID,
            fallbackModeID: previous.modeID, trialModeID: trial.modeID,
            displayIdentity: .init(original), previousMode: .init(previous),
            fallbackMode: .init(previous), trialMode: .init(trial)
        )
        let service = FakeDisplays([returned])
        let transcript = Transcript()
        let context = transcript.context(service: service, isRoot: false, decision: .revert)
        try SetCommand.finishRestore(pending, with: ModeSwitcher(service: service), on: original, in: context)
        #expect(transcript.output == "DELL P2419H is back. Restored the previous mode: 1920 × 1080 @ 60 Hz, mode 101.")
        #expect(service.changes.last?.modeID == 101)
        #expect(!transcript.errors.contains("went away"))
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
        // `set --default` would save the default mode over the one the person had.
        #expect(result.message == """
            Error: DELL P2419H did not come back in time, so its previous mode was not restored. \
            Logging out brings back the mode macOS saved for it.
            """)
        #expect(result.transcript.errors == waiting + "\n" + wayBack)
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
            Logging out brings back the mode macOS saved for it.
            """)
        #expect(result.transcript.errors == waiting + "\n" + wayBack)
    }

    /// The answer is about the mode on trial, so a display showing another one by then is
    /// neither saved over nor switched back.
    @Test func keepsNothingWhenTheDisplayShowsAnotherModeAtTheAnswer() async {
        let (base, service) = monitor()
        let result = await run(arguments, on: service) {
            service.disconnect(forSnapshots: 0, returningIn: 1)
            return .keep
        }
        #expect(result.code == 1)
        #expect(result.message
            == "Error: DELL P2419H was showing another mode when you answered, so the mode on trial was not kept.")
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    @Test func leavesAModeChosenElsewhereDuringThePromptAlone() async {
        let (base, service) = monitor()
        let result = await run(arguments, on: service) {
            service.disconnect(forSnapshots: 0, returningIn: 3)
            return .revert
        }
        #expect(result.code == 0)
        #expect(result.transcript.output == "DELL P2419H was showing 1280 × 720 @ 60 Hz, mode 3, when you answered, so it was left as it is.")
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    /// A refusal says nothing once the display has gone away again.
    @Test func saysTheDisplayDidNotComeBackWhenItLeftAgainAfterARefusal() async {
        let (_, service) = monitor { $0.refuse(modeID: 1, times: 1, thenGoAway: true) }
        let result = await run(arguments, on: service) {
            service.disconnect(forSnapshots: 3)
            return .revert
        }
        #expect(result.code == 1)
        #expect(result.message?.hasPrefix("Error: DELL P2419H did not come back in time") == true)
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
        // How the wait ended comes first, as it does when the mode showed.
        #expect(result.transcript.output == "DELL P2419H is back. Restored the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
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

    /// A session-only Keep still needs a connected display to verify the trial.
    @Test func saysWhenADisplayKeptForTheSessionWentAway() async {
        let (base, service) = monitor()
        let result = await run(arguments + ["--session"], on: service) {
            service.disconnect()
            return .keep
        }
        #expect(result.code == 1)
        #expect(result.message?.contains("went away") == true)
        #expect(result.transcript.output.isEmpty)
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    /// Ctrl-C ends the wait, after one last look, with the way back.
    @Test func stopsWaitingAtControlCAndSaysHowToPutThePreviousModeBack() async {
        let (base, service) = monitor()
        let interrupts = Interrupts()
        let result = await run(arguments, on: service, interrupts: interrupts) {
            service.disconnect()
            interrupts.interrupt()
            return .revert
        }
        #expect(result.code == 1)
        #expect(result.message == "Error: The operation was cancelled.")
        #expect(result.transcript.errors == waiting + "\n" + wayBack)
        #expect(base.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
    }

    /// A display back by the time Ctrl-C comes still gets its mode back.
    @Test func putsThePreviousModeBackWhenTheDisplayIsBackAtControlC() async {
        let (base, service) = monitor()
        let interrupts = Interrupts()
        let result = await run(arguments, on: service, interrupts: interrupts) {
            service.disconnect(forSnapshots: 2)
            interrupts.interrupt()
            return .revert
        }
        #expect(result.code == 0)
        #expect(result.transcript.output == "DELL P2419H is back. Restored the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
        #expect(base.changes.last == .init(displayID: 2, modeID: 1, scope: .session))
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
    private var goesAwayAfterRefusing = false
    /// Snapshots left before the display goes away for good, after a refusal.
    private var snapshotsUntilAway: Int?

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

    /// Makes switching the display to `modeID` fail the next `times` times, or always. With
    /// `thenGoAway`, the display stays for one more snapshot after a refusal and then goes
    /// away for good.
    func refuse(modeID: Int32, times: Int? = nil, thenGoAway: Bool = false) {
        lock.withLock {
            refusals[modeID] = .some(times)
            goesAwayAfterRefusing = thenGoAway
        }
    }

    private var isAway: Bool {
        lock.withLock { snapshotsAway != 0 }
    }

    func displays() -> [Display] {
        let (away, returning) = lock.withLock { () -> (Bool, Int32?) in
            if let left = snapshotsUntilAway {
                if left > 0 {
                    snapshotsUntilAway = left - 1
                } else {
                    snapshotsUntilAway = nil
                    snapshotsAway = nil
                }
            }
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
            if goesAwayAfterRefusing { snapshotsUntilAway = 1 }
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

/// Ctrl-C while a hidden mode is on trial is caught, since ending the process would leave
/// the mode until logout.
@Suite(.serialized) struct ControlCTests {
    @Test(arguments: [("y\n", true), (" YES \n", true), ("yikes\n", false), ("\n", false)])
    func readsOnlyAnExplicitAnswerFromThePolledDescriptor(answer: String, keeps: Bool) throws {
        var ends: [Int32] = [-1, -1]
        try #require(pipe(&ends) == 0)
        defer { ends.forEach { close($0) } }
        let bytes = Array(answer.utf8)
        #expect(bytes.withUnsafeBytes { write(ends[1], $0.baseAddress, $0.count) } == bytes.count)
        let originalFlags = fcntl(ends[0], F_GETFL)
        let result = SetCommand.askToKeep(seconds: 1, input: ends[0], isTerminal: true, interrupts: Interrupts())
        #expect(result == (keeps ? .keep : .revert))
        #expect(fcntl(ends[0], F_GETFL) == originalFlags)
    }

    @Test func partialInputCannotBlockTheRevertDeadline() throws {
        var ends: [Int32] = [-1, -1]
        try #require(pipe(&ends) == 0)
        defer { ends.forEach { close($0) } }
        var byte = UInt8(ascii: "y")
        #expect(write(ends[1], &byte, 1) == 1)
        let start = ContinuousClock.now
        let answer = SetCommand.askToKeep(seconds: 1, input: ends[0], isTerminal: true, interrupts: Interrupts())
        #expect(answer == .revert)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    @Test func noTerminalNeverKeepsATrial() {
        #expect(SetCommand.askToKeep(isTerminal: false) == .revert)
    }

    @Test(arguments: [SIGTERM, SIGHUP]) func terminationSignalsReachRecovery(number: Int32) {
        let event = Interrupts.process.catchingControlC {
            kill(getpid(), number)
            return Interrupts.process.wait(2)
        }
        #expect(event == .interrupted)
    }

    /// Ctrl-C wins even when a complete positive answer is already readable. Observing
    /// consumption of the interrupt proves the cause without timing task scheduling.
    @Test func answersThePromptWithRevert() throws {
        var ends: [Int32] = [-1, -1]
        try #require(pipe(&ends) == 0)
        defer { ends.forEach { close($0) } }
        let interrupts = Interrupts()
        let answer = Array("y\n".utf8)
        try #require(answer.withUnsafeBytes { write(ends[1], $0.baseAddress, $0.count) } == answer.count)
        interrupts.interrupt()
        #expect(SetCommand.askToKeep(seconds: 5, input: ends[0], isTerminal: true, interrupts: interrupts) == .revert)
        #expect(interrupts.wait(0) == .timedOut)
        // Recovery must start before the competing positive input is consumed.
        let flags = fcntl(ends[0], F_GETFL)
        try #require(flags >= 0 && fcntl(ends[0], F_SETFL, flags | O_NONBLOCK) == 0)
        var unread = [UInt8](repeating: 0, count: answer.count)
        #expect(read(ends[0], &unread, unread.count) == answer.count)
        #expect(unread == answer)
    }

    /// The real Ctrl-C reaches the pipe while it is caught. Like the terminal's, the signal
    /// goes to the process, and whichever thread takes it runs the handler.
    @Test func catchesTheSignalWhileATrialIsUnderWay() {
        let caught = Interrupts.process.catchingControlC { () -> Interrupts.Event in
            kill(getpid(), SIGINT)
            return Interrupts.process.wait(2)
        }
        #expect(caught == .interrupted)
    }
}
