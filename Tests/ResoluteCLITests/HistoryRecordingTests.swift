import Foundation
import ResoluteKit
import Testing
@testable import resolute

/// `set` and `mirror` add what they change to History, in the transcript's own support folder.
@Suite struct HistoryRecordingTests {
    func entries(_ transcript: Transcript) throws -> [HistoryEntry] {
        try HistoryStore(locations: transcript.support).entries()
    }

    func run(_ arguments: [String], on service: any DisplayControlling, decision: ModeSwitcher.Decision = .revert) async -> (Transcript, Int32) {
        let transcript = Transcript()
        let result = await ResoluteCommand.execute(arguments, in: transcript.context(service: service, isRoot: false, decision: decision))
        return (transcript, result.code)
    }

    @Test func recordsASwitchAsWhoeverRanTheCommand() async throws {
        let transcript = Transcript()
        var context = transcript.context(service: FakeDisplays([Sample.builtIn]), isRoot: false, decision: .revert)
        context.requester = { Requester(agent: "Claude Code", app: "Terminal") }
        #expect(await ResoluteCommand.execute(["set", "1496x967"], in: context).code == 0)
        let entry = try #require(try entries(transcript).first)
        #expect(try entries(transcript).count == 1)
        #expect(entry.outcome == .applied)
        #expect(entry.source == .agent(name: "Claude Code", app: "Terminal"))
        #expect(HistoryText.title(of: entry.change) == "Built-in Retina Display  1728 × 1117 → 1496 × 967")
    }

    @Test func recordsHowEachTrialEnded() async throws {
        let arguments = ["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"]
        // A kept hidden mode lasts until logout.
        let kept = try await resolute(arguments, service: FakeDisplays([Sample.monitor]), decision: .keep)
        #expect(try entries(kept).map(\.outcome) == [.keptForSession])
        #expect(try entries(kept).first?.isHiddenMode == true)
        let reverted = try await resolute(arguments, service: FakeDisplays([Sample.monitor]))
        #expect(try entries(reverted).map(\.outcome) == [.reverted(.unspecified)])
        let session = try await resolute(["set", "--refresh", "60", "--session"])
        #expect(try entries(session).map(\.outcome) == [.keptForSession])
    }

    @Test func recordsNothingWhenNothingChanges() async throws {
        #expect(try entries(try await resolute(["set", "--refresh", "60", "--dry-run"])).isEmpty)
        #expect(try entries(try await resolute(["set", "1728x1117"])).isEmpty)
        #expect(try entries(try await resolute(["mirror"], service: FakeDisplays([Sample.builtIn, Sample.monitor]))).isEmpty)
    }

    @Test func recordsAFailedSwitchButNotARefusal() async throws {
        let (failed, code) = await run(
            ["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"], on: FakeDisplays([Sample.monitor], ignoring: [90]), decision: .keep
        )
        #expect(code == 1)
        #expect(try entries(failed).map(\.outcome) == [.failed(message: ResoluteError.modeNotApplied(display: "DELL P2419H").localizedDescription)])
        let (refused, _) = await run(["set", "2560x1440", "-d", "dell"], on: FakeDisplays([Sample.monitor]))
        #expect(try entries(refused).isEmpty)
    }

    @Test func recordsATrialUndoneWhenTheDisplayCameBack() async throws {
        var display = Sample.monitor
        display.currentModeID = 1
        let service = ReconnectingDisplays(FakeDisplays([display]), displayID: 2)
        let transcript = Transcript()
        var context = transcript.context(service: service, isRoot: false, decision: .revert)
        context.confirmHiddenMode = {
            service.disconnect(forSnapshots: 3)
            return .revert
        }
        context.restoreTimeout = 0.2
        context.restorePollInterval = 0.001
        let result = await ResoluteCommand.execute(["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"], in: context)
        #expect(result.code == 0)
        #expect(try entries(transcript).map(\.outcome) == [.reverted(.displayWentDark)])
    }

    @Test func recordsAWaitThatGaveUpAsAFailure() async throws {
        var display = Sample.monitor
        display.currentModeID = 1
        let service = ReconnectingDisplays(FakeDisplays([display]), displayID: 2)
        let transcript = Transcript()
        var context = transcript.context(service: service, isRoot: false, decision: .revert)
        context.confirmHiddenMode = {
            service.disconnect()
            return .revert
        }
        context.restoreTimeout = 0.2
        context.restorePollInterval = 0.001
        let result = await ResoluteCommand.execute(["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"], in: context)
        #expect(result.code == 1)
        #expect(try entries(transcript).map(\.outcome) == [.failed(message: ResoluteError.displayDidNotReturn(display: "DELL P2419H").localizedDescription)])
    }

    @Test func recordsMirroringOnlyWhenItChanges() async throws {
        let service = FakeDisplays([Sample.builtIn, Sample.monitor])
        let transcript = Transcript()
        let context = transcript.context(service: service, isRoot: false, decision: .revert)
        for arguments in [["mirror", "on"], ["mirror", "on"], ["mirror", "off"]] {
            #expect(await ResoluteCommand.execute(arguments, in: context).code == 0)
        }
        #expect(try entries(transcript).map { HistoryText.title(of: $0.change) } == [
            "Mirroring off: Built-in + DELL P2419H", "Mirroring on: Built-in + DELL P2419H",
        ])
    }

    /// As the app records one: History lists a mirroring change that failed.
    @Test func recordsAMirroringChangeThatFailed() async throws {
        let service = FakeDisplays([Sample.builtIn, Sample.monitor])
        service.mirroringFailure = .coreGraphics(code: 1001, operation: "mirror the displays")
        let transcript = Transcript()
        let context = transcript.context(service: service, isRoot: false, decision: .revert)
        #expect(await ResoluteCommand.execute(["mirror", "on"], in: context).code != 0)
        let entry = try #require(try entries(transcript).first)
        #expect(HistoryText.title(of: entry.change) == "Mirroring on: Built-in + DELL P2419H")
        #expect(entry.outcome == .failed(message: ResoluteError.coreGraphics(code: 1001, operation: "mirror the displays").localizedDescription))
    }

    /// Mirroring a single display changes nothing, so nothing is recorded, as a preset that
    /// can't mirror records nothing.
    @Test func recordsNoMirroringOfASingleDisplay() async throws {
        let service = FakeDisplays([Sample.builtIn])
        service.mirroringFailure = .mirroringNeedsTwoDisplays
        let transcript = Transcript()
        let context = transcript.context(service: service, isRoot: false, decision: .revert)
        #expect(await ResoluteCommand.execute(["mirror", "on"], in: context).code != 0)
        #expect(try entries(transcript).isEmpty)
    }

    @Test func listsWhatItRecorded() async throws {
        let transcript = Transcript()
        let context = transcript.context(service: FakeDisplays([Sample.builtIn]), isRoot: false, decision: .revert)
        #expect(await ResoluteCommand.execute(["set", "1496x967"], in: context).code == 0)
        #expect(await ResoluteCommand.execute(["history"], in: context).code == 0)
        #expect(transcript.output.contains("Kept  Built-in Retina Display  1728 × 1117 → 1496 × 967"))
    }
}
