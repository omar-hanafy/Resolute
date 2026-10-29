import AppKit
import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// Stands in for the dialog and the notices: records what would show, and lets a test answer
/// as the person would.
@MainActor
final class FakeTrialScreen {
    var shown: [TrialDialogModel] = []
    var closed = 0
    var outcomes: [(TrialOutcome, TrialQuestion)] = []
    var restored: [ConfirmHiddenModeRequest] = []
    var isAppTrialUp = false
    var allowsHiddenModes = true
    var trialSeconds = 15

    func requests(socket: URL = URL(filePath: "/tmp/unused.sock"), clock: TrialTestClock) -> AgentRequests {
        AgentRequests(
            socket: socket,
            trialSeconds: { self.trialSeconds },
            allowsHiddenModes: { self.allowsHiddenModes },
            isAppTrialUp: { self.isAppTrialUp },
            present: { model in
                self.shown.append(model)
                return { self.closed += 1 }
            },
            showOutcome: { self.outcomes.append(($0, $1)) },
            restore: { self.restored.append($0) },
            clock: { clock.read }
        )
    }

    /// The dialog once it is up.
    func dialog(_ index: Int = 0) async throws -> TrialDialogModel {
        let deadline = ContinuousClock.now + .seconds(30)
        while shown.count <= index, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return try #require(shown.count > index ? shown[index] : nil)
    }
}

/// Requests from `resolute`: the dialog they show, what each answer sends back, one at a
/// time, never over the app's own question, and closing when the command goes away. The
/// dialog is driven through its model; nothing is shown.
@MainActor
@Suite struct AgentRequestsTests {
    let screen = FakeTrialScreen()
    let clock = TrialTestClock()
    let request = ConfirmHiddenModeRequest(
        display: .init(name: "DELL U2723QE", id: 3, vendorID: 0x10AC, productID: 0x41BB, serialNumber: 0),
        mode: "2880 × 1620", modeID: 90, previousMode: "2560 × 1440", previousModeID: 1, trialSeconds: 8,
        requester: Requester(agent: "Claude Code", app: "Terminal")
    )

