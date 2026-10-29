import AppKit
import Foundation
import Observation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// Records what the app model asks of the windows, the panel and quitting.
@MainActor
final class RecordingShell: AppShell {
    var windows: [AppRoute] = []
    var panelOpens = 0
    var panelCloses = 0
    var quits = 0

    func showWindow(_ route: AppRoute) { windows.append(route) }
    func showPanel() { panelOpens += 1 }
    func closePanel() { panelCloses += 1 }
    func quit() { quits += 1 }
}

/// Launch at Login that turns on and off when toggled, without `SMAppService`.
@MainActor
final class ToggledLoginItem: LoginItemToggling {
    var state: LaunchAtLoginState
    private(set) var toggles = 0

    init(_ state: LaunchAtLoginState) {
        self.state = state
    }

    func unregister() throws {
        state = .disabled
    }

    func toggle() {
        toggles += 1
        state = state == .enabled ? .disabled : .enabled
    }
}

/// A user defaults suite of the test's own, removed when the test is over.
final class ScratchDefaults {
    let name = "ResoluteAppTests-\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name) ?? .standard
    }

    deinit {
        defaults.removePersistentDomain(forName: name)
    }
}

/// Answers the Keep/Revert question, and notes the countdown it was asked with.
@MainActor
final class TrialAnswers {
    var keeps = false
    var asked: [RevertCountdown] = []
    var questions: [TrialQuestion] = []
    /// The notices that said how each trial ended.
    var outcomes: [TrialOutcome] = []
    /// Runs while the question is up.
    var whileAsking: (() -> Void)?

    func answer(_ question: TrialQuestion) -> Bool {
        asked.append(question.countdown)
        questions.append(question)
        whileAsking?()
        return keeps
    }
}

/// What the model would have shown in alerts.
@MainActor
final class ShownErrors {
    var titles: [String] = []
    /// What each said, in the same order.
    var messages: [String] = []
}

/// Notes that an observed value changed; the change handler may run on any thread.
final class ObservedChange: @unchecked Sendable {
    private let lock = NSLock()
    private var happened = false

    var didChange: Bool { lock.withLock { happened } }

    func note() {
        lock.withLock { happened = true }
    }
}

@MainActor
@Suite struct AppModelTests {
    let service = FakeDisplayService()
    let scratch = ScratchDefaults()
    let preferences: Preferences
    let loginItem = ToggledLoginItem(.disabled)
    let center = NotificationCenter()
    let shell = RecordingShell()
    let answers = TrialAnswers()
    let errors = ShownErrors()
    let overridesRoot: URL
    let model: AppModel

    typealias Change = FakeDisplayService.Change

    init() throws {
        preferences = Preferences(defaults: scratch.defaults)
        overridesRoot = FileManager.default.temporaryDirectory.appending(
            path: "ResoluteAppModelTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        model = Self.makeModel(
            service: service, preferences: preferences, loginItem: loginItem, center: center,
            answers: answers, errors: errors, overridesRoot: overridesRoot
        )
        model.shell = shell
    }

    static func makeModel(
        service: any DisplayControlling,
        preferences: Preferences,
        loginItem: ToggledLoginItem = ToggledLoginItem(.disabled),
        center: NotificationCenter = NotificationCenter(),
        answers: TrialAnswers = TrialAnswers(),
        errors: ShownErrors = ShownErrors(),
        overridesRoot: URL,
        launchKind: LaunchKind = .deliberate
    ) -> AppModel {
        AppModel(environment: AppEnvironment(
            service: service,
            preferences: preferences,
            loginItem: loginItem,
            overrides: OverrideStore(locations: .staged(at: overridesRoot)),
            support: SupportLocations(root: overridesRoot.appending(path: "Support", directoryHint: .isDirectory)),
            notificationCenter: center,
            askToKeep: { answers.answer($0) },
            showTrialOutcome: { outcome, _ in answers.outcomes.append(outcome) },
            showError: { error, title in
                errors.titles.append(title)
                errors.messages.append(error.localizedDescription)
            },
            launchKind: launchKind,
            displayDetails: { _ in DisplayDetails() }
        ))
    }

    var builtIn: Display { FakeDisplayService.builtIn }
    var dell: Display { FakeDisplayService.dell }

