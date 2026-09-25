import CoreGraphics
import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// A monitor with a hidden mode that can drop off and come back, as one does when it loses
/// its link to a mode it cannot show. Records every switch.
final class DroppingMonitor: DisplayControlling, @unchecked Sendable {
    struct Change: Equatable {
        var modeID: Int32
        var scope: ConfigurationScope
    }

    private let lock = NSLock()
    private var display = Display(
        id: 2, name: "DELL P2419H", currentModeID: 1,
        modes: [
            DisplayMode(modeID: 1, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60, ioFlags: 0x7),
            DisplayMode(modeID: 3, width: 1280, height: 720, pixelWidth: 1280, pixelHeight: 720, refreshRate: 60, ioFlags: 0x3),
            DisplayMode(
                modeID: 90, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 75,
                ioFlags: 0x1, origin: .hidden
            ),
        ],
        privateModes: .trusted
    )
    private var isAway = false
    private let refused: Set<Int32>
    private var recorded: [Change] = []

    init(refusing refused: Set<Int32> = []) {
        self.refused = refused
    }

    var changes: [Change] { lock.withLock { recorded } }

    func goAway() { lock.withLock { isAway = true } }
    func comeBack() { lock.withLock { isAway = false } }

    func displays() -> [Display] { lock.withLock { isAway ? [] : [display] } }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        lock.withLock { isAway ? nil : display.currentModeID }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        try lock.withLock {
            guard !isAway else { throw ResoluteError.displayNotFound("id:\(displayID)") }
            guard !refused.contains(modeID) else {
                throw ResoluteError.coreGraphics(code: 1001, operation: "select the display mode")
            }
            recorded.append(Change(modeID: modeID, scope: scope))
            display.currentModeID = modeID
        }
    }

    func setMirroring(_ enabled: Bool) throws {}
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
    typealias Change = DroppingMonitor.Change

    let reports = Reports()
    let clock = TestClock()
    /// Mode 1 was in use before the trial, and it is also the default mode.
    let pending = ModeSwitcher.PendingRestore(displayID: 2, displayName: "DELL P2419H", modeID: 1, fallbackModeID: nil, trialModeID: 90)

    /// A coordinator that answers the countdown with `answer` and collects alerts.
    func coordinator(_ monitor: DroppingMonitor, answer: @escaping @MainActor () -> ModeSwitcher.Decision) -> ModeChangeCoordinator {
        let reports = reports
        let clock = clock
        return ModeChangeCoordinator(
            service: monitor,
            decide: answer,
            report: { reports.errors.append(($0 as? ResoluteError) ?? .cancelled) },
            now: { clock.now }
        )
    }

    @Test func putsThePreviousModeBackWhenTheDisplayReturns() {
        let monitor = DroppingMonitor()
        let coordinator = coordinator(monitor) {
            monitor.goAway()
            return .revert
        }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(coordinator.pendingRestores == [pending])
        coordinator.displaysDidChange()
        #expect(monitor.changes == [Change(modeID: 90, scope: .session)])

        monitor.comeBack()
        coordinator.displaysDidChange()
        #expect(monitor.changes == [Change(modeID: 90, scope: .session), Change(modeID: 1, scope: .session)])
        #expect(coordinator.pendingRestores.isEmpty)
        // Reconnecting is no reason for an alert.
        #expect(reports.errors.isEmpty)
    }

    @Test func givesUpOnADisplayThatStaysAwayForTwoMinutes() {
        let monitor = DroppingMonitor()
        let coordinator = coordinator(monitor) {
            monitor.goAway()
            return .revert
        }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        clock.now += .seconds(119)
        coordinator.giveUpOnExpiredRestores()
        #expect(coordinator.pendingRestores == [pending])

        clock.now += .seconds(1)
        coordinator.giveUpOnExpiredRestores()
        #expect(coordinator.pendingRestores.isEmpty)
        monitor.comeBack()
        coordinator.displaysDidChange()
        #expect(monitor.changes == [Change(modeID: 90, scope: .session)])
        #expect(reports.errors.isEmpty)
    }

    /// The timer may be late; a display that comes back after the deadline is left alone.
    @Test func leavesADisplayThatComesBackTooLateAlone() {
        let monitor = DroppingMonitor()
        let coordinator = coordinator(monitor) {
            monitor.goAway()
            return .revert
        }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(coordinator.pendingRestores == [pending])
        clock.now += .seconds(121)
        monitor.comeBack()
        coordinator.displaysDidChange()
        #expect(monitor.changes == [Change(modeID: 90, scope: .session)])
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(reports.errors.isEmpty)
    }

    @Test func revertsStraightAwayWhileTheDisplayStays() {
        let monitor = DroppingMonitor()
        let coordinator = coordinator(monitor) { .revert }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(monitor.changes == [Change(modeID: 90, scope: .session), Change(modeID: 1, scope: .session)])
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(reports.errors.isEmpty)
    }

    /// Nothing will save the mode later, so the person hears about it now.
    @Test func saysAKeptModeWasNotSavedWhenTheDisplayWentAway() {
        let monitor = DroppingMonitor()
        let coordinator = coordinator(monitor) {
            monitor.goAway()
            return .keep
        }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(reports.errors == [.displayWentAway(display: "DELL P2419H")])
        #expect(coordinator.pendingRestores.isEmpty)
        #expect(monitor.changes == [Change(modeID: 90, scope: .session)])
    }

    /// Once the person picks a mode for the display, the old one must not come back.
    @Test func dropsAWaitingRestoreWhenTheDisplayGetsANewMode() {
        let monitor = DroppingMonitor()
        let coordinator = coordinator(monitor) {
            monitor.goAway()
            return .revert
        }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(coordinator.pendingRestores == [pending])
        monitor.comeBack()
        coordinator.apply(modeID: 3, to: 2, needsConfirmation: false)
        coordinator.displaysDidChange()
        #expect(monitor.changes == [Change(modeID: 90, scope: .session), Change(modeID: 3, scope: .permanent)])
        #expect(coordinator.pendingRestores.isEmpty)
    }

    /// Once the display is back it is no longer reconnecting, so a failure is shown.
    @Test func reportsARestoreTheReturningDisplayRefuses() {
        let monitor = DroppingMonitor(refusing: [1])
        let coordinator = coordinator(monitor) {
            monitor.goAway()
            return .revert
        }
        coordinator.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(reports.errors.isEmpty)
        monitor.comeBack()
        coordinator.displaysDidChange()
        #expect(reports.errors == [.revertFailed(display: "DELL P2419H")])
        #expect(coordinator.pendingRestores.isEmpty)
    }
}
