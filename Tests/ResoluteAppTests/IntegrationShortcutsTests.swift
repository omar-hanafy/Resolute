import AppIntents
import AppKit
import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// Shortcuts and Spotlight actions, run through the app model on the fake displays and
/// Figma's presets: what each switches, that History says Shortcuts, that only listed modes
/// are used, and that a change asked for while a Keep/Revert question is up fails with a
/// message rather than an alert.
@MainActor
@Suite struct IntegrationShortcutsTests {
    let service = FakeDisplayService()
    let scratch = ScratchDefaults()
    let answers = TrialAnswers()
    let errors = ShownErrors()
    let shell = RecordingShell()
    let model: AppModel
    let actions: ShortcutActions

    init() throws {
        model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), answers: answers, errors: errors,
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteShortcutsTests-\(UUID().uuidString)")
        )
        model.shell = shell
        try model.updatePresets { library in
            for preset in PresetsSamples.figma { try library.add(preset) }
        }
        actions = ShortcutActions(model: model)
    }

    var builtInID: String { ShortcutCatalog.identifier(of: FakeDisplayService.builtIn, among: model.displays) }
    var dellID: String { ShortcutCatalog.identifier(of: FakeDisplayService.dell, among: model.displays) }

    func display(_ id: CGDirectDisplayID) throws -> Display {
        try #require(model.displays.first { $0.id == id })
    }

    func resolution(_ width: Int, _ height: Int, on displayID: String, scale: Int = 2) throws -> ResolutionEntity {
        try #require(ShortcutCatalog.resolutions(of: model.displays, onlyOn: displayID).first {
            $0.key == ResolutionGroup.Key(width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale)
        })
    }

    func presetEntity(_ name: String) throws -> PresetEntity {
        try #require(ShortcutCatalog.presets(model.presets).first { $0.name == name })
    }

    func displayEntity(_ id: String) throws -> DisplayEntity {
        try #require(ShortcutCatalog.displays(model.displays).first { $0.id == id })
    }

    // MARK: - Apply Preset

    /// Apply Preset applies the preset through the model, each change recorded with
    /// Shortcuts as where it came from.
    @Test func applyPresetAppliesItWithShortcutsAsTheSource() throws {
        let name = try actions.applyPreset(presetEntity("Coding"))
        #expect(name == "Coding")
        #expect(model.isActive(try #require(model.presets.first { $0.name == "Coding" })))
        #expect(model.historyEntries.first?.source.origin == .shortcuts)
        #expect(model.historyEntries.first?.source.presetName == "Coding")
        #expect(errors.titles.isEmpty)
    }

    /// A preset deleted since the shortcut was made fails with what the panel's alert would
    /// say, and nothing switches.
    @Test func applyPresetOfADeletedPresetFailsWithAMessage() throws {
        let coding = try presetEntity("Coding")
        try model.updatePresets { library in _ = library.delete(id: coding.id) }
        #expect(throws: ShortcutError.failed(
            "“Coding” could not be applied. It was deleted outside Resolute, such as with resolute preset delete."
        )) {
            try actions.applyPreset(coding)
        }
        #expect(service.changes.isEmpty)
        #expect(errors.titles.isEmpty)
    }

    // MARK: - Set Resolution

    /// Set Resolution switches the display it names to the listed mode of that size, without
    /// asking to keep it, and History says Shortcuts.
    @Test func setResolutionSwitchesTheNamedDisplay() throws {
        let result = try actions.setResolution(resolution(1496, 967, on: builtInID), on: displayEntity(builtInID))
        #expect(result.resolution == "1496 × 967")
        #expect(service.changes.map(\.displayID) == [FakeDisplayService.builtInID])
        #expect(try display(FakeDisplayService.builtInID).currentMode?.width == 1496)
        #expect(answers.asked.isEmpty)
        #expect(model.historyEntries.first?.source == .shortcuts)
    }

    /// Spotlight's “Set 1496 × 967” names no display: the one the resolution belongs to
    /// switches.
    @Test func setResolutionWithoutADisplaySwitchesTheResolutionsOwn() throws {
        try actions.setResolution(resolution(1920, 1080, on: dellID), on: nil)
        #expect(service.changes.map(\.displayID) == [FakeDisplayService.dellID])
        #expect(try display(FakeDisplayService.dellID).currentMode?.width == 1920)
    }

    /// A resolution picked for one display and used with another switches the other to the
    /// same size when it lists it, and says so when it doesn't.
    @Test func setResolutionMatchesTheSizeOnAnotherDisplay() throws {
        let fromDell = try resolution(1920, 1080, on: dellID)
        #expect(throws: ShortcutError.notListed(size: "1920 × 1080", display: "Built-in Retina Display")) {
            try actions.setResolution(fromDell, on: displayEntity(builtInID))
        }
        #expect(service.changes.isEmpty)

        let fromBuiltIn = try resolution(2056, 1329, on: builtInID)
        var sameSize = fromBuiltIn
        sameSize.displayID = dellID
        #expect(throws: ShortcutError.notListed(size: "2056 × 1329", display: "DELL U2723QE")) {
            try actions.setResolution(sameSize, on: nil)
        }
    }

    /// A hidden mode is never offered nor used: nobody may be watching the display.
    @Test func setResolutionUsesListedModesOnly() throws {
        let offered = ShortcutCatalog.resolutions(of: model.displays, onlyOn: dellID).map(\.sizeText)
        #expect(!offered.contains("2880 × 1620"))
        let hidden = ResolutionEntity(
            displayID: dellID, displayName: "DELL U2723QE",
            key: ResolutionGroup.Key(width: 2880, height: 1620, pixelWidth: 5760, pixelHeight: 3240), isLowResolution: false
        )
        #expect(throws: ShortcutError.notListed(size: "2880 × 1620", display: "DELL U2723QE")) {
            try actions.setResolution(hidden, on: nil)
        }
        #expect(service.changes.isEmpty)
        #expect(answers.asked.isEmpty)
    }

    /// A display that is gone fails with its name.
    @Test func setResolutionOnADisplayThatIsGoneFails() throws {
        let dellResolution = try resolution(1920, 1080, on: dellID)
        service.set([FakeDisplayService.builtIn])
        #expect(throws: ShortcutError.notConnected(display: "DELL U2723QE")) {
            try actions.setResolution(dellResolution, on: nil)
        }
    }

    /// A switch that fails throws what its alert would have said, and shows no alert.
    @Test func aFailedSwitchThrowsInsteadOfShowingAnAlert() throws {
        let target = try resolution(1496, 967, on: builtInID)
        service.failsWith = .noDisplays
        #expect(throws: ShortcutError.failed(
            "The display mode could not be changed. \(ResoluteError.noDisplays.localizedDescription)"
        )) {
            try actions.setResolution(target, on: nil)
        }
        #expect(errors.titles.isEmpty)
        #expect(model.historyEntries.first?.source == .shortcuts)
    }

    // MARK: - Set Refresh Rate

    /// Set Refresh Rate switches to the listed mode at that rate, with Shortcuts as the source.
    @Test func setRefreshRateSwitchesWithShortcutsAsTheSource() throws {
        let result = try actions.setRefreshRate(RefreshRateEntity(hertz: 60), on: displayEntity(builtInID))
        #expect(result.refreshRate == "60 Hz")
        #expect(try display(FakeDisplayService.builtInID).currentMode?.refreshRate == 60)
        #expect(model.historyEntries.first?.source == .shortcuts)
    }

    /// A rate the display doesn't offer at its resolution fails with a message.
    @Test func setRefreshRateNotOfferedFails() throws {
        #expect(throws: ShortcutError.rateNotOffered(rate: "120 Hz", display: "DELL U2723QE", size: "2560 × 1440")) {
            try actions.setRefreshRate(RefreshRateEntity(hertz: 120), on: displayEntity(dellID))
        }
        #expect(service.changes.isEmpty)
    }

    /// The rate in use changes nothing and records nothing.
    @Test func setRefreshRateInUseChangesNothing() throws {
        try actions.setRefreshRate(RefreshRateEntity(hertz: 120), on: displayEntity(builtInID))
        #expect(service.changes.isEmpty)
        #expect(model.historyEntries.isEmpty)
    }

    /// A rate offered only by a hidden mode is not offered, as in the Dock menu.
    @Test func refreshRatesAreListedOnesOnly() throws {
        var dell = FakeDisplayService.dell
        let hidden = DisplayMode(
            modeID: 900, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 75, bitsPerSample: 8,
            origin: .hidden
        )
        dell.modes.append(hidden)
        service.set([FakeDisplayService.builtIn, dell])
        model.refresh()
        #expect(ShortcutCatalog.refreshRates(of: model.displays, onlyOn: dellID).map(\.hertz) == [60, 50, 30])
        #expect(throws: ShortcutError.rateNotOffered(rate: "75 Hz", display: "DELL U2723QE", size: "2560 × 1440")) {
            try actions.setRefreshRate(RefreshRateEntity(hertz: 75), on: displayEntity(dellID))
        }
    }

    // MARK: - Mirror Displays

    /// Mirror Displays turns mirroring on, off, or the other way, with Shortcuts as the source.
    @Test func mirrorDisplaysChangesMirroringFromShortcuts() throws {
        #expect(try actions.mirror(.turnOn))
        #expect(model.historyEntries.first?.source == .shortcuts)
        #expect(try !actions.mirror(.toggle))
        #expect(try !actions.mirror(.turnOff))
        #expect(service.mirroringRequests == [true, false, false])
    }

    /// With one display there is nothing to mirror.
    @Test func mirrorDisplaysNeedsTwoDisplays() throws {
        service.set([FakeDisplayService.builtIn])
        #expect(throws: ShortcutError.needsTwoDisplays) { try actions.mirror(.turnOn) }
        #expect(service.mirroringRequests.isEmpty)
    }

    /// A mirroring change that fails throws what its alert would have said, and shows none.
    @Test func aFailedMirroringChangeThrowsInsteadOfShowingAnAlert() throws {
        service.failsWith = .noDisplays
        #expect(throws: ShortcutError.failed(
            "Mirroring could not be changed. \(ResoluteError.noDisplays.localizedDescription)"
        )) {
            try actions.mirror(.turnOn)
        }
        #expect(errors.titles.isEmpty)
    }

    // MARK: - Keep/Revert questions

    /// While the app's Keep/Revert countdown is up, every change is refused with a message,
    /// and nothing more switches.
    @Test func everyChangeIsRefusedWhileACountdownIsUp() throws {
        let hidden = try #require(FakeDisplayService.dell.modes.first { $0.origin == .hidden })
        let target = try resolution(1496, 967, on: builtInID)
        let coding = try presetEntity("Coding")
        let builtIn = try displayEntity(builtInID)
        var refusals: [ShortcutError] = []
        answers.whileAsking = {
            for attempt in [
                { try actions.setResolution(target, on: nil) },
                { try actions.setRefreshRate(RefreshRateEntity(hertz: 60), on: builtIn) },
                { try actions.applyPreset(coding) },
                { try actions.mirror(.turnOn) },
                { try actions.openWindow() },
            ] as [() throws -> Any] {
                do {
                    _ = try attempt()
                } catch let error as ShortcutError {
                    refusals.append(error)
                } catch {}
            }
        }
        model.apply(hidden, to: FakeDisplayService.dell)
        #expect(refusals == Array(repeating: .busy, count: 5))
        #expect(service.changes.map(\.modeID) == [hidden.modeID, 201])
        #expect(service.mirroringRequests.isEmpty)
        #expect(shell.windows.isEmpty)
    }

    /// While an agent's Keep/Revert question is up, a change is refused too: it may be about
    /// the very display the shortcut would switch.
    @Test func aChangeIsRefusedWhileAnAgentsQuestionIsUp() async throws {
        let screen = FakeTrialScreen()
        let requests = screen.requests(clock: TrialTestClock())
        model.agentRequests = requests
        let request = ConfirmHiddenModeRequest(
            display: .init(name: "DELL U2723QE", id: 2, vendorID: 0x10AC, productID: 0x42A6, serialNumber: 0),
            mode: "2880 × 1620", modeID: 218, previousMode: "2560 × 1440", previousModeID: 201, trialSeconds: 8,
            requester: Requester(agent: "Claude Code", app: "Terminal")
        )
        let answer = Task { await requests.answer(request) }
        let dialog = try await screen.dialog()
        #expect(throws: ShortcutError.busy) {
            try actions.setResolution(resolution(1496, 967, on: builtInID), on: nil)
        }
        #expect(service.changes.isEmpty)
        dialog.revert()
        _ = await answer.value
        try actions.setResolution(resolution(1496, 967, on: builtInID), on: nil)
        #expect(service.changes.map(\.displayID) == [FakeDisplayService.builtInID])
    }

    /// The message Shortcuts shows for a refusal says what to do.
    @Test func theRefusalSaysWhatToDo() {
        #expect(ShortcutError.busy.message == "Resolute is asking whether to keep a display setting. Answer that first, then try again.")
        #expect(ShortcutError.busy.errorDescription == ShortcutError.busy.message)
    }

    // MARK: - Get Displays and Open Resolute

    /// Get Displays returns every display, main first, with its mode, or only the main one.
    @Test func getDisplaysReturnsTheDisplaysWithTheirModes() throws {
        let all = actions.displays(.all)
        #expect(all.map(\.name) == ["Built-in Retina Display", "DELL U2723QE"])
        #expect(all.map(\.summary) == ["1728 × 1117 · 120 Hz", "2560 × 1440 · 60 Hz"])
        #expect(all.map(\.isMain) == [true, false])
        #expect(all.map(\.isBuiltIn) == [true, false])
        #expect(actions.displays(.main).map(\.id) == [builtInID])
    }

    /// Open Resolute opens the window on the main display's page.
    @Test func openResoluteOpensTheWindow() throws {
        try actions.openWindow()
        #expect(shell.windows == [model.defaultRoute])
    }

    // MARK: - What Shortcuts offers

    /// The resolutions offered for a display are its listed ones, larger first, with its
    /// 1× sizes marked; with no display named, every display's.
    @Test func resolutionsOfferedAreEachDisplaysListedOnes() throws {
        let builtIn = ShortcutCatalog.resolutions(of: model.displays, onlyOn: builtInID)
        #expect(builtIn.map(\.sizeText) == ["3456 × 2234", "2056 × 1329", "1728 × 1117", "1728 × 1117", "1496 × 967", "1312 × 848"])
        #expect(builtIn.filter(\.isLowResolution).map(\.sizeText) == ["3456 × 2234", "1728 × 1117"])
        #expect(builtIn.allSatisfy { $0.displayName == "Built-in Retina Display" })
        let all = ShortcutCatalog.resolutions(of: model.displays, onlyOn: nil)
        #expect(all.count == builtIn.count + ShortcutCatalog.resolutions(of: model.displays, onlyOn: dellID).count)
    }

    /// A resolution's ID names its display and size, so a saved shortcut finds it again.
    @Test func aResolutionIsFoundAgainByItsID() throws {
        let original = try resolution(1496, 967, on: builtInID)
        let found = try #require(ShortcutCatalog.resolution(id: original.id, displays: model.displays))
        #expect(found.id == original.id)
        #expect(found.displayName == "Built-in Retina Display")
        #expect(ShortcutCatalog.resolution(id: "builtin|nonsense", displays: model.displays) == nil)
    }

    /// Displays keep their IDs across restarts; identical monitors without a serial number
    /// are told apart by display ID while connected.
    @Test func displayIDsTellIdenticalMonitorsApart() throws {
        #expect(builtInID == "builtin")
        #expect(ShortcutCatalog.display(for: dellID, in: model.displays)?.id == FakeDisplayService.dellID)
        var first = FakeDisplayService.dell
        first.serialNumber = 0
        var second = first
        second.id = 3
        let displays = [FakeDisplayService.builtIn, first, second]
        let ids = displays.map { ShortcutCatalog.identifier(of: $0, among: displays) }
        #expect(Set(ids).count == 3)
        #expect(ShortcutCatalog.display(for: ids[2], in: displays)?.id == 3)
        // One of the two gone, the other is still found by the ID it had.
        #expect(ShortcutCatalog.display(for: ids[2], in: [FakeDisplayService.builtIn, first])?.id == FakeDisplayService.dellID)
    }

    /// Refresh rates offered are the listed ones at each display's current resolution,
    /// fastest first, each once; their IDs are read back.
    @Test func refreshRatesOffered() {
        #expect(ShortcutCatalog.refreshRates(of: model.displays, onlyOn: nil).map(\.hertz) == [120, 60, 50, 48, 30])
        #expect(ShortcutCatalog.refreshRate(id: "5994")?.hertz == 59.94)
        #expect(ShortcutCatalog.refreshRate(id: "0") == nil)
        #expect(RefreshRateEntity(hertz: 120).id == "12000")
    }

    /// Presets are offered in their saved order, with their summaries; Siri finds one by
    /// part of its name.
    @Test func presetsOfferedAndFoundByName() {
        let presets = ShortcutCatalog.presets(model.presets)
        #expect(presets.map(\.name) == ["Coding", "Presenting", "Gaming"])
        #expect(presets.first?.summary == "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz")
        #expect(ShortcutCatalog.presets(presets, matching: "pres").map(\.name) == ["Presenting"])
        #expect(ShortcutCatalog.presets(presets, matching: " ").count == 3)
    }

    /// History offers its Shortcuts filter once a Shortcuts action has changed something.
    @Test func historyOffersTheShortcutsFilterAfterAnAction() throws {
        #expect(!HistoryFilter.offered(for: model.historyEntries).contains(.shortcuts))
        try actions.mirror(.turnOn)
        #expect(HistoryFilter.offered(for: model.historyEntries).contains(.shortcuts))
    }

    // MARK: - The intents

    /// Each intent's description is the one Shortcuts shows: it witnesses the protocol's.
    @Test func intentsDescribeThemselves() {
        func description<Intent: AppIntent>(_: Intent.Type) -> IntentDescription? { Intent.description }
        #expect(description(ApplyPresetIntent.self) != nil)
        #expect(description(SetResolutionIntent.self) != nil)
        #expect(description(OpenResoluteIntent.self) != nil)
    }

    /// The App Shortcuts are each intent but Get Displays' parameters.
    @Test func appShortcutsCoverTheActions() {
        #expect(ResoluteShortcuts.appShortcuts.count == 6)
    }

    /// Intents wait for the app model while the app finishes launching, then use it.
    @Test func intentsReachTheModelOnceTheAppHasMadeIt() async throws {
        let earlier = IntentHost.appModel
        defer { IntentHost.appModel = earlier }
        IntentHost.appModel = nil
        await #expect(throws: ShortcutError.notReady) {
            _ = try await IntentHost.readyModel(waitingUpTo: .milliseconds(10))
        }
        let model = model
        Task { @MainActor in IntentHost.appModel = model }
        #expect(try await IntentHost.readyModel() === model)
    }

    /// App Shortcuts are told to read their parameters again only when the presets or the
    /// resolutions change.
    @Test func shortcutParametersUpdateWhenPresetsChange() async throws {
        var updates = 0
        let parameters = ShortcutParameterUpdates { updates += 1 }
        parameters.start(model: model)
        defer { parameters.stop() }
        #expect(updates == 1)
        model.refresh()
        try await Task.sleep(for: .milliseconds(50))
        #expect(updates == 1)
        try model.updatePresets { library in _ = try library.add(Preset(name: "Reading", displays: PresetsSamples.figma[0].displays)) }
        let deadline = ContinuousClock.now + .seconds(5)
        while updates < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(updates == 2)
    }
}