    func display(_ id: CGDirectDisplayID) throws -> Display {
        try #require(model.displays.first { $0.id == id })
    }

    /// Lets main-actor work queued by a notification or an observation run.
    func settle() async throws {
        try await Task.sleep(for: .milliseconds(50))
    }

    // MARK: - Displays

    @Test func listsTheMainDisplayFirstThenTheBuiltInOne() {
        service.set([dell, builtIn])
        model.refresh()
        #expect(model.displays.map(\.id) == [FakeDisplayService.builtInID, FakeDisplayService.dellID])

        var mainDell = dell
        mainDell.isMain = true
        var secondaryBuiltIn = builtIn
        secondaryBuiltIn.isMain = false
        service.set([secondaryBuiltIn, mainDell])
        model.refresh()
        #expect(model.displays.map(\.id) == [FakeDisplayService.dellID, FakeDisplayService.builtInID])
        #expect(model.mainDisplay?.id == FakeDisplayService.dellID)
    }

    @Test func readsTheDisplaysAgainWhenTheScreensChange() async throws {
        #expect(model.displays.count == 2)
        service.set([builtIn])
        #expect(model.displays.count == 2)

        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await settle()
        #expect(model.displays.map(\.id) == [FakeDisplayService.builtInID])
        #expect(!model.canMirror)
    }

    @Test func switchesThroughTheCoordinatorAndReadsTheDisplaysAgain() throws {
        let mode = try #require(dell.modes.first { $0.width == 1920 && $0.refreshRate == 60 && $0.isHiDPI })
        model.apply(mode, to: dell)
        #expect(service.changes == [Change(displayID: FakeDisplayService.dellID, modeID: mode.modeID, scope: .permanent)])
        #expect(try display(FakeDisplayService.dellID).currentModeID == mode.modeID)
        #expect(answers.asked.isEmpty)
    }

