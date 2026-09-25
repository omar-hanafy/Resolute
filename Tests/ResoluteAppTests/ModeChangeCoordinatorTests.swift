import CoreGraphics
import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// A built-in display (1) and a monitor (2), each with a hidden mode. A display can drop
/// off and come back, as one does when it loses its link to a mode it cannot show, and
/// can refuse modes. Records every switch.
final class ReconnectingDisplays: DisplayControlling, @unchecked Sendable {
    struct Change: Equatable {
        var displayID: CGDirectDisplayID
        var modeID: Int32
        var scope: ConfigurationScope
    }

    private let lock = NSLock()
    private var list = [
        Display(
            id: 1, name: "Built-in Retina Display", isBuiltin: true, isMain: true, currentModeID: 51,
            modes: [
                ReconnectingDisplays.mode(51, flags: 0x7), ReconnectingDisplays.mode(52),
                ReconnectingDisplays.mode(91, origin: .hidden),
            ],
            privateModes: .trusted
        ),
        Display(
            id: 2, name: "DELL P2419H", currentModeID: 1,
            modes: [
                ReconnectingDisplays.mode(1, flags: 0x7), ReconnectingDisplays.mode(3),
                ReconnectingDisplays.mode(90, origin: .hidden),
            ],
            privateModes: .trusted
        ),
    ]
    private var away: Set<CGDirectDisplayID> = []
    private var dropsOnSwitchTo: Int32?
    private var recorded: [Change] = []
    private var refusedModes: Set<Int32> = []

    static func mode(_ id: Int32, flags: UInt32 = 0x3, origin: DisplayMode.Origin = .system) -> DisplayMode {
        DisplayMode(
            modeID: id, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080,
            refreshRate: Double(id), ioFlags: flags, origin: origin
        )
    }

    var changes: [Change] { lock.withLock { recorded } }

    /// Modes every display refuses.
    var refused: Set<Int32> {
        get { lock.withLock { refusedModes } }
        set { lock.withLock { refusedModes = newValue } }
    }

    func goAway(_ displayID: CGDirectDisplayID) {
        _ = lock.withLock { away.insert(displayID) }
    }

    /// Brings the display back, showing `modeID` when given.
    func comeBack(_ displayID: CGDirectDisplayID, showing modeID: Int32? = nil) {
        lock.withLock {
            away.remove(displayID)
            if let modeID, let index = list.firstIndex(where: { $0.id == displayID }) {
                list[index].currentModeID = modeID
            }
        }
    }

    /// Makes the monitor drop off as soon as it switches to `modeID`.
    func dropMonitor(whenSwitchedTo modeID: Int32) {
        lock.withLock { dropsOnSwitchTo = modeID }
    }

    func displays() -> [Display] { lock.withLock { list.filter { !away.contains($0.id) } } }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        lock.withLock { away.contains(displayID) ? nil : list.first { $0.id == displayID }?.currentModeID }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        try lock.withLock {
            guard !away.contains(displayID), let index = list.firstIndex(where: { $0.id == displayID }) else {
                throw ResoluteError.displayNotFound("id:\(displayID)")
            }
            guard !refusedModes.contains(modeID) else {
                throw ResoluteError.coreGraphics(code: 1001, operation: "select the display mode")
            }
            recorded.append(Change(displayID: displayID, modeID: modeID, scope: scope))
            list[index].currentModeID = modeID
            if displayID == 2, modeID == dropsOnSwitchTo {
                away.insert(2)
                dropsOnSwitchTo = nil
            }
        }
    }

    func setMirroring(_ enabled: Bool) throws {}
}

/// Answers the Keep/Revert countdown with what each test lines up, one answer per switch.
@MainActor
final class Countdown {
    var answers: [() -> ModeSwitcher.Decision] = []

    func answer() -> ModeSwitcher.Decision {
        answers.isEmpty ? .revert : answers.removeFirst()()
    }
}

/// What the coordinator would have shown in alerts.
@MainActor
final class Reports {
    var errors: [ResoluteError] = []
}

@MainActor
final class TestClock {
    var now = ContinuousClock.now
}

@MainActor
@Suite struct ModeChangeCoordinatorTests {
    typealias Change = ReconnectingDisplays.Change

    let displays = ReconnectingDisplays()
    let countdown = Countdown()
    let reports = Reports()
    let clock = TestClock()
    let coordinator: ModeChangeCoordinator
    /// Mode 1 was in use on the monitor before the trial of mode 90; it is also the default.
    let pending = ModeSwitcher.PendingRestore(displayID: 2, displayName: "DELL P2419H", modeID: 1, fallbackModeID: nil, trialModeID: 90)

    init() {
        let (countdown, reports, clock) = (countdown, reports, clock)
        coordinator = ModeChangeCoordinator(
            service: displays,
            decide: { countdown.answer() },
            report: { reports.errors.append(($0 as? ResoluteError) ?? .cancelled) },
            now: { clock.now }
        )
    }

    /// Tries `modeID` on the monitor, which drops off while the person is asked.
    func tryModeThatMakesTheMonitorGoAway(modeID: Int32 = 90) {
        let displays = displays
        countdown.answers.append {
            displays.goAway(2)
            return .revert
        }
        coordinator.apply(modeID: modeID, to: 2, needsConfirmation: true)
    }

