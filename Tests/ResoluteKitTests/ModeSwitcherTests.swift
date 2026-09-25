import Testing
@testable import ResoluteKit

@Suite struct ModeSwitcherTests {
    typealias Call = FakeDisplayService.Call

    @Test func savesListedModesStraightAway() throws {
        let service = FakeDisplayService(display: TestData.fullHD())
        var asked = false
        let outcome = try ModeSwitcher(service: service).apply(modeID: 2, to: 2, trial: false) {
            asked = true
            return .keep
        }
        #expect(outcome == .applied)
        #expect(!asked)
        #expect(service.calls == [Call(modeID: 2, scope: .permanent)])
    }

    @Test func keepsAConfirmedTrial() throws {
        let service = FakeDisplayService(display: TestData.fullHD())
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .keep }
        #expect(outcome == .kept)
        #expect(service.calls == [Call(modeID: 90, scope: .session), Call(modeID: 90, scope: .permanent)])
    }

    @Test func leavesATrialForTheSessionWhenAsked() throws {
        let service = FakeDisplayService(display: TestData.fullHD())
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .keepForSession }
        #expect(outcome == .keptForSession)
        #expect(service.calls == [Call(modeID: 90, scope: .session)])
    }

    @Test func revertsAnUnconfirmedTrial() throws {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 2))
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .revert }
        #expect(outcome == .reverted(to: 2))
        #expect(service.calls == [Call(modeID: 90, scope: .session), Call(modeID: 2, scope: .session)])
    }

    @Test func takesThePreviousModeFromTheFullSnapshot() throws {
        // CoreGraphics does not report the hidden mode in use; the snapshot does.
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 91), reportsCurrentMode: false)
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .revert }
        #expect(outcome == .reverted(to: 91))
    }

    @Test func fallsBackToTheDefaultModeWhenThePreviousOneFails() throws {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [2])
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .revert }
        #expect(outcome == .reverted(to: 1))
    }

    @Test func explainsWhenNothingCanBeRestored() throws {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [1, 2])
        #expect(throws: ResoluteError.revertFailed(display: "Full HD Monitor")) {
            try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .revert }
        }
    }

    @Test func doesNotAskAboutAModeThatNeverApplied() {
        let service = FakeDisplayService(display: TestData.fullHD(), ignoring: [90])
        var asked = false
        do {
            _ = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) {
                asked = true
                return .keep
            }
            Issue.record("expected the switch to be reported as not applied")
        } catch {
            #expect(error as? ResoluteError == .modeNotApplied(display: "Full HD Monitor"))
        }
        #expect(!asked)
        // Put back in case the switch lands late; if it never happened this changes nothing.
        #expect(service.calls == [Call(modeID: 90, scope: .session), Call(modeID: 1, scope: .session)])
    }

    /// CoreGraphics reports its own failures for listed modes, so a session trial of one is
    /// not second-guessed; only hidden modes, switched through SkyLight, are checked.
    @Test func leavesListedModesToCoreGraphics() throws {
        let service = FakeDisplayService(display: TestData.fullHD(), ignoring: [2])
        let outcome = try ModeSwitcher(service: service).apply(modeID: 2, to: 2, trial: true) { .keepForSession }
        #expect(outcome == .keptForSession)
        #expect(service.calls == [Call(modeID: 2, scope: .session)])
    }

    /// The live tests run a listed refresh rate through the check hidden modes get, since
    /// the development Mac has no hidden modes.
    @Test func checksAListedModeWhenAskedTo() {
        let service = FakeDisplayService(display: TestData.fullHD(), ignoring: [2])
        var switcher = ModeSwitcher(service: service)
        switcher.verifiesListedModes = true
        #expect(throws: ResoluteError.modeNotApplied(display: "Full HD Monitor")) {
            try switcher.apply(modeID: 2, to: 2, trial: true) { .keepForSession }
        }
        #expect(service.calls == [Call(modeID: 2, scope: .session), Call(modeID: 1, scope: .session)])
    }

    /// The live tests try modes for the app only, so CoreGraphics undoes a trial when the
    /// test process ends, even if it crashes.
    @Test func triesAndPutsBackForTheScopeAskedFor() throws {
        let service = FakeDisplayService(display: TestData.fullHD())
        var switcher = ModeSwitcher(service: service)
        switcher.trialScope = .app
        #expect(try switcher.apply(modeID: 90, to: 2, trial: true) { .revert } == .reverted(to: 1))
        #expect(service.calls == [Call(modeID: 90, scope: .app), Call(modeID: 1, scope: .app)])
    }

    @Test func fallsBackToTheDefaultModeWhenANeverAppliedModeCannotBeUndone() {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [2], ignoring: [90])
        #expect(throws: ResoluteError.modeNotApplied(display: "Full HD Monitor")) {
            try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .keep }
        }
        #expect(service.calls == [Call(modeID: 90, scope: .session), Call(modeID: 1, scope: .session)])
    }

    @Test func explainsWhenANeverAppliedModeLeavesNothingToRestore() {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [1, 2], ignoring: [90])
        #expect(throws: ResoluteError.revertFailed(display: "Full HD Monitor")) {
            try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .keep }
        }
    }

    @Test func waitsForADisplayThatReportsTheNewModeLate() throws {
        let service = FakeDisplayService(display: TestData.fullHD(), staleSnapshotsAfterASwitch: 3)
        _ = service.displays()  // the snapshot taken before the switch is current
        var asked = false
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) {
            asked = true
            return .keep
        }
        #expect(asked)
        #expect(outcome == .kept)
    }

    @Test func leavesTheCurrentModeAlone() throws {
        let service = FakeDisplayService(display: TestData.fullHD())
        let outcome = try ModeSwitcher(service: service).apply(modeID: 1, to: 2, trial: true) { .revert }
        #expect(outcome == .alreadyCurrent)
        #expect(service.calls.isEmpty)
    }
}