    @Test func triesAHiddenModeForTheTrialLengthAndKeepsItWhenThePersonDoes() throws {
        preferences.trialLength = .thirtySeconds
        answers.keeps = true
        let model = model
        var countdownWhileAsking: RevertCountdown?
        answers.whileAsking = { countdownWhileAsking = model.trial.countdown }
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })

        let started = Date()
        model.apply(hidden, to: dell)
        // Kept until logout: a hidden mode is never saved for good.
        #expect(service.changes == [
            Change(displayID: FakeDisplayService.dellID, modeID: hidden.modeID, scope: .session),
        ])
        #expect(answers.outcomes == [.kept])
        let question = try #require(answers.questions.first)
        #expect(question.displayID == FakeDisplayService.dellID && question.displayName == dell.name)
        #expect(question.mode == hidden.sizeText && question.previousMode == dell.currentMode?.sizeText)
        let countdown = try #require(answers.asked.first)
        #expect(abs(countdown.deadline.timeIntervalSince(started) - 30) < 2)
        #expect(countdownWhileAsking == countdown)
        #expect(model.trial.countdown == nil)
        #expect(try display(FakeDisplayService.dellID).currentModeID == hidden.modeID)
    }

    @Test func putsThePreviousModeBackWhenATrialIsNotKept() throws {
        let previous = try #require(dell.currentModeID)
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        model.apply(hidden, to: dell)
        #expect(service.changes == [
            Change(displayID: FakeDisplayService.dellID, modeID: hidden.modeID, scope: .session),
            Change(displayID: FakeDisplayService.dellID, modeID: previous, scope: .session),
        ])
        #expect(try display(FakeDisplayService.dellID).currentModeID == previous)
        #expect(answers.asked.count == 1)
    }

    @Test func changesTheRefreshRateAtTheCurrentResolution() throws {
        model.setRefreshRate(50, on: FakeDisplayService.dellID)
        let fifty = try #require(dell.modes.first { $0.width == 2560 && $0.isHiDPI && $0.refreshRate == 50 })
        #expect(service.changes == [Change(displayID: FakeDisplayService.dellID, modeID: fifty.modeID, scope: .permanent)])

        // The rate in use, and one the resolution does not offer, change nothing.
        model.setRefreshRate(50, on: FakeDisplayService.dellID)
        model.setRefreshRate(144, on: FakeDisplayService.dellID)
        #expect(service.changes.count == 1)
    }

    @Test func mirrorsAndStopsMirroring() {
        #expect(model.canMirror)
        #expect(!model.isMirroring)
        model.setMirroring(true)
        #expect(model.isMirroring)
        model.toggleMirroring()
        #expect(!model.isMirroring)
        #expect(service.mirroringRequests == [true, false])
        #expect(errors.titles.isEmpty)
    }

    @Test func saysWhenMirroringCannotBeChanged() {
        service.failsWith = .coreGraphics(code: 1001, operation: "mirror the displays")
        model.setMirroring(true)
        #expect(errors.titles == ["Mirroring could not be changed"])
        #expect(!model.isMirroring)
    }

    /// Mirroring changes the displays a trial must put back, and an alert would hold up its
    /// revert, so nothing else runs while the question is up.
    @Test func changesNothingElseWhileATrialIsUp() throws {
        let model = model
        answers.whileAsking = {
            model.setMirroring(true)
            model.toggleLaunchAtLogin()
            model.openWindow(.presets)
        }
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        model.apply(hidden, to: dell)
        #expect(answers.asked.count == 1)
        #expect(service.mirroringRequests.isEmpty)
        #expect(loginItem.toggles == 0)
        #expect(shell.windows.isEmpty)
    }

    // MARK: - Launch at Login

    @Test func turnsLaunchAtLoginOnAndOff() {
        #expect(model.launchAtLogin == .disabled)
        model.toggleLaunchAtLogin()
        #expect(model.launchAtLogin == .enabled)
        model.toggleLaunchAtLogin()
        #expect(model.launchAtLogin == .disabled)
        #expect(loginItem.toggles == 2)
    }

    @Test func notesLaunchAtLoginChangedInSystemSettings() {
        loginItem.state = .requiresApproval
        model.refresh()
        #expect(model.launchAtLogin == .requiresApproval)
    }

    // MARK: - Override targets

    @Test func listsDisplaysThatAreNotConnectedButHaveAnOverride() throws {
        defer { try? FileManager.default.removeItem(at: overridesRoot) }
        let locations = OverrideLocations.staged(at: overridesRoot)
        let away = OverrideKey(vendorID: 0x1E6D, productID: 0x5B11)
        let unnamed = OverrideKey(vendorID: 0x22F0, productID: 0x1234)
        try write(DisplayOverride(key: away, productName: "LG UltraFine 5K"), to: locations)
        try write(DisplayOverride(key: unnamed), to: locations)
        try write(DisplayOverride(key: OverrideKey(display: dell)), to: locations)
        model.refresh()

        #expect(model.overrideTargets == [
            AppModel.OverrideTarget(
                key: OverrideKey(display: builtIn), name: "Built-in Retina Display",
                displayID: FakeDisplayService.builtInID, hasOverride: false
            ),
            AppModel.OverrideTarget(
                key: OverrideKey(display: dell), name: "DELL U2723QE", displayID: FakeDisplayService.dellID, hasOverride: true
            ),
            AppModel.OverrideTarget(key: away, name: "LG UltraFine 5K", displayID: nil, hasOverride: true),
            AppModel.OverrideTarget(key: unnamed, name: "Display 22f0:1234", displayID: nil, hasOverride: true),
        ])
        #expect(model.notConnectedTargets.map(\.key) == [away, unnamed])
        #expect(model.windowTitle(for: .display(.overrideKey(away))) == WindowTitle(title: "LG UltraFine 5K", subtitle: "Not connected"))
    }

    /// Identical monitors share an override key, so one page stands for them.
    @Test func listsIdenticalMonitorsUnderOneOverrideKey() {
        var twin = dell
        twin.id = 3
        service.set([builtIn, dell, twin])
        model.refresh()
        #expect(model.overrideTargets.map(\.key) == [OverrideKey(display: builtIn), OverrideKey(display: dell)])
        #expect(model.display(for: .overrideKey(OverrideKey(display: dell))) == nil)
        #expect(model.display(for: .overrideKey(OverrideKey(display: builtIn)))?.id == FakeDisplayService.builtInID)
    }

    func write(_ override: DisplayOverride, to locations: OverrideLocations) throws {
        let url = locations.userFile(for: override.key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try override.propertyListData().write(to: url)
    }

    // MARK: - Routing

    @Test func opensWindowsThePanelAndQuitsThroughTheShell() {
        model.openWindow(.presets)
        model.openSettings()
        model.openSettings(.about)
        model.openCustomResolutions(for: nil)
        model.openCustomResolutions(for: FakeDisplayService.dellID)
        model.openPanel()
        model.closePanel()
        model.quit()
        #expect(shell.windows == [
            .presets, .settings(.general), .settings(.about),
            .display(.id(FakeDisplayService.builtInID), tab: .customResolutions),
            .display(.id(FakeDisplayService.dellID), tab: .customResolutions),
        ])
        #expect(shell.panelOpens == 1)
        #expect(shell.panelCloses == 1)
        #expect(shell.quits == 1)
    }

    @Test func opensOnTheMainDisplayByDefault() {
        #expect(model.defaultRoute == .display(.id(FakeDisplayService.builtInID), tab: .resolution))
        service.set([])
        model.refresh()
        #expect(model.defaultRoute == .settings(.general))
    }

    @Test func titlesEachPage() {
        #expect(model.windowTitle(for: .display(.id(FakeDisplayService.builtInID)))
            == WindowTitle(title: "Built-in Retina Display", subtitle: "1728 × 1117 · 120 Hz"))
        #expect(model.windowTitle(for: .display(.id(FakeDisplayService.dellID), tab: .pictureAndName))
            == WindowTitle(title: "DELL U2723QE", subtitle: "2560 × 1440 · 60 Hz"))
        #expect(model.windowTitle(for: .display(.id(99))) == WindowTitle(title: "Display", subtitle: "Not connected"))
        #expect(model.windowTitle(for: .presets) == WindowTitle(title: "Presets", subtitle: ""))
        #expect(model.windowTitle(for: .history) == WindowTitle(title: "History", subtitle: ""))
        #expect(model.windowTitle(for: .settings(.commandLine)) == WindowTitle(title: "Settings", subtitle: ""))
    }

    @Test func showsTheMainDisplaysResolutionInTheMenuBar() {
        #expect(model.menuBarResolutionText == "1728 × 1117")
    }

    // MARK: - Waiting reverts

    /// A display that dropped off during a trial: the panel's Stop Waiting gives its revert up,
    /// and the display keeps what it shows when it is back.
    @Test func stopsWaitingForADisplayThatWentAway() async throws {
        let displays = ReconnectingDisplays()
        let answers = TrialAnswers()
        answers.whileAsking = { displays.goAway(2) }
        let model = Self.makeModel(service: displays, preferences: preferences, answers: answers, overridesRoot: overridesRoot)
        let observed = ObservedChange()
        withObservationTracking {
            _ = model.pendingRestores
        } onChange: {
            observed.note()
        }

        model.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(model.pendingRestores.map(\.displayID) == [2])
        #expect(observed.didChange)

        model.stopWaiting(for: 2)
        #expect(model.pendingRestores.isEmpty)
        displays.comeBack(2)
        model.displaysDidChange()
        #expect(displays.changes.map(\.modeID) == [90])
    }

    /// History says how a trial whose revert waited ended, Stop Waiting included, so it
    /// never leaves one out.
    @Test func recordsATrialWhoseWaitWasStopped() throws {
        let displays = ReconnectingDisplays()
        let answers = TrialAnswers()
        answers.whileAsking = { displays.goAway(2) }
        let model = Self.makeModel(service: displays, preferences: preferences, answers: answers, overridesRoot: overridesRoot)
        model.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(model.historyEntries.isEmpty)

        model.stopWaiting(for: 2)
        #expect(model.trialsAwaitingRestore.isEmpty)
        #expect(model.historyEntries.map(\.outcome) == [.failed(message: "You stopped waiting, so the previous mode was not put back.")])
    }

    /// A second trial of a display whose revert still waits is undone by the same revert;
    /// History lists both once the display is back.
    @Test func recordsEveryTrialOneRevertUndoes() throws {
        let displays = ReconnectingDisplays()
        let answers = TrialAnswers()
        answers.whileAsking = { displays.goAway(2) }
        let model = Self.makeModel(service: displays, preferences: preferences, answers: answers, overridesRoot: overridesRoot)
        model.apply(modeID: 90, to: 2, needsConfirmation: true)
        // Back, but it refuses its previous mode, then goes dark again during a second trial.
        displays.refused = [1]
        displays.comeBack(2)
        model.displaysDidChange()
        model.apply(modeID: 3, to: 2, needsConfirmation: true)
        #expect(model.trialsAwaitingRestore[2]?.map(\.mode.modeID) == [90, 3])

        displays.refused = []
        displays.comeBack(2)
        model.displaysDidChange()
        #expect(displays.changes.last?.modeID == 1)
        #expect(model.trialsAwaitingRestore.isEmpty)
        #expect(model.historyEntries.map(\.outcome) == [.reverted(.displayWentDark), .reverted(.displayWentDark)])
    }

    /// An Undo that tries a hidden mode, whose display goes dark during the countdown, is in
    /// History once the display is back, as any such trial is.
    @Test func recordsAnUndoTrialWhoseDisplayWentDark() throws {
        let displays = ReconnectingDisplays()
        let answers = TrialAnswers()
        let model = Self.makeModel(service: displays, preferences: preferences, answers: answers, overridesRoot: overridesRoot)
        answers.keeps = true
        model.apply(modeID: 90, to: 2, needsConfirmation: true)
        answers.keeps = false
        model.apply(modeID: 1, to: 2, needsConfirmation: false)
        let listed = try #require(model.historyEntries.first)
        answers.whileAsking = { displays.goAway(2) }
        model.undo(listed, from: .window)
        #expect(model.trialsAwaitingRestore[2]?.map(\.mode.modeID) == [90])

        displays.comeBack(2)
        model.displaysDidChange()
        #expect(model.historyEntries.count == 3)
        #expect(model.historyEntries.first?.outcome == .reverted(.displayWentDark))
        #expect(model.historyEntries.first?.source == .window)
    }

    /// An Undo that tries a hidden mode and is put back says why, as any trial does.
    @Test func recordsWhyAnUndoTrialWasPutBack() throws {
        let displays = ReconnectingDisplays()
        let answers = TrialAnswers()
        let model = Self.makeModel(service: displays, preferences: preferences, answers: answers, overridesRoot: overridesRoot)
        answers.keeps = true
        model.apply(modeID: 90, to: 2, needsConfirmation: true)
        answers.keeps = false
        model.apply(modeID: 1, to: 2, needsConfirmation: false)
        let listed = try #require(model.historyEntries.first)
        model.undo(listed, from: .window)
        #expect(model.historyEntries.first?.outcome == .reverted(.declined))
    }

    /// Quit Anyway while a revert waits: History says the trial was not put back.
    @Test func recordsTrialsStillWaitingWhenResoluteQuits() throws {
        let displays = ReconnectingDisplays()
        let answers = TrialAnswers()
        answers.whileAsking = { displays.goAway(2) }
        let model = Self.makeModel(service: displays, preferences: preferences, answers: answers, overridesRoot: overridesRoot)
        model.apply(modeID: 90, to: 2, needsConfirmation: true)
        #expect(model.historyEntries.isEmpty)
        model.recordTrialsLeftWaiting()
        #expect(model.historyEntries.map(\.outcome) == [.failed(message: "Resolute quit before it could put the previous mode back.")])
        #expect(model.trialsAwaitingRestore.isEmpty)
    }

    /// A menu built before the display behind an ID changed may say no trial is needed; a
    /// hidden mode is tried anyway.
    @Test func triesAHiddenModeWhateverTheMenuSaid() throws {
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        model.apply(modeID: hidden.modeID, to: dell.id, needsConfirmation: false)
        #expect(answers.asked.count == 1)
        #expect(service.changes.map(\.scope) == [.session, .session])
    }

    /// A menu offers what it read when it opened. When by the click its display ID names
    /// another display, on which that mode is hidden, the mode is tried, never saved for good.
    @Test func triesAModeHiddenOnTheDisplayNowBehindTheID() throws {
        var earlier = dell
        earlier.name = "Earlier monitor"
        earlier.serialNumber = 1
        let hiddenID = try #require(dell.modes.first { $0.origin == .hidden }?.modeID)
        let index = try #require(earlier.modes.firstIndex { $0.modeID == hiddenID })
        earlier.modes[index].origin = .system
        service.set([builtIn, earlier])
        model.refresh()
        // The DELL takes its ID before the model hears of the change.
        service.set([builtIn, dell])

        model.apply(modeID: hiddenID, to: dell.id, needsConfirmation: false, from: .menu)

        #expect(answers.asked.count == 1)
        #expect(service.changes.first == Change(displayID: dell.id, modeID: hiddenID, scope: .session))
        #expect(!service.changes.contains { $0.scope == .permanent })
    }

    // MARK: - Alerts

    /// An alert asked for while the countdown is up, here by a notification's Undo of a
    /// change no longer in History, opens once the switch is over: over the dialog it would
    /// hold up the revert until closed.
    @Test func opensAlertsAskedForDuringTheCountdownOnceItIsOver() throws {
        let poster = FakeNotificationPoster()
        let notifier = AgentChangeNotifier(model: model, poster: poster)
        let errors = errors
        var shownDuringCountdown: [String]?
        answers.whileAsking = {
            poster.onUndo?(UUID())
            shownDuringCountdown = errors.titles
        }
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        model.apply(hidden, to: try display(FakeDisplayService.dellID))
        withExtendedLifetime(notifier) {}
        #expect(shownDuringCountdown == [])
        #expect(errors.titles.isEmpty)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        #expect(errors.titles == ["The change can’t be undone"])
        // With no switch under way, an alert opens at once.
        model.showError(UndoUnavailable(reason: "Gone."), "Now")
        #expect(errors.titles.last == "Now")
    }

    // MARK: - Preferences

    @Test func startsWithTheDesignsSettings() {
        #expect(!preferences.showsResolutionInMenuBar)
        #expect(preferences.panelShortcut == .openPanel)
        #expect(preferences.panelShortcut?.displayText == "⌃⌥R")
        #expect(preferences.showLowResolutionModes)
        #expect(!preferences.showHiddenModes)
        #expect(preferences.trialLength == .fifteenSeconds)
        #expect(preferences.trialLength.title == "15 seconds")
        #expect(!preferences.hasShownWelcome)
        #expect(!preferences.hasShownFirstCloseNotice)
    }

    @Test func keepsSettingsInTheUserDefaults() {
        preferences.showsResolutionInMenuBar = true
        preferences.panelShortcut = KeyShortcut(key: "P", modifiers: [.command, .shift])
        preferences.showLowResolutionModes = false
        preferences.showHiddenModes = true
        preferences.trialLength = .oneMinute
        preferences.hasShownWelcome = true
        preferences.hasShownFirstCloseNotice = true

        let reread = Preferences(defaults: scratch.defaults)
        #expect(reread.showsResolutionInMenuBar)
        #expect(reread.panelShortcut?.spec == "shift+command+p")
        #expect(!reread.showLowResolutionModes)
        #expect(reread.showHiddenModes)
        #expect(reread.trialLength == .oneMinute)
        #expect(reread.hasShownWelcome)
        #expect(reread.hasShownFirstCloseNotice)
        // The low-resolution setting keeps the key the app has always used.
        #expect(scratch.defaults.object(forKey: "ShowLowResolutionModes") as? Bool == false)
    }

    @Test func remembersAClearedShortcut() {
        preferences.panelShortcut = nil
        #expect(Preferences(defaults: scratch.defaults).panelShortcut == nil)
    }

    @Test func readsAnUnknownTrialLengthAsTheDefault() {
        scratch.defaults.set(20, forKey: "HiddenModeTrialSeconds")
        #expect(preferences.trialLength == .fifteenSeconds)
        scratch.defaults.set("control+", forKey: "PanelShortcut")
        #expect(preferences.panelShortcut == .openPanel)
    }

    @Test func tellsObserversWhenASettingChanges() {
        let observed = ObservedChange()
        withObservationTracking {
            _ = preferences.showsResolutionInMenuBar
        } onChange: {
            observed.note()
        }
        preferences.showHiddenModes = true
        #expect(!observed.didChange)
        preferences.showsResolutionInMenuBar = true
        #expect(observed.didChange)
    }

    // MARK: - Launch

    @Test func knowsALaunchAtLoginFromTheOpenApplicationEvent() {
        func openApplication(launchedAsLoginItem: Bool) -> NSAppleEventDescriptor {
            let event = NSAppleEventDescriptor(
                eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
                targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
            )
            if launchedAsLoginItem {
                event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
            }
            return event
        }
        #expect(LaunchKind(appleEvent: openApplication(launchedAsLoginItem: true)) == .atLogin)
        #expect(LaunchKind(appleEvent: openApplication(launchedAsLoginItem: false)) == .deliberate)
        #expect(LaunchKind(appleEvent: nil) == .deliberate)
        let reopen = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        reopen.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        #expect(LaunchKind(appleEvent: reopen) == .deliberate)
    }

    @Test func passesTheLaunchKindOn() {
        let model = Self.makeModel(service: service, preferences: preferences, overridesRoot: overridesRoot, launchKind: .atLogin)
        #expect(model.launchKind == .atLogin)
    }
}