    @Test func putsThePreviousModeBackWhenTheDisplayReturns() {
        tryModeThatMakesTheMonitorGoAway()
        #expect(coordinator.pendingRestores == [pending])
        coordinator.displaysDidChange()
        #expect(displays.changes == [Change(displayID: 2, modeID: 90, scope: .session)])

        displays.comeBack(2)
        coordinator.displaysDidChange()
        #expect(displays.changes == [
            Change(displayID: 2, modeID: 90, scope: .session), Change(displayID: 2, modeID: 1, scope: .session),
        ])
        #expect(coordinator.pendingRestores.isEmpty)
        // Reconnecting is no reason for an alert.
        #expect(reports.errors.isEmpty)
    }

    @Test func givesUpOnADisplayThatStaysAwayForTwoMinutes() {
        tryModeThatMakesTheMonitorGoAway()
        clock.now += .seconds(119)
        coordinator.expireRestores()
        #expect(coordinator.pendingRestores == [pending])

        clock.now += .seconds(1)
        coordinator.expireRestores()
        #expect(coordinator.pendingRestores.isEmpty)
        displays.comeBack(2)
        coordinator.displaysDidChange()
        #expect(displays.changes == [Change(displayID: 2, modeID: 90, scope: .session)])
        #expect(reports.errors.isEmpty)
    }

    /// A screen change can be missed, so the end of the wait is one last try.
    @Test func triesOnceMoreWhenTheWaitEnds() {
        tryModeThatMakesTheMonitorGoAway()
        displays.comeBack(2)
        clock.now += .seconds(120)
        coordinator.expireRestores()
        #expect(displays.changes.last == Change(displayID: 2, modeID: 1, scope: .session))
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(reports.errors.isEmpty)
    }

    /// Only the mode on trial is undone.
    @Test func leavesADisplayThatCameBackInAnotherModeAlone() {
        tryModeThatMakesTheMonitorGoAway()
        displays.comeBack(2, showing: 1)
        coordinator.displaysDidChange()
        #expect(displays.changes == [Change(displayID: 2, modeID: 90, scope: .session)])
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(reports.errors.isEmpty)
    }

    @Test func revertsStraightAwayWhileTheDisplayStays() {
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(displays.changes == [
            Change(displayID: 2, modeID: 90, scope: .session), Change(displayID: 2, modeID: 1, scope: .session),
        ])
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(reports.errors.isEmpty)
    }

    /// Nothing will save the mode later, so the person hears about it now.
    @Test func saysAKeptModeWasNotSavedWhenTheDisplayWentAway() {
        let displays = displays
        countdown.answers.append {
            displays.goAway(2)
            return .keep
        }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(reports.errors == [.displayWentAway(display: "DELL P2419H")])
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(displays.changes == [Change(displayID: 2, modeID: 90, scope: .session)])
    }

    /// Shown once the display is back, as it is when the display stays.
    @Test func reportsAModeThatNeverShowedOnceTheDisplayIsBack() {
        displays.dropMonitor(whenSwitchedTo: 90)
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(reports.errors.isEmpty)
        displays.comeBack(2)
        coordinator.displaysDidChange()
        #expect(displays.changes.last == Change(displayID: 2, modeID: 1, scope: .session))
        #expect(reports.errors == [.modeNotApplied(display: "DELL P2419H")])
    }

    /// A display that has only just come back may not take a mode yet; it is shown only
    /// when the wait ends, by which time it is not reconnecting any more.
    @Test func triesARefusedRestoreAgainAndReportsItOnlyWhenTheWaitEnds() {
        tryModeThatMakesTheMonitorGoAway()
        displays.refused = [1]
        displays.comeBack(2)
        coordinator.displaysDidChange()
        coordinator.displaysDidChange()
        #expect(coordinator.pendingRestores == [pending])
        #expect(reports.errors.isEmpty)

        clock.now += .seconds(120)
        coordinator.expireRestores()
        #expect(reports.errors == [.revertFailed(display: "DELL P2419H")])
        #expect(coordinator.pendingRestores.isEmpty)
    }

    /// A display that has only just come back may refuse a mode for a moment and then
    /// change nothing more, so a refused revert is tried again soon without waiting for
    /// another screen change.
    @Test func triesARefusedRestoreAgainSoonWithoutAnotherScreenChange() async throws {
        let (countdown, clock) = (countdown, clock)
        let coordinator = ModeChangeCoordinator(
            service: displays, decide: { countdown.answer() }, report: { _ in }, now: { clock.now },
            retryInterval: .milliseconds(10)
        )
        let displays = displays
        countdown.answers.append {
            displays.goAway(2)
            return .revert
        }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        displays.refused = [1]
        displays.comeBack(2)
        coordinator.displaysDidChange()
        #expect(coordinator.pendingRestores == [pending])
        displays.refused = []
        for _ in 0..<100 where !coordinator.pendingRestores.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(displays.changes.last == Change(displayID: 2, modeID: 1, scope: .session))
    }

    /// Choosing the mode on trial again, while its display refuses the previous one, is
    /// no answer to the countdown: the revert keeps waiting.
    @Test func keepsAWaitingRestoreWhenTheModeOnTrialIsChosenAgain() {
        tryModeThatMakesTheMonitorGoAway()
        displays.refused = [1]
        displays.comeBack(2)
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(coordinator.pendingRestores == [pending])
    }

    @Test func restoresOnALaterChangeOnceTheDisplayTakesTheMode() {
        tryModeThatMakesTheMonitorGoAway()
        displays.refused = [1]
        displays.comeBack(2)
        coordinator.displaysDidChange()
        displays.refused = []
        coordinator.displaysDidChange()
        #expect(displays.changes.last == Change(displayID: 2, modeID: 1, scope: .session))
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(reports.errors.isEmpty)
    }

    /// The new switch starts from the mode the person had, not from the one on trial, so
    /// undoing it cannot bring that one back.
    @Test func putsThePreviousModeBackBeforeANewSwitchOfTheSameDisplay() {
        tryModeThatMakesTheMonitorGoAway()
        displays.comeBack(2)
        coordinator.apply(modeID: 3, to: 2, needsConfirmation: false)
        #expect(displays.changes == [
            Change(displayID: 2, modeID: 90, scope: .session), Change(displayID: 2, modeID: 1, scope: .session),
            Change(displayID: 2, modeID: 3, scope: .permanent),
        ])
        #expect(coordinator.pendingRestores.isEmpty)
    }

    @Test func keepsAWaitingRestoreWhenANewSwitchOfTheDisplayFails() {
        tryModeThatMakesTheMonitorGoAway()
        coordinator.apply(modeID: 3, to: 2, needsConfirmation: false)
        #expect(coordinator.pendingRestores == [pending])
    }

    /// A display that refuses the previous mode is still in the one on trial, and undoing a
    /// new trial takes it back there, so the earlier revert keeps waiting.
    @Test func keepsARefusedRestoreWhenANewTrialOfTheDisplayIsUndone() {
        tryModeThatMakesTheMonitorGoAway()
        displays.refused = [1]
        displays.comeBack(2)
        coordinator.apply(modeID: 3, to: 2, needsConfirmation: true)
        #expect(displays.changes.last == Change(displayID: 2, modeID: 90, scope: .session))
        #expect(coordinator.pendingRestores == [pending])
        displays.refused = []
        coordinator.displaysDidChange()
        #expect(displays.changes.last == Change(displayID: 2, modeID: 1, scope: .session))
    }

    /// Undoing both trials means going back to the mode from before the first one.
    @Test func goesBackToTheModeFromBeforeBothTrialsWhenTheDisplayGoesAwayAgain() {
        tryModeThatMakesTheMonitorGoAway()
        displays.refused = [1]
        displays.comeBack(2)
        tryModeThatMakesTheMonitorGoAway(modeID: 3)
        #expect(coordinator.pendingRestores == [
            ModeSwitcher.PendingRestore(displayID: 2, displayName: "DELL P2419H", modeID: 1, fallbackModeID: nil, trialModeID: 3),
        ])
    }

    /// A mode chosen while a countdown is up is ignored, with the revert waiting for its
    /// display: either could open an alert or a second countdown over the first, whose
    /// timer would then end the wrong one.
    @Test func ignoresModesChosenWhileACountdownIsUp() {
        displays.dropMonitor(whenSwitchedTo: 90)
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        displays.comeBack(2)
        var seenDuringCountdown: [ResoluteError]?
        let (coordinator, reports) = (coordinator, reports)
        countdown.answers.append {
            coordinator.apply(modeID: 3, to: 2, needsConfirmation: false)
            seenDuringCountdown = reports.errors
            return .revert
        }
        coordinator.apply(modeID: 91, to: 1, needsConfirmation: true)
        #expect(seenDuringCountdown == [])
        #expect(!displays.changes.contains(Change(displayID: 2, modeID: 1, scope: .session)))
        #expect(!displays.changes.contains(Change(displayID: 2, modeID: 3, scope: .permanent)))
    }

    /// The countdown's timer ends the innermost modal alert, so no other alert may open
    /// while it is up: screen changes wait until the switch is over.
    @Test func showsNothingWhileAnotherDisplayIsOnTrial() {
        tryModeThatMakesTheMonitorGoAway()
        displays.refused = [1]
        displays.comeBack(2)
        clock.now += .seconds(121)
        var seenDuringCountdown: (errors: [ResoluteError], waiting: Int)?
        let (coordinator, reports) = (coordinator, reports)
        countdown.answers.append {
            coordinator.displaysDidChange()
            coordinator.expireRestores()
            seenDuringCountdown = (reports.errors, coordinator.pendingRestores.count)
            return .revert
        }
        coordinator.apply(modeID: 91, to: 1, needsConfirmation: true)
        #expect(seenDuringCountdown?.errors == [])
        #expect(seenDuringCountdown?.waiting == 1)
        #expect(reports.errors == [.revertFailed(display: "DELL P2419H")])
        #expect(coordinator.pendingRestores.isEmpty)
    }
}