    @Test func asksOnTheDisplayNamingWhoAsked() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let answer = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        #expect(requests.isAsking)
        #expect(dialog.question.displayID == 3)
        #expect(dialog.question.requester == Requester(agent: "Claude Code", app: "Terminal"))
        #expect(dialog.total == 8)
        #expect(dialog.message.hasSuffix("It switches back to 2560 × 1440 in 8 seconds."))
        #expect(dialog.requesterNote == "Claude Code asked for this from Terminal. It can’t see your screen, so only you can keep it.")
        dialog.keep()
        #expect(await answer.value == .keptByPerson)
        #expect(!requests.isAsking)
        #expect(screen.closed == 1)
    }

    @Test func keepShowsKept() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let answer = Task { await requests.answer(request) }
        try await screen.dialog().keep()
        _ = await answer.value
        #expect(screen.outcomes.map(\.0) == [.kept])
        #expect(screen.outcomes.first?.1.mode == "2880 × 1620")
    }

    @Test func revertIsTheCommandsToDoAndShowsSwitchedBack() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let answer = Task { await requests.answer(request) }
        try await screen.dialog().revert()
        #expect(await answer.value == .revertedByPerson)
        #expect(screen.outcomes.map(\.0) == [.switchedBack])
    }

    /// The countdown of the length the command asked for; no notice, since nobody answered.
    @Test func noAnswerAfterTheRequestedTrial() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let answer = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        clock.advance(7.9)
        dialog.tick()
        #expect(dialog.answer == nil)
        clock.advance(0.1)
        dialog.tick()
        #expect(await answer.value == .noAnswer(after: 8))
        #expect(screen.outcomes.isEmpty)
    }

    /// A request that waited for the main thread counts down from when it arrived, as the
    /// command does, so the dialog never outlasts the command's wait.
    @Test func countsDownFromWhenTheRequestArrived() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let arrived = ContinuousClock.now - .seconds(3)
        let answer = Task { await requests.answer(request, arrived: arrived) }
        let dialog = try await screen.dialog()
        // Five seconds left, less however long the test took to get here.
        #expect(dialog.remaining <= 5)
        #expect(dialog.remaining > 3)
        #expect(dialog.total == 8)
        dialog.revert()
        _ = await answer.value
    }

    /// A Keep that arrives at the deadline is no keep.
    @Test func keepTooLateIsNoAnswer() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let answer = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        clock.advance(8)
        dialog.keep()
        #expect(await answer.value == .noAnswer(after: 8))
    }

    @Test func refusesASecondRequestWhileOneIsUp() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let first = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        let second = await requests.answer(request)
        #expect(second.answer == .revert)
        #expect(second.by == nil)
        #expect(second.reason == AgentRequests.Refusal.busy)
        #expect(screen.shown.count == 1)
        dialog.revert()
        _ = await first.value
        // Free again once the first is answered.
        let third = Task { await requests.answer(request) }
        try await screen.dialog(1).revert()
        #expect(await third.value == .revertedByPerson)
    }

    /// The other way round: while a request's dialog is up, the app starts no trial of its
    /// own, from the panel, the window or History's Undo; listed modes still switch.
    @Test func holdsTheAppsOwnTrialsWhileOneIsUp() async throws {
        let service = FakeDisplayService()
        let scratch = ScratchDefaults()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults),
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteAgentGuard-\(UUID().uuidString)")
        )
        let requests = screen.requests(clock: clock)
        model.agentRequests = requests
        let request = request
        let answer = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        let dell = FakeDisplayService.dell
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        model.apply(hidden, to: dell)
        #expect(service.changes.isEmpty)
        let listed = try #require(dell.modes.first { $0.origin == .system && $0.modeID != dell.currentModeID })
        model.apply(listed, to: dell)
        #expect(service.changes.map(\.modeID) == [listed.modeID])
        dialog.revert()
        _ = await answer.value
        model.apply(hidden, to: try #require(model.displays.first { $0.id == dell.id }))
        #expect(service.changes.count > 1)
    }

    @Test func neverShowsOverTheAppsOwnQuestion() async {
        screen.isAppTrialUp = true
        let requests = screen.requests(clock: clock)
        let response = await requests.answer(request)
        #expect(response.answer == .revert)
        #expect(response.reason == AgentRequests.Refusal.appTrial)
        #expect(screen.shown.isEmpty)
        #expect(!requests.isAsking)
    }

    /// The command dismissed the request or went away: the server cancels the handler, and
    /// the dialog closes without a notice.
    @Test func closesWhenTheRequestIsWithdrawn() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let answer = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        answer.cancel()
        let response = await answer.value
        #expect(response.answer == .revert)
        #expect(response.reason == AgentRequests.Refusal.withdrawn)
        #expect(dialog.answer == .dismissed)
        #expect(screen.closed == 1)
        #expect(screen.outcomes.isEmpty)
        #expect(!requests.isAsking)
    }

    /// Only a command that vanished without a word leaves the mode for the app to put back,
    /// and not after a person kept it.
    @Test func restoresOnlyAfterACommandVanished() async throws {
        let requests = screen.requests(clock: clock)
        requests.abandoned(request, .dismissed(.interrupted))
        requests.abandoned(request, .dismissed(.stoppedWaiting))
        #expect(screen.restored.isEmpty)
        requests.abandoned(request, .disconnected)
        #expect(screen.restored == [request])
        let kept = request
        let answer = Task { await requests.answer(kept) }
        try await screen.dialog().keep()
        _ = await answer.value
        requests.abandoned(kept, .disconnected)
        #expect(screen.restored.count == 1)
    }

    /// A Keep counts from the click: a command killed before the answer got back to it
    /// does not have the kept mode put back.
    @Test func leavesAModeKeptJustBeforeItsCommandVanished() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let answer = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        dialog.keep()
        requests.abandoned(request, .disconnected)
        _ = await answer.value
        #expect(screen.restored.isEmpty)
    }

    /// The same command again after a person kept it: its Keep is no reason to leave the
    /// mode when this one vanishes while its dialog is up.
    @Test func restoresARepeatOfAKeptRequestWhoseCommandVanished() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let first = Task { await requests.answer(request) }
        try await screen.dialog().keep()
        #expect(await first.value == .keptByPerson)

        let second = Task { await requests.answer(request) }
        let dialog = try await screen.dialog(1)
        #expect(dialog.answer == nil)
        // Killed: the server cancels the handler and says the command disconnected.
        second.cancel()
        requests.abandoned(request, .disconnected)
        _ = await second.value
        #expect(screen.restored == [request])
    }

    /// The same command again after a Keep, turned away before its dialog (the app's own
    /// question is up) and killed before it heard so: its mode is put back.
    @Test func restoresARepeatOfAKeptRequestTurnedAwayBeforeItsDialog() async throws {
        let requests = screen.requests(clock: clock)
        let request = request
        let first = Task { await requests.answer(request) }
        try await screen.dialog().keep()
        #expect(await first.value == .keptByPerson)

        screen.isAppTrialUp = true
        #expect(await requests.answer(request).reason == AgentRequests.Refusal.appTrial)
        requests.abandoned(request, .disconnected)
        #expect(screen.restored == [request])
    }

    /// Another command's dialog coming up does not end a Keep still on its way to its own
    /// command: that command vanishing then leaves the kept mode.
    @Test func leavesAKeptModeWhenAnotherRequestComesUpFirst() async throws {
        let requests = screen.requests(clock: clock)
        let kept = request
        let first = Task { await requests.answer(kept) }
        try await screen.dialog().keep()
        _ = await first.value
        var other = request
        other.modeID = 91
        other.mode = "3008 × 1692"
        let second = Task { await requests.answer(other) }
        let dialog = try await screen.dialog(1)

        requests.abandoned(kept, .disconnected)
        #expect(screen.restored.isEmpty)
        dialog.revert()
        _ = await second.value
    }

    /// Settings say Don't Allow: a request that comes anyway, without `hello` or after the
    /// setting changed, shows no dialog and is answered Revert.
    @Test func turnsARequestAwayWhenThePersonDoesNotAllowHiddenModes() async {
        screen.allowsHiddenModes = false
        let requests = screen.requests(clock: clock)
        let request = request
        let answer = Task { await requests.answer(request) }
        // A dialog that shows anyway is answered, so the test ends either way.
        try? await Task.sleep(for: .milliseconds(50))
        screen.shown.first?.revert()
        let response = await answer.value
        #expect(screen.shown.isEmpty)
        #expect(response.answer == .revert)
        #expect(response.by == nil)
        #expect(response.reason == AgentRequests.Refusal.notAllowed)
    }

    /// A command that vanished while the app's own countdown was up: its mode is put back
    /// once that countdown is over, since the coordinator turns switches away until then.
    @Test func putsBackAVanishedCommandsModeOnceTheAppsCountdownIsOver() throws {
        let service = FakeDisplayService()
        let scratch = ScratchDefaults()
        let answers = TrialAnswers()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), answers: answers,
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteAgentRestore-\(UUID().uuidString)")
        )
        let requests = AgentRequests(model: model)
        let dell = FakeDisplayService.dell
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        let request = ConfirmHiddenModeRequest(
            display: dell, trying: hidden, previous: dell.currentMode, trialSeconds: 8,
            requester: Requester(agent: "Claude Code", app: "Terminal")
        )
        // The command switched the DELL, then was killed during a trial on the built-in display.
        try service.apply(modeID: hidden.modeID, to: dell.id, scope: .session)
        model.refresh()
        answers.whileAsking = { requests.abandoned(request, .disconnected) }
        let builtIn = try #require(model.displays.first { $0.id == FakeDisplayService.builtInID })
        let other = try #require(builtIn.modes.first { $0.modeID != builtIn.currentModeID })
        model.apply(modeID: other.modeID, to: builtIn.id, needsConfirmation: true)
        #expect(service.currentModeID(of: dell.id) == hidden.modeID)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(service.currentModeID(of: dell.id) == dell.currentModeID)
        #expect(service.changes.last?.displayID == dell.id)
    }

    /// The previous mode goes back for the session only, as the command's own revert puts
    /// it, and History says how the command's trial ended, since the command can't.
    @Test func putsBackAVanishedCommandsModeForTheSessionAndRecordsIt() throws {
        let service = FakeDisplayService()
        let scratch = ScratchDefaults()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults),
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteAgentRestore-\(UUID().uuidString)")
        )
        let dell = FakeDisplayService.dell
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        let request = ConfirmHiddenModeRequest(
            display: dell, trying: hidden, previous: dell.currentMode, trialSeconds: 8,
            requester: Requester(agent: "Claude Code", app: "Terminal")
        )
        try service.apply(modeID: hidden.modeID, to: dell.id, scope: .session)
        model.refresh()
        AgentRequests.restorePreviousMode(of: request, in: model)
        #expect(service.changes.last == FakeDisplayService.Change(displayID: dell.id, modeID: try #require(dell.currentModeID), scope: .session))
        let entry = try #require(model.historyEntries.first)
        #expect(entry.source == .agent(name: "Claude Code", app: "Terminal"))
        #expect(entry.outcome == .reverted(.unspecified))
        guard case .mode(let change) = entry.change else {
            Issue.record("expected a mode change")
            return
        }
        #expect(change.to.modeID == hidden.modeID)
        #expect(change.from?.modeID == dell.currentModeID)
    }

    /// An Undo that would try a hidden mode while a request's dialog is up changes nothing,
    /// as a hidden mode chosen then does, and says why: the dialog stays clickable over the
    /// alert and keeps counting down.
    @Test func saysWhyAnUndoWaitsWhileADialogIsUp() async throws {
        let service = FakeDisplayService()
        let scratch = ScratchDefaults()
        let answers = TrialAnswers()
        let errors = ShownErrors()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), answers: answers, errors: errors,
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteAgentUndo-\(UUID().uuidString)")
        )
        let dell = FakeDisplayService.dell
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        answers.keeps = true
        model.apply(hidden, to: dell)
        let listed = try #require(dell.modes.first { $0.origin == .system && $0.modeID != dell.currentModeID })
        model.apply(listed, to: try #require(model.displays.first { $0.id == dell.id }))
        // Undoing it goes back to the hidden mode, which is tried first.
        let change = try #require(model.historyEntries.first)
        let requests = screen.requests(clock: clock)
        model.agentRequests = requests
        let request = request
        let answer = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        let switches = service.changes.count

        model.undo(change, from: .panel)

        #expect(service.changes.count == switches)
        #expect(errors.titles == ["The change could not be undone"])
        #expect(errors.messages == [AppModel.undoWaitsForAQuestion])
        dialog.revert()
        _ = await answer.value
    }

    /// The mode before the trial does not take (a hidden one the display reports late, or
    /// refuses): the display's default mode comes back, as the command's own revert would put
    /// it, never the mode on trial that nobody kept.
    @Test func putsBackTheDefaultModeWhenTheOneBeforeDoesNotTake() throws {
        var dell = FakeDisplayService.dell
        let earlier = DisplayMode(
            modeID: 213, width: 2304, height: 1296, pixelWidth: 4608, pixelHeight: 2592,
            refreshRate: 60, bitsPerSample: 8, ioFlags: 0x3, origin: .hidden
        )
        dell.modes.append(earlier)
        // Kept until logout after an earlier trial.
        dell.currentModeID = earlier.modeID
        let fake = FakeDisplayService(displays: [FakeDisplayService.builtIn, dell])
        let service = IgnoringDisplays(fake)
        let scratch = ScratchDefaults()
        let errors = ShownErrors()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), errors: errors,
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteAgentRestore-\(UUID().uuidString)")
        )
        let trying = try #require(dell.modes.first { $0.origin == .hidden && $0.modeID != earlier.modeID })
        let request = ConfirmHiddenModeRequest(
            display: dell, trying: trying, previous: earlier, trialSeconds: 8,
            requester: Requester(agent: "Claude Code", app: "Terminal")
        )
        try fake.apply(modeID: trying.modeID, to: dell.id, scope: .session)
        model.refresh()
        service.ignored = [earlier.modeID]

        AgentRequests.restorePreviousMode(of: request, in: model)

        let defaultMode = try #require(dell.modes.first { $0.origin == .system && $0.isDefault })
        #expect(fake.currentModeID(of: dell.id) == defaultMode.modeID)
        #expect(fake.changes.last == FakeDisplayService.Change(displayID: dell.id, modeID: defaultMode.modeID, scope: .session))
        #expect(model.modeChanges.pendingRestores.isEmpty)
        #expect(errors.titles.isEmpty)
        #expect(model.historyEntries.first?.outcome == .reverted(.unspecified))
    }

    /// A command killed while its display is away, maybe because the display can't show the
    /// mode on trial: the app waits for the display, as for its own trials, puts the
    /// previous mode back once it is back, and History says so then.
    @Test func waitsForADisplayAwayToPutItsPreviousModeBack() throws {
        let service = FakeDisplayService()
        let scratch = ScratchDefaults()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults),
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteAgentRestore-\(UUID().uuidString)")
        )
        let dell = FakeDisplayService.dell
        let previous = try #require(dell.currentModeID)
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        let request = ConfirmHiddenModeRequest(
            display: dell, trying: hidden, previous: dell.currentMode, trialSeconds: 8,
            requester: Requester(agent: "Claude Code", app: "Terminal")
        )
        try service.apply(modeID: hidden.modeID, to: dell.id, scope: .session)
        let inTrial = try #require(service.displays().first { $0.id == dell.id })
        service.set([FakeDisplayService.builtIn])
        model.displaysDidChange()

        AgentRequests.restorePreviousMode(of: request, in: model)
        #expect(model.modeChanges.pendingRestores.map(\.displayID) == [dell.id])
        #expect(model.historyEntries.isEmpty)

        // Back, still in the mode on trial.
        service.set([FakeDisplayService.builtIn, inTrial])
        model.displaysDidChange()
        #expect(service.changes.last == FakeDisplayService.Change(displayID: dell.id, modeID: previous, scope: .session))
        #expect(model.modeChanges.pendingRestores.isEmpty)
        let entry = try #require(model.historyEntries.first)
        #expect(entry.source == .agent(name: "Claude Code", app: "Terminal"))
        #expect(entry.outcome == .reverted(.displayWentDark))
    }

    /// Another monitor took the ID of the one on trial while it was dark: the revert waits for
    /// the one on trial, found by its serial number under its new ID once it is back, and
    /// leaves the other monitor alone.
    @Test func waitsForTheDisplayOnTrialWhenAnotherTakesItsID() throws {
        let service = FakeDisplayService()
        let scratch = ScratchDefaults()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults),
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteAgentRestore-\(UUID().uuidString)")
        )
        let dell = FakeDisplayService.dell
        let previous = try #require(dell.currentModeID)
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        let request = ConfirmHiddenModeRequest(
            display: dell, trying: hidden, previous: dell.currentMode, trialSeconds: 8,
            requester: Requester(agent: "Claude Code", app: "Terminal")
        )
        try service.apply(modeID: hidden.modeID, to: dell.id, scope: .session)
        model.refresh()
        var inTrial = try #require(service.displays().first { $0.id == dell.id })
        service.set([FakeDisplayService.builtIn])
        model.displaysDidChange()
        var other = FakeDisplayService.dell
        other.serialNumber = 0x1234
        service.set([FakeDisplayService.builtIn, other])
        model.displaysDidChange()
        let switches = service.changes.count

        AgentRequests.restorePreviousMode(of: request, in: model)
        #expect(model.modeChanges.pendingRestores.map(\.displayID) == [dell.id])
        #expect(service.changes.count == switches)

        inTrial.id = 7
        service.set([FakeDisplayService.builtIn, other, inTrial])
        model.displaysDidChange()
        #expect(service.changes.last == FakeDisplayService.Change(displayID: 7, modeID: previous, scope: .session))
        #expect(model.modeChanges.pendingRestores.isEmpty)
        #expect(model.historyEntries.first?.outcome == .reverted(.displayWentDark))
    }

    /// A display changed since the command switched it keeps what was chosen, and History
    /// says the trial ended with the display changed, as the command would have recorded.
    @Test func leavesADisplayChangedSinceAndSaysSo() throws {
        let service = FakeDisplayService()
        let scratch = ScratchDefaults()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults),
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteAgentRestore-\(UUID().uuidString)")
        )
        let dell = FakeDisplayService.dell
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        let chosen = try #require(dell.modes.first { $0.origin == .system && $0.modeID != dell.currentModeID })
        let request = ConfirmHiddenModeRequest(
            display: dell, trying: hidden, previous: dell.currentMode, trialSeconds: 8,
            requester: Requester(agent: "Claude Code", app: "Terminal")
        )
        try service.apply(modeID: hidden.modeID, to: dell.id, scope: .session)
        try service.apply(modeID: chosen.modeID, to: dell.id, scope: .permanent)
        model.refresh()
        let switches = service.changes.count

        AgentRequests.restorePreviousMode(of: request, in: model)

        #expect(service.changes.count == switches)
        #expect(service.currentModeID(of: dell.id) == chosen.modeID)
        #expect(model.historyEntries.first?.outcome == .reverted(.displayChanged))
    }

    /// Through the real socket: `hello` tells the app's trial length, and a person's Keep
    /// reaches the command.
    @Test func answersTheCommandOverTheSocket() async throws {
        let folder = try agentSocketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        screen.trialSeconds = 30
        let socket = folder.appending(path: "agent.sock")
        let requests = screen.requests(socket: socket, clock: clock)
        requests.start()
        defer { requests.stop() }
        #expect(requests.isListening)
        let client = AgentChannelClient(socket: socket)
        let status = await onOwnThread { client.checkApp() }
        guard case .ready(let ready) = status else {
            Issue.record("The app did not say hello: \(status)")
            return
        }
        #expect(ready.trialSeconds == 30)
        let request = request
        let progress = Task.detached { () -> PendingAnswer.Progress in
            do {
                return try client.ask(request).waitForAnswer(until: .now + .seconds(10))
            } catch let error as AgentChannelError {
                return .failed(error)
            } catch {
                return .failed(.closedWithoutAnswer)
            }
        }
        try await screen.dialog().keep()
        #expect(await progress.value == .answered(.keptByPerson))
    }
}