@Suite struct KeyShortcutTests {
    @Test func readsAndWritesItsSpec() throws {
        let shortcut = try #require(KeyShortcut(spec: "control+option+R"))
        #expect(shortcut == .openPanel)
        #expect(shortcut.spec == "control+option+r")
        #expect(shortcut.displayText == "⌃⌥R")
        #expect(shortcut.keyCode == 0x0F)
        #expect(shortcut.modifierFlags == [.control, .option])
        // Modifiers come out in menu order whatever order they were written in.
        #expect(KeyShortcut(spec: "command+shift+option+control+Space")?.spec == "control+option+shift+command+space")
        #expect(KeyShortcut(spec: "command+shift+option+control+Space")?.displayText == "⌃⌥⇧⌘Space")
        #expect(KeyShortcut(spec: "command+Left")?.displayText == "⌘←")
    }

    @Test(arguments: ["R", "shift+R", "control+control+R", "control+Hyper", "", "control+", "fn+R", "+R"])
    func refusesWhatIsNotAShortcut(_ spec: String) {
        #expect(KeyShortcut(spec: spec) == nil)
    }

    @Test func takesAKeyPressedInARecorder() {
        #expect(KeyShortcut(keyCode: 0x0F, modifierFlags: [.control, .option]) == .openPanel)
        #expect(KeyShortcut(keyCode: 0x7A, modifierFlags: [.command, .capsLock])?.spec == "command+f1")
        #expect(KeyShortcut(keyCode: 0x0F, modifierFlags: []) == nil)
        #expect(KeyShortcut(keyCode: 0x3F, modifierFlags: [.command]) == nil)
    }

