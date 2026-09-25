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

    @Test func leavesTheCurrentModeAlone() throws {
        let service = FakeDisplayService(display: TestData.fullHD())
        let outcome = try ModeSwitcher(service: service).apply(modeID: 1, to: 2, trial: true) { .revert }
        #expect(outcome == .alreadyCurrent)
        #expect(service.calls.isEmpty)
    }
}
