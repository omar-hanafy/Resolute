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

    @Test func fallsBackWhenThePreviousHiddenModeSilentlyFails() throws {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 91), ignoring: [91])
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .revert }
        #expect(outcome == .reverted(to: 1))
        #expect(service.calls == [
            Call(modeID: 90, scope: .session), Call(modeID: 91, scope: .session), Call(modeID: 1, scope: .session),
        ])
        #expect(service.currentModeID(of: 2) == 1)
    }

    @Test func retainsRecoveryWhenHiddenRestoreAndFallbackBothFail() throws {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 91), refusing: [1], ignoring: [91])
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .revert }
        guard case .restorePending(let pending) = outcome else {
            Issue.record("expected recovery to remain pending")
            return
        }
        #expect(pending.modeID == 91)
        #expect(pending.fallbackModeID == 1)
        #expect(service.currentModeID(of: 2) == 90)
    }

    @Test func retainsRecoveryWhenNothingCanBeRestoredImmediately() throws {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [1, 2])
        let switcher = ModeSwitcher(service: service)
        let outcome = try switcher.apply(modeID: 90, to: 2, trial: true) { .revert }
        guard case .restorePending(let pending) = outcome else {
            Issue.record("expected recovery to remain pending")
            return
        }
        #expect(pending.modeID == 2)
        #expect(pending.fallbackModeID == 1)
        #expect(throws: ResoluteError.revertFailed(display: "Full HD Monitor")) {
            try switcher.finish(pending)
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

    /// Listed modes also need a fresh check at confirmation: the display could have
    /// changed while the person was deciding.
    @Test func refusesToKeepAListedModeThatIsNotCurrent() throws {
        let service = FakeDisplayService(display: TestData.fullHD(), ignoring: [2])
        #expect(throws: ResoluteError.displayChangedDuringTrial(display: "Full HD Monitor")) {
            try ModeSwitcher(service: service).apply(modeID: 2, to: 2, trial: true) { .keepForSession }
        }
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

    @Test func retainsTheOriginalFailureWhenANeverAppliedModeCannotBeRestored() throws {
        let service = FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [1, 2], ignoring: [90])
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .keep }
        guard case .restorePending(let pending) = outcome else {
            Issue.record("expected recovery to remain pending")
            return
        }
        #expect(pending.failure == .modeNotApplied(display: "Full HD Monitor"))
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

    @Test func refusesATrialWithoutAKnownRecoveryMode() {
        var display = TestData.fullHD()
        display.currentModeID = nil
        display.modes.removeAll { $0.isDefault }
        let service = FakeDisplayService(display: display)
        #expect(throws: ResoluteError.usage(
            "Cannot try a mode on Full HD Monitor: no previous or default mode is available for recovery."
        )) {
            try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .keep }
        }
        #expect(service.calls.isEmpty)
    }

    @Test func refusesATrialWhoseTargetWasNotEnumerated() {
        let service = FakeDisplayService(display: TestData.fullHD())
        #expect(throws: ResoluteError.modeNotFound("mode 999", suggestions: [])) {
            try ModeSwitcher(service: service).apply(modeID: 999, to: 2, trial: true) { .keep }
        }
        #expect(service.calls.isEmpty)
    }
}

/// A display that cannot show a mode may lose its link during the countdown and
/// reconnect, possibly still in the mode on trial.
@Suite struct DisplayThatGoesAwayTests {
    typealias Call = FakeDisplayService.Call
    typealias PendingRestore = ModeSwitcher.PendingRestore

    let base = FakeDisplayService(display: TestData.fullHD(currentModeID: 2))
    let service: ReconnectingDisplays
    /// Mode 2 was in use before the trial of mode 90; mode 1 is the display's default.
    let pending: PendingRestore = {
        let display = TestData.fullHD(currentModeID: 2)
        return PendingRestore(
            displayID: 2, displayName: display.name, modeID: 2, fallbackModeID: 1, trialModeID: 90,
            displayIdentity: .init(display), previousMode: .init(display.modes[1]),
            fallbackMode: .init(display.modes[0]), trialMode: .init(display.modes[4])
        )
    }()