    @Test func namesEveryKeyCodeOnce() {
        let codes = Array(KeyShortcut.keyCodes.values)
        #expect(Set(codes).count == codes.count)
    }
}

/// What a trial prompt published while it asked.
@MainActor
final class PromptRecord {
    var prompt: TrialPrompt?
    var countdown: RevertCountdown?
    var secondsLeft: Int?
}

@MainActor
@Suite struct TrialPromptTests {
    @Test func publishesTheCountdownWhileItAsks() throws {
        let record = PromptRecord()
        let prompt = TrialPrompt(length: { 15 }) { question in
            record.countdown = record.prompt?.countdown
            record.secondsLeft = record.prompt?.secondsLeft(at: question.countdown.deadline.addingTimeInterval(-12))
            return true
        }
        record.prompt = prompt
        let started = Date()
        // A kept mode lasts until logout.
        #expect(prompt.decide() == .keepForSession)
        let countdown = try #require(record.countdown)
        #expect(abs(countdown.deadline.timeIntervalSince(started) - 15) < 2)
        #expect(record.secondsLeft == 12)
        #expect(prompt.countdown == nil)
        #expect(prompt.secondsLeft() == nil)
    }

    @Test func revertsUnlessThePersonKeeps() {
        let prompt = TrialPrompt(length: { 15 }) { _ in false }
        #expect(prompt.decide() == .revert)
    }
}
