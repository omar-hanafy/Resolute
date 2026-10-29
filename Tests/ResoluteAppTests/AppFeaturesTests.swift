import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// History and presets through the app model: what the panel and the window rely on.
@MainActor
@Suite struct AppFeaturesTests {
    let service = FakeDisplayService()
    let scratch = ScratchDefaults()
    let answers = TrialAnswers()
    let errors = ShownErrors()
    let root = FileManager.default.temporaryDirectory.appending(
        path: "ResoluteAppFeaturesTests-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    let model: AppModel

    init() {
        model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), answers: answers, errors: errors,
            overridesRoot: root
        )
    }

    var dell: Display { FakeDisplayService.dell }

    func listedMode(_ display: Display) throws -> DisplayMode {
        try #require(display.modes.first { $0.origin != .hidden && $0.modeID != display.currentModeID && $0.isHiDPI == display.currentMode?.isHiDPI })
    }

    // MARK: - History

    @Test func recordsASwitchWithWhereItWasAskedFor() throws {
        let mode = try listedMode(dell)
        model.apply(mode, to: dell, from: .window)
        let entry = try #require(model.historyEntries.first)
        #expect(model.historyEntries.count == 1)
        #expect(entry.source == .window)
        #expect(entry.outcome == .applied)
        guard case .mode(let change) = entry.change else { Issue.record("not a mode change"); return }
        #expect(change.to.modeID == mode.modeID && change.from?.modeID == dell.currentModeID)
    }

    @Test func recordsWhyATrialWasRevertedAndSaysSoOnTheDisplay() throws {
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        answers.keeps = false
        model.apply(hidden, to: dell)
        // The person chose Revert before the countdown ended.
        #expect(model.historyEntries.map(\.outcome) == [.reverted(.declined)])
        #expect(answers.outcomes == [.switchedBack])
        #expect(try #require(model.displays.first { $0.id == dell.id }).currentModeID == dell.currentModeID)
    }

    @Test func undoPutsBackWhatAChangeReplaced() throws {
        let mode = try listedMode(dell)
        model.apply(mode, to: dell)
        let change = try #require(model.historyEntries.first)
        #expect(model.historyTimeline.canUndo(change))
        model.undo(change, from: .window)
        #expect(try #require(model.displays.first { $0.id == dell.id }).currentModeID == dell.currentModeID)
        #expect(model.historyTimeline.status(of: change) == .undone)
        #expect(!model.historyTimeline.canUndo(change))
        // Undoing again says why not, and changes nothing.
        let switches = service.changes.count
        model.undo(change)
        #expect(service.changes.count == switches)
        #expect(errors.titles.last == "The change can’t be undone")
    }

    @Test func readsWhatTheCommandLineAdded() throws {
        let mode = try listedMode(dell)
        let terminal = HistoryRecorder(store: HistoryStore(locations: model.support), source: .agent(name: "Claude Code", app: "Terminal"))
        terminal.recordSwitch(of: dell, to: mode, outcome: .applied)
        #expect(model.lastOutsideActivity() == nil)
        model.refresh()
        let activity = try #require(model.lastOutsideActivity())
        #expect(activity.entry.source == .agent(name: "Claude Code", app: "Terminal"))
    }

    @Test func recordsMirroringOnlyWhenItChanges() {
        model.setMirroring(true, from: .menu)
        model.setMirroring(true, from: .menu)
        #expect(model.historyEntries.count == 1)
        #expect(model.historyEntries.first?.source == .menu)
    }

    // MARK: - Presets

    @Test func savesTheCurrentSetupAndAppliesItBack() throws {
        let preset = try model.saveCurrentSetupAsPreset(named: "Desk")
        #expect(model.presets.map(\.name) == ["Desk"])
        #expect(model.isActive(preset))
        model.apply(try listedMode(dell), to: dell)
        #expect(!model.isActive(preset))
        model.applyPreset(preset, from: .panel)
        #expect(model.isActive(preset))
        #expect(errors.titles.isEmpty)
        // The switch back is in History as the preset's.
        #expect(model.historyEntries.first?.source == .preset(name: "Desk", via: .panel))
    }

    /// `resolute preset delete` while the app still lists the preset: choosing it, from a
    /// shortcut or a menu built before, applies nothing and says why.
    @Test func appliesNoPresetDeletedOutsideTheApp() throws {
        let preset = try model.saveCurrentSetupAsPreset(named: "Desk")
        model.apply(try listedMode(dell), to: dell)
        let switches = service.changes.count
        try PresetStore(locations: model.support).update { library in _ = try library.delete(named: "Desk") }
        model.applyPreset(preset, from: .keyboard)
        #expect(service.changes.count == switches)
        #expect(errors.titles == ["“Desk” could not be applied"])
        #expect(model.presets.isEmpty)
        #expect(model.historyEntries.first?.source != .preset(name: "Desk", via: .keyboard))
    }

    /// A presets file that can't be read, after a bad hand edit: nothing is applied from what
    /// the app read before, as `resolute preset apply` applies nothing, and the alert says why.
    @Test func appliesNoPresetWhileItsFileCantBeRead() throws {
        let preset = try model.saveCurrentSetupAsPreset(named: "Desk")
        model.apply(try listedMode(dell), to: dell)
        let switches = service.changes.count
        let store = PresetStore(locations: model.support)
        try Data("{ not a presets file".utf8).write(to: store.file)

        model.applyPreset(preset, from: .keyboard)

        #expect(service.changes.count == switches)
        #expect(errors.titles == ["“Desk” could not be applied"])
        let message = try #require(errors.messages.first)
        #expect(message.contains(store.file.lastPathComponent))
    }

    /// `resolute preset save --replace` while the app still lists the old setup: the preset
    /// applied is the one the file holds now.
    @Test func appliesAPresetAsItsFileHoldsItNow() throws {
        let stale = try model.saveCurrentSetupAsPreset(named: "Desk")
        let listed = try listedMode(dell)
        model.apply(listed, to: dell)
        let displays = model.displays
        try PresetStore(locations: model.support).update { library in
            _ = try library.save(PresetCapture(displays: displays), named: "Desk", replacing: true)
        }
        let original = try #require(FakeDisplayService.dell.currentModeID)
        try service.apply(modeID: original, to: dell.id, scope: .permanent)
        model.applyPreset(stale)
        #expect(service.currentModeID(of: dell.id) == listed.modeID)
        #expect(errors.titles.isEmpty)
    }

    @Test func picksAFreeNameForEachNewPreset() throws {
        try model.saveCurrentSetupAsPreset()
        try model.saveCurrentSetupAsPreset()
        #expect(model.presets.map(\.name) == ["New Preset", "New Preset 2"])
        try model.updatePresets { library in _ = try library.rename("New Preset 2", to: "Gaming") }
        #expect(model.presets.map(\.name) == ["New Preset", "Gaming"])
    }

    @Test func appliesNoPresetWhileACountdownIsUp() throws {
        let preset = try model.saveCurrentSetupAsPreset(named: "Desk")
        model.apply(try listedMode(dell), to: dell)
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        let switches = service.changes.count
        answers.whileAsking = { model.applyPreset(preset) }
        model.apply(hidden, to: dell)
        // Only the trial and its revert: the preset chosen during the countdown did nothing.
        #expect(service.changes.count == switches + 2)
    }
}