    init() {
        service = ReconnectingDisplays(base, displayID: 2)
    }

    /// Tries mode 90 on a display that goes away during the countdown.
    func tryModeThatGoesAway(on service: ReconnectingDisplays) throws -> ModeSwitcher.Outcome {
        try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) {
            service.disconnect()
            return .revert
        }
    }

    @Test func putsThePreviousModeBackWhenTheDisplayReturns() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        let switcher = ModeSwitcher(service: service)
        #expect(try switcher.finish(pending) == .waiting)
        service.reconnect()
        #expect(try switcher.finish(pending) == .restored(to: 2))
        #expect(base.calls == [Call(modeID: 90, scope: .session), Call(modeID: 2, scope: .session)])
    }

    @Test func waitsWithoutChangingAnythingWhileTheDisplayStaysAway() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        for _ in 1...3 {
            #expect(try ModeSwitcher(service: service).finish(pending) == .waiting)
        }
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    /// A display that drops off right after the switch never reports the mode, so the
    /// check fails; putting the previous mode back then waits for the display too, and
    /// the failure is kept to report once it is back.
    @Test func putsThePreviousModeBackAfterAModeThatNeverShowed() throws {
        service.disconnect(whenSwitchedTo: 90)
        let switcher = ModeSwitcher(service: service)
        var asked = false
        let outcome = try switcher.apply(modeID: 90, to: 2, trial: true) {
            asked = true
            return .keep
        }
        #expect(!asked)
        let notShown = PendingRestore(
            displayID: 2, displayName: "Full HD Monitor", modeID: 2, fallbackModeID: 1, trialModeID: 90,
            failure: .modeNotApplied(display: "Full HD Monitor"),
            displayIdentity: pending.displayIdentity, previousMode: pending.previousMode,
            fallbackMode: pending.fallbackMode, trialMode: pending.trialMode
        )
        #expect(outcome == .restorePending(notShown))
        service.reconnect()
        #expect(try switcher.finish(notShown) == .restored(to: 2))
    }

    /// Only the mode on trial is undone: a display back in another mode (its saved one,
    /// one chosen since, or another display given the same ID) is left as it is.
    @Test func leavesADisplayThatCameBackInAnotherModeAlone() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        service.reconnect(showing: 2)
        #expect(try ModeSwitcher(service: service).finish(pending) == .leftAlone(current: 2))
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    /// A display with a failing link may come back and drop off again at once; the
    /// placeholder mode CoreGraphics then reports must not pass for a mode chosen since.
    @Test func keepsWaitingForADisplayThatDropsOffAgainAtOnce() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        service.reconnect(forSnapshots: 1)
        #expect(try ModeSwitcher(service: service).finish(pending) == .waiting)
        service.reconnect()
        #expect(try ModeSwitcher(service: service).finish(pending) == .restored(to: 2))
    }

    /// A snapshot taken as the display dropped off lists only CoreGraphics' placeholder,
    /// which says nothing about the mode the display shows.
    @Test func doesNotTakeThePlaceholderForAModeChosenSince() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        service.reconnectWithPlaceholder()
        #expect(throws: ResoluteError.revertFailed(display: "Full HD Monitor")) {
            try ModeSwitcher(service: service).finish(pending)
        }
        service.reconnect(showing: 90)
        #expect(try ModeSwitcher(service: service).finish(pending) == .restored(to: 2))
    }

    /// When the display cannot say which mode it shows, it may still be the one on trial.
    @Test func putsTheModeBackWhenTheReturningDisplayCannotSayWhichModeItShows() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        service.reconnect(showing: nil)
        #expect(try ModeSwitcher(service: service).finish(pending) == .restored(to: 2))
    }

    @Test func fallsBackToTheDefaultModeWhenTheReturningDisplayRefusesThePreviousOne() throws {
        let service = ReconnectingDisplays(FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [2]), displayID: 2)
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        let switcher = ModeSwitcher(service: service)
        #expect(try switcher.finish(pending) == .waiting)
        service.reconnect()
        #expect(try switcher.finish(pending) == .restored(to: 1))
    }

    @Test func explainsWhenTheReturningDisplayTakesNoModeBack() throws {
        let service = ReconnectingDisplays(FakeDisplayService(display: TestData.fullHD(currentModeID: 2), refusing: [1, 2]), displayID: 2)
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        let switcher = ModeSwitcher(service: service)
        #expect(try switcher.finish(pending) == .waiting)
        service.reconnect()
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

    @Test func cannotKeepAModeForTheSessionAfterTheDisplayDisappears() {
        #expect(throws: ResoluteError.displayWentAway(display: "Full HD Monitor")) {
            try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) {
                service.disconnect()
                return .keepForSession
            }
        }
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    @Test(arguments: [ModeSwitcher.Decision.keep, .keepForSession, .revert])
    func leavesAnExternallyChangedListedTrialAlone(decision: ModeSwitcher.Decision) throws {
        let switcher = ModeSwitcher(service: service)
        let action = {
            try switcher.apply(modeID: 3, to: 2, trial: true) {
                service.reconnect(showing: 1)
                return decision
            }
        }
        if decision == .revert {
            #expect(try action() == .leftAlone(current: 1))
        } else {
            #expect(throws: ResoluteError.displayChangedDuringTrial(display: "Full HD Monitor"), performing: action)
        }
        #expect(base.calls == [Call(modeID: 3, scope: .session)])
    }

    @Test func neverTreatsAnOfflinePlaceholderAsTheCurrentMode() {
        service.disconnect()
        let switcher = ModeSwitcher(service: service)
        #expect(switcher.currentModeID(of: 2) == nil)
        #expect(throws: ResoluteError.displayNotFound("id:2")) {
            try switcher.apply(modeID: 0, to: 2, trial: false) { .keep }
        }
        #expect(base.calls.isEmpty)
    }

    /// The answer is about the mode on trial. A display that came back in another mode
    /// during the countdown, or was switched elsewhere, keeps what it shows: saving the
    /// mode on trial would switch it back to what may have made it drop off.
    @Test(arguments: [ModeSwitcher.Decision.keep, .keepForSession])
    func keepsNothingWhenTheDisplayShowsAnotherModeAtTheAnswer(decision: ModeSwitcher.Decision) throws {
        let switcher = ModeSwitcher(service: service)
        #expect(throws: ResoluteError.displayChangedDuringTrial(display: "Full HD Monitor")) {
            try switcher.apply(modeID: 90, to: 2, trial: true) {
                service.reconnect(showing: 2)
                return decision
            }
        }
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    /// Nor is a mode chosen elsewhere during the countdown undone.
    @Test func revertsNothingWhenTheDisplayShowsAnotherModeAtTheAnswer() throws {
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) {
            service.reconnect(showing: 3)
            return .revert
        }
        #expect(outcome == .leftAlone(current: 3))
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    @Test func revertsStraightAwayWhenTheDisplayStays() throws {
        let outcome = try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) { .revert }
        #expect(outcome == .reverted(to: 2))
        #expect(base.calls == [Call(modeID: 90, scope: .session), Call(modeID: 2, scope: .session)])
    }

    @Test func doesNotRestoreADifferentDisplayReusingTheSameIDAndModes() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        var replacement = TestData.fullHD(currentModeID: 90)
        replacement.serialNumber = 12345
        base.replaceDisplay(replacement)
        service.reconnect()
        #expect(try ModeSwitcher(service: service).finish(pending) == .waiting)
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    @Test func restoresTheSameSerialNumberAfterItsDisplayIDChanges() throws {
        var original = TestData.fullHD(currentModeID: 2)
        original.serialNumber = 12345
        base.replaceDisplay(original)
        let outcome = try tryModeThatGoesAway(on: service)
        guard case .restorePending(let pending) = outcome else {
            Issue.record("expected a pending restore")
            return
        }
        var returned = original
        returned.id = 22
        returned.currentModeID = 90
        base.replaceDisplay(returned)
        service.reconnect()
        #expect(try ModeSwitcher(service: service).finish(pending) == .restored(to: 2))
        #expect(base.appliedDisplayIDs == [2, 22])
        #expect(pending.displayID == 2) // caller bookkeeping retains its original key
    }

    @Test func cannotFollowADisplayIDChangeWithoutASerialNumber() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        base.replaceDisplay(TestData.fullHD(id: 22, currentModeID: 90))
        service.reconnect()
        #expect(try ModeSwitcher(service: service).finish(pending) == .waiting)
        #expect(base.appliedDisplayIDs == [2])
    }

    @Test func requiresAUniqueSerialMatchWhenTheDisplayIDChanges() {
        var original = TestData.fullHD(currentModeID: 2)
        original.serialNumber = 12345
        let bound = PendingRestore(
            displayID: original.id, displayName: original.name, modeID: 2, fallbackModeID: 1,
            trialModeID: 90, displayIdentity: .init(original)
        )
        var returned = original
        returned.id = 22
        var duplicate = returned
        duplicate.id = 23
        var replacement = original
        replacement.serialNumber = 67890
        #expect(bound.resolveDisplay(in: [returned])?.id == 22)
        #expect(bound.resolveDisplay(in: [replacement, returned])?.id == 22)
        #expect(bound.resolveDisplay(in: [returned, duplicate]) == nil)
    }

    @Test func resolvesUniqueRenumberedModesAfterReconnect() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        var reconnected = TestData.fullHD(currentModeID: 190)
        reconnected.modes = reconnected.modes.map { mode in
            var mode = mode
            mode.modeID += 100
            return mode
        }
        base.replaceDisplay(reconnected)
        service.reconnect()
        #expect(try ModeSwitcher(service: service).finish(pending) == .restored(to: 102))
        #expect(base.calls == [Call(modeID: 90, scope: .session), Call(modeID: 102, scope: .session)])
    }

    @Test func neverAppliesReusedIDsWithDifferentModeProperties() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        var reconnected = TestData.fullHD(currentModeID: 90)
        reconnected.modes[0].width += 1
        reconnected.modes[1].refreshRate = 100
        base.replaceDisplay(reconnected)
        service.reconnect()
        #expect(throws: ResoluteError.revertFailed(display: pending.displayName)) {
            try ModeSwitcher(service: service).finish(pending)
        }
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    @Test func refusesAmbiguousRenumberedModes() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        var reconnected = TestData.fullHD(currentModeID: 90)
        var duplicate = reconnected.modes[1]
        duplicate.modeID = 102
        reconnected.modes[1].modeID = 202
        reconnected.modes.append(duplicate)
        reconnected.modes.removeAll { $0.modeID == 1 } // no safe fallback remains
        base.replaceDisplay(reconnected)
        service.reconnect()
        #expect(throws: ResoluteError.revertFailed(display: pending.displayName)) {
            try ModeSwitcher(service: service).finish(pending)
        }
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    @Test func leavesAReusedTrialIDWithDifferentPropertiesAlone() throws {
        #expect(try tryModeThatGoesAway(on: service) == .restorePending(pending))
        var reconnected = TestData.fullHD(currentModeID: 90)
        reconnected.modes[4].refreshRate = 100
        base.replaceDisplay(reconnected)
        service.reconnect()
        #expect(try ModeSwitcher(service: service).finish(pending) == .leftAlone(current: 90))
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }

    @Test func cannotConfirmAReplacementDisplayWithTheSameIDs() {
        #expect(throws: ResoluteError.displayChangedDuringTrial(display: pending.displayName)) {
            try ModeSwitcher(service: service).apply(modeID: 90, to: 2, trial: true) {
                var replacement = TestData.fullHD(currentModeID: 90)
                replacement.productID += 1
                base.replaceDisplay(replacement)
                return .keep
            }
        }
        #expect(base.calls == [Call(modeID: 90, scope: .session)])
    }
}
