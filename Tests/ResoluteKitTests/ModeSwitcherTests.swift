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
