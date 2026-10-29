import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// Settings › Command Line & Agents › "Notify me when an agent changes a display": which
/// History entries notify, when permission is asked, and where Undo goes. A fake poster
/// stands in for Notification Center, which tests must never reach.
@MainActor
@Suite struct AgentNotificationTests {
    let service = FakeDisplayService()
    let scratch = ScratchDefaults()
    let errors = ShownErrors()
    let poster = FakeNotificationPoster()
    let root = FileManager.default.temporaryDirectory.appending(
        path: "ResoluteAgentNotificationTests-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    let model: AppModel
    let notifier: AgentChangeNotifier

    init() {
        model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), errors: errors, overridesRoot: root
        )
        notifier = AgentChangeNotifier(model: model, poster: poster, settleDelay: 0.05, retryInterval: 0.05)
    }

    var preferences: Preferences { model.preferences }

    func recorder(_ source: HistoryEntry.Source) -> HistoryRecorder {
        HistoryRecorder(store: HistoryStore(locations: model.support), source: source)
    }

    var claude: HistoryRecorder { recorder(.agent(name: "Claude Code", app: "Terminal")) }

    /// Switches the Dell as `resolute` does for `history`, and records it there.
    @discardableResult
    func switchDell(recordedBy history: HistoryRecorder, outcome: HistoryEntry.Outcome = .applied) throws -> HistoryEntry {
        let before = try #require(service.displays().first { $0.id == FakeDisplayService.dellID })
        let mode = try #require(before.modes.first {
            $0.origin != .hidden && $0.modeID != before.currentModeID && $0.isHiDPI == before.currentMode?.isHiDPI
                && $0.width != before.currentMode?.width
        })
        if outcome.tookEffect { try service.apply(modeID: mode.modeID, to: before.id, scope: .permanent) }
        return try #require(history.recordSwitch(of: before, to: mode, outcome: outcome))
    }

    /// Lets the observation of the preference, queued on the main run loop, run.
    func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    func turn(_ isOn: Bool) async throws {
        preferences.notifiesAgentChanges = isOn
        try await settle()
    }

    // MARK: - Which changes notify

    @Test func notifiesOfAnAgentsNewChangeInHistorysWords() async throws {
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        #expect(notifier.isWatching)
        let entry = try switchDell(recordedBy: claude)
        notifier.readHistory()
        let notification = try #require(poster.posted.first)
        #expect(poster.posted.count == 1)
        #expect(notification.entryID == entry.id)
        #expect(notification.title == HistoryText.title(of: entry.change))
        #expect(notification.title.hasPrefix("DELL U2723QE  "))
        #expect(notification.body == "From Claude Code (Terminal)")
        #expect(notification.offersUndo)
        // Read again, the same change does not notify twice.
        notifier.readHistory()
        #expect(poster.posted.count == 1)
    }

    @Test func notifiesOfNothingWhileOff() async throws {
        notifier.start()
        defer { notifier.stop() }
        #expect(!notifier.isWatching)
        try switchDell(recordedBy: claude)
        notifier.readHistory()
        #expect(poster.posted.isEmpty)
        // Turned on and off again, it stops watching.
        try await turn(true)
        try await turn(false)
        #expect(!notifier.isWatching)
        try switchDell(recordedBy: claude)
        notifier.readHistory()
        #expect(poster.posted.isEmpty)
    }

    @Test func neverNotifiesOfChangesMadeBeforeItWasTurnedOn() async throws {
        notifier.start()
        defer { notifier.stop() }
        try switchDell(recordedBy: claude)
        try await turn(true)
        notifier.readHistory()
        #expect(poster.posted.isEmpty)
    }

    @Test func neverNotifiesOfChangesMadeBeforeLaunch() throws {
        preferences.notifiesAgentChanges = true
        try switchDell(recordedBy: claude)
        notifier.start()
        defer { notifier.stop() }
        #expect(notifier.isWatching)
        notifier.readHistory()
        #expect(poster.posted.isEmpty)
    }

    @Test func ignoresTheAppsAndAPersonsChangesAndChangesThatDidNotHappen() async throws {
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        let dell = try #require(model.displays.first { $0.id == FakeDisplayService.dellID })
        let mode = try #require(dell.modes.first { $0.origin != .hidden && $0.modeID != dell.currentModeID })
        model.apply(mode, to: dell, from: .panel)
        try switchDell(recordedBy: recorder(.terminal(app: "Ghostty")))
        try switchDell(recordedBy: recorder(.shortcuts))
        try switchDell(recordedBy: recorder(.terminal(app: nil)).applying(preset: "Desk"))
        try switchDell(recordedBy: claude, outcome: .reverted(.noAnswer))
        try switchDell(recordedBy: claude, outcome: .failed(message: "The display did not answer"))
        notifier.readHistory()
        #expect(poster.posted.isEmpty)
    }

    @Test func notifiesOfEachSwitchOfAnAgentsPresetInOneStack() async throws {
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        let preset = claude.applying(preset: "Presenting")
        let first = try switchDell(recordedBy: preset)
        let mirroring = try #require(preset.recordMirroring(true, displays: service.displays()))
        notifier.readHistory()
        #expect(Set(poster.posted.map(\.entryID)) == [first.id, mirroring.id])
        #expect(poster.posted.map(\.body) == [
            "From Claude Code (Terminal) · “Presenting” preset", "From Claude Code (Terminal) · “Presenting” preset",
        ])
        #expect(Set(poster.posted.map(\.group)).count == 1)
        #expect(poster.posted.contains { $0.title.hasPrefix("Mirroring on: ") })
    }

    @Test func followsTheFileWhileAnAgentSwitches() async throws {
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        let preset = claude.applying(preset: "Presenting")
        let first = try switchDell(recordedBy: preset)
        let second = try switchDell(recordedBy: preset)
        for _ in 0..<100 where poster.posted.count < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        // Oldest first, so the newest is on top of the stack.
        #expect(poster.posted.map(\.entryID) == [first.id, second.id])
    }

    @Test func waitsForTheSupportFolderAnAgentsFirstSwitchCreates() async throws {
        #expect(!FileManager.default.fileExists(atPath: model.support.historyFile.deletingLastPathComponent().path))
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        let entry = try switchDell(recordedBy: claude)
        for _ in 0..<100 where poster.posted.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(poster.posted.map(\.entryID) == [entry.id])
    }

    // MARK: - Permission

    @Test func asksForPermissionOnlyWhenThePersonTurnsItOn() async throws {
        notifier.start()
        defer { notifier.stop() }
        #expect(poster.permissionRequests == 0)
        try await turn(true)
        #expect(poster.permissionRequests == 1)
        try await turn(false)
        #expect(poster.permissionRequests == 1)
        try await turn(true)
        #expect(poster.permissionRequests == 2)
    }

    @Test func doesNotAskAgainAtLaunch() async throws {
        preferences.notifiesAgentChanges = true
        notifier.start()
        defer { notifier.stop() }
        try await settle()
        #expect(poster.permissionRequests == 0)
    }

    @Test func hasNoNotificationCenterWithoutABundleIdentifier() {
        #expect(SystemNotificationPoster.make(bundleIdentifier: nil) == nil)
    }

    // MARK: - Undo

    @Test func undoGoesThroughTheModelAsThePanels() async throws {
        let original = service.currentModeID(of: FakeDisplayService.dellID)
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        let entry = try switchDell(recordedBy: claude)
        notifier.readHistory()
        #expect(poster.posted.map(\.entryID) == [entry.id])
        let onUndo = try #require(poster.onUndo)
        onUndo(entry.id)
        #expect(errors.titles.isEmpty)
        #expect(service.currentModeID(of: FakeDisplayService.dellID) == original)
        let undo = try #require(model.historyEntries.first { $0.outcome == .undone(of: entry.id) })
        #expect(undo.source == .panel)
        #expect(model.historyTimeline.status(of: entry) == .undone)
        // The app's own Undo is not an agent's change.
        notifier.readHistory()
        #expect(poster.posted.count == 1)
    }

    @Test func withdrawsTheUndoOfAChangeUndoneElsewhere() async throws {
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        let entry = try switchDell(recordedBy: claude)
        notifier.readHistory()
        model.refresh()
        model.undo(entry, from: .window)
        #expect(model.historyTimeline.status(of: entry) == .undone)
        notifier.readHistory()
        #expect(poster.withdrawn == [entry.id])
        notifier.readHistory()
        #expect(poster.withdrawn == [entry.id])
    }

    /// The person chose another mode for the display since: the notification's Undo is
    /// taken back, as the panel's is, and one clicked anyway leaves the person's choice.
    @Test func withdrawsTheUndoOfAChangeMadeAgainSince() async throws {
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        let entry = try switchDell(recordedBy: claude)
        notifier.readHistory()
        #expect(poster.posted.first?.offersUndo == true)
        model.refresh()
        let dell = try #require(model.displays.first { $0.id == FakeDisplayService.dellID })
        let chosen = try #require(dell.modes.first {
            $0.origin != .hidden && $0.modeID != dell.currentModeID && $0.isHiDPI == dell.currentMode?.isHiDPI
        })
        model.apply(chosen, to: dell, from: .panel)
        notifier.readHistory()
        #expect(poster.withdrawn == [entry.id])

        poster.onUndo?(entry.id)
        #expect(service.currentModeID(of: FakeDisplayService.dellID) == chosen.modeID)
        #expect(errors.titles == ["The change can’t be undone"])
    }

    /// Of an agent's two changes to one display, only the newer offers Undo.
    @Test func offersUndoOnlyForTheNewestChangeOfADisplay() async throws {
        notifier.start()
        defer { notifier.stop() }
        try await turn(true)
        try switchDell(recordedBy: claude)
        try switchDell(recordedBy: claude)
        notifier.readHistory()
        #expect(poster.posted.map(\.offersUndo) == [false, true])
    }

    /// Undo clicked while a countdown is up is done once the countdown is over, rather
    /// than turned away.
    @Test func undoesOnceTheCountdownItWasClickedDuringIsOver() throws {
        let answers = TrialAnswers()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), answers: answers, errors: errors,
            overridesRoot: root
        )
        let notifier = AgentChangeNotifier(model: model, poster: poster)
        let entry = try switchDell(recordedBy: claude)
        model.refresh()
        let agentsMode = service.currentModeID(of: FakeDisplayService.dellID)
        let poster = poster
        answers.whileAsking = { poster.onUndo?(entry.id) }
        let builtIn = try #require(model.displays.first { $0.id == FakeDisplayService.builtInID })
        let other = try #require(builtIn.modes.first { $0.modeID != builtIn.currentModeID })
        model.apply(modeID: other.modeID, to: builtIn.id, needsConfirmation: true)
        #expect(service.currentModeID(of: FakeDisplayService.dellID) == agentsMode)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(model.historyTimeline.status(of: entry) == .undone)
        #expect(service.currentModeID(of: FakeDisplayService.dellID) != agentsMode)
        #expect(errors.titles.isEmpty)
        withExtendedLifetime(notifier) {}
    }

    /// A notification's Undo is taken up at the run loop's next turn, which comes while
    /// main-actor work is under way too, rather than as main-actor work: an alert it opened as
    /// main-actor work would hold up all other such work until closed, such as a Keep from a
    /// `resolute` command's dialog on its way to the command.
    @Test func takesUpANotificationsUndoAtTheRunLoopsNextTurn() {
        let undo = UndoTakenUp()
        SystemNotificationPoster.takeUp { undo.ran = true }
        #expect(!undo.ran)
        // This test is main-actor work, which only the run loop's way gets past meanwhile.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(undo.ran)
    }

    @Test func saysWhenTheChangeIsGoneFromHistory() {
        poster.onUndo?(UUID())
        #expect(errors.titles == ["The change can’t be undone"])
        #expect(service.changes.isEmpty)
    }
}

@MainActor
private final class UndoTakenUp {
    var ran = false
}

/// Notification Center as the notifier sees it, without reaching it.
@MainActor
final class FakeNotificationPoster: AgentNotificationPosting {
    var onUndo: (@MainActor (UUID) -> Void)?
    private(set) var permissionRequests = 0
    private(set) var posted: [AgentChangeNotification] = []
    private(set) var withdrawn: [UUID] = []

    func requestPermission() {
        permissionRequests += 1
    }

    func post(_ notification: AgentChangeNotification) {
        posted.append(notification)
    }

    func withdraw(_ entryIDs: [UUID]) {
        withdrawn.append(contentsOf: entryIDs)
    }
}