/// Runs blocking socket work off the main actor.
/// The fake displays, except that a mode in `ignored` never takes: the display goes on
/// showing the mode it had, as one that reports a switch late, or not at all, does.
final class IgnoringDisplays: DisplayControlling, @unchecked Sendable {
    let base: FakeDisplayService
    private let lock = NSLock()
    private var ignoredModes: Set<Int32> = []

    init(_ base: FakeDisplayService) {
        self.base = base
    }

    var ignored: Set<Int32> {
        get { lock.withLock { ignoredModes } }
        set { lock.withLock { ignoredModes = newValue } }
    }

    func displays() -> [Display] { base.displays() }
    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? { base.currentModeID(of: displayID) }
    func setMirroring(_ enabled: Bool) throws { try base.setMirroring(enabled) }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        guard !ignored.contains(modeID) else { return }
        try base.apply(modeID: modeID, to: displayID, scope: scope)
    }
}

private func onOwnThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: work()) }
    }
}

/// A fresh folder for a socket. A socket address holds 103 bytes of path, so it goes in
/// /tmp when the temporary folder's path is long.
private func agentSocketFolder() throws -> URL {
    let name = "rt-" + UUID().uuidString.prefix(8)
    let temporary = FileManager.default.temporaryDirectory
    let fits = temporary.path(percentEncoded: false).utf8.count + name.count + "/agent.sock".count < 100
    return (fits ? temporary : URL(filePath: "/tmp", directoryHint: .isDirectory)).appending(path: name, directoryHint: .isDirectory)
}