/// A display that cannot show a mode may lose its link during the countdown and
/// reconnect, possibly still in the mode on trial.
@Suite struct DisplayThatGoesAwayTests {
    typealias Call = FakeDisplayService.Call

    let base = FakeDisplayService(display: TestData.fullHD(currentModeID: 2))
    let service: ReconnectingDisplays
    /// Mode 2 was in use before the trial; mode 1 is the display's default.
    let pending = ModeSwitcher.PendingRestore(displayID: 2, displayName: "Full HD Monitor", modeID: 2, fallbackModeID: 1)

    init() {
        service = ReconnectingDisplays(base, displayID: 2)
    }

    @Test func putsThePreviousModeBackWhenTheDisplayReturns() throws {
        let switcher = ModeSwitcher(service: service)
        let outcome = try switcher.apply(modeID: 90, to: 2, trial: true) {
            service.disconnect()
            return .revert
        }
        #expect(outcome == .restorePending(pending))
        #expect(try switcher.finish(pending) == .waiting)
        service.reconnect()
        #expect(try switcher.finish(pending) == .restored(to: 2))
        #expect(base.calls == [Call(modeID: 90, scope: .session), Call(modeID: 2, scope: .session)])
    }

    @Test func waitsWithoutChangingAnythingWhileTheDisplayStaysAway() throws {
        let switcher = ModeSwitcher(service: service)
        let outcome = try switcher.apply(modeID: 90, to: 2, trial: true) {
            service.disconnect()
            return .revert
        }
        #expect(outcome == .restorePending(pending))
        for _ in 1...3 {
            #expect(try switcher.finish(pending) == .waiting)
        }
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    /// A display that drops off right after the switch never reports the mode, so the
    /// check fails; putting the previous mode back then waits for the display too.
    @Test func putsThePreviousModeBackAfterAModeThatNeverShowed() throws {
        service.disconnect(whenSwitchedTo: 90)
        let switcher = ModeSwitcher(service: service)
        var asked = false
        let outcome = try switcher.apply(modeID: 90, to: 2, trial: true) {
            asked = true
            return .keep
        }
        #expect(!asked)
        #expect(outcome == .restorePending(pending))
        service.reconnect()
        #expect(try switcher.finish(pending) == .restored(to: 2))
    }

    @Test func fallsBackToTheDefaultModeWhenTheReturningDisplayRefusesThePreviousOne() throws {
        let refusing = FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [2])
        let service = ReconnectingDisplays(refusing, displayID: 2)
        let switcher = ModeSwitcher(service: service)
        _ = try switcher.apply(modeID: 90, to: 2, trial: true) {
            service.disconnect(forSnapshots: 1)
            return .revert
        }
        #expect(try switcher.finish(pending) == .restored(to: 1))
    }

    @Test func explainsWhenTheReturningDisplayTakesNoModeBack() throws {
        let refusing = FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [1, 2])
        let service = ReconnectingDisplays(refusing, displayID: 2)
        let switcher = ModeSwitcher(service: service)
        _ = try switcher.apply(modeID: 90, to: 2, trial: true) {
            service.disconnect(forSnapshots: 1)
            return .revert
        }
        #expect(throws: ResoluteError.revertFailed(display: "Full HD Monitor")) {
            try switcher.finish(pending)
        }
    }

    /// Nothing will save the mode later, so the person hears about it now.
    @Test func saysAKeptModeWasNotSavedWhenTheDisplayWentAway() throws {
        let switcher = ModeSwitcher(service: service)
        #expect(throws: ResoluteError.displayWentAway(display: "Full HD Monitor")) {
            try switcher.apply(modeID: 90, to: 2, trial: true) {
                service.disconnect()
                return .keep
            }
        }
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    @Test func revertsStraightAwayWhenTheDisplayStays() throws {
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .revert }
        #expect(outcome == .reverted(to: 2))
        #expect(base.calls == [Call(modeID: 90, scope: .session), Call(modeID: 2, scope: .session)])
    }
}
