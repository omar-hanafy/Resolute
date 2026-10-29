import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// The Presets page's logic: its cards in order with the active one, and every change it
/// makes through the presets file.
@MainActor
@Suite struct PresetsPageTests {
    let scratch = ScratchDefaults()
    let errors = ShownErrors()
    let root = FileManager.default.temporaryDirectory.appending(
        path: "ResolutePresetsPageTests-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    let preferences: Preferences
    let service: FakeDisplayService
    let model: AppModel
    let page: PresetsPageModel

    init() throws {
        // The built-in display at 1496 × 967, so Figma's Coding is the active preset.
        var builtIn = FakeDisplayService.builtIn
        builtIn.currentModeID = try #require(builtIn.modes.first { $0.width == 1496 && $0.refreshRate == 120 }).modeID
        service = FakeDisplayService(displays: [builtIn, FakeDisplayService.dell])
        preferences = Preferences(defaults: scratch.defaults)
        model = AppModelTests.makeModel(service: service, preferences: preferences, errors: errors, overridesRoot: root)
        try model.updatePresets { library in
            for preset in PresetsSamples.figma { try library.add(preset) }
        }
        page = PresetsPageModel(app: model)
    }

    func preset(_ name: String) throws -> Preset {
        try #require(page.presets.first { $0.name == name })
    }

    @Test func listsThePresetsInTheirSavedOrderWithTheActiveOne() throws {
        #expect(page.presets.map(\.name) == ["Coding", "Presenting", "Gaming"])
        #expect(page.presets.map(page.isActive) == [true, false, false])
        #expect(try preset("Coding").shortcut?.displayText == "⌃⌥1")
    }

    @Test func appliesAPresetFromTheWindow() throws {
        page.apply(try preset("Gaming"))
        #expect(page.presets.map(page.isActive) == [false, false, true])
        #expect(model.historyEntries.first?.source == .preset(name: "Gaming", via: .window))
        #expect(errors.titles.isEmpty)
    }

    @Test func savesTheCurrentSetupAndAsksForItsName() throws {
        page.newPresetFromCurrentSetup()
        #expect(page.presets.map(\.name) == ["Coding", "Presenting", "Gaming", "New Preset"])
        #expect(page.renaming?.name == "New Preset")
        #expect(page.newName == "New Preset")
        page.newName = "  Desk "
        #expect(page.commitRename())
        #expect(page.renaming == nil)
        #expect(page.presets.map(\.name) == ["Coding", "Presenting", "Gaming", "Desk"])
        // The new preset is the setup as it is now, so it is active with Coding.
        #expect(page.isActive(try preset("Desk")))
    }

    @Test func renamesKeepingThePresetsPlaceAndShortcut() throws {
        let coding = try preset("Coding")
        page.beginRename(coding)
        page.newName = "Writing"
        #expect(page.commitRename())
        let renamed = try #require(page.presets.first)
        #expect(renamed.id == coding.id && renamed.name == "Writing" && renamed.shortcut == coding.shortcut)
        #expect(errors.titles.isEmpty)
    }

    @Test func refusesANameAnotherPresetHas() throws {
        #expect(!page.rename(try preset("Gaming"), to: "coding"))
        #expect(errors.titles == ["The preset could not be renamed"])
        #expect(page.presets.map(\.name) == ["Coding", "Presenting", "Gaming"])
        #expect(!page.rename(try preset("Gaming"), to: "   "))
        #expect(errors.titles.count == 2)
    }

    @Test func deletesOnlyAfterAsking() throws {
        let presenting = try preset("Presenting")
        page.beginDelete(presenting)
        #expect(page.deleting == presenting)
        #expect(page.presets.count == 3)
        page.delete(presenting)
        #expect(page.deleting == nil)
        #expect(page.presets.map(\.name) == ["Coding", "Gaming"])
        // Deleted from the command line in the meantime: nothing to say.
        page.delete(presenting)
        #expect(errors.titles.isEmpty)
    }

    @Test func setsAndClearsAShortcut() throws {
        let gaming = try preset("Gaming")
        let shortcut = try #require(KeyShortcut(key: "g", modifiers: [.control, .option]))
        page.setShortcut(shortcut, for: gaming)
        #expect(try preset("Gaming").shortcut == shortcut)
        page.setShortcut(nil, for: gaming)
        #expect(try preset("Gaming").shortcut == nil)
        // Another preset's shortcut is refused by the file too.
        page.setShortcut(try preset("Coding").shortcut, for: gaming)
        #expect(errors.titles == ["The shortcut could not be changed"])
        #expect(try preset("Gaming").shortcut == nil)
    }

    @Test func saysWhatAlreadyHasAShortcut() throws {
        let gaming = try preset("Gaming")
        let coding = try preset("Coding")
        #expect(page.shortcutConflict(.openPanel, for: gaming) == "⌃⌥R already opens the panel.")
        #expect(page.shortcutConflict(try #require(coding.shortcut), for: gaming) == "⌃⌥1 is already the shortcut for “Coding”.")
        // A preset's own shortcut is no conflict.
        #expect(page.shortcutConflict(try #require(coding.shortcut), for: coding) == nil)
        #expect(page.shortcutConflict(try #require(KeyShortcut(key: "9", modifiers: [.command, .option])), for: gaming) == nil)
        // The panel's recorder ignores the panel's own shortcut, not the presets'.
        #expect(model.shortcutConflict(.openPanel, ignoring: .panel) == nil)
        #expect(model.shortcutConflict(try #require(coding.shortcut), ignoring: .panel) != nil)
        preferences.panelShortcut = nil
        #expect(page.shortcutConflict(.openPanel, for: gaming) == nil)
    }

    @Test func importsPresetsWithFreeNamesAndShortcuts() throws {
        let file = root.appending(path: "Exported.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let travel = Preset(
            name: "Travel", displays: [DisplaySetting(display: DisplayReference(FakeDisplayService.builtIn), refreshRate: 60)],
            shortcut: KeyShortcut(key: "t", modifiers: [.control, .option])
        )
        let exported = PresetLibrary(presets: PresetsSamples.figma + [travel, Preset(
            name: "Panel Key", displays: travel.displays, shortcut: .openPanel
        )])
        try exported.data().write(to: file)
        page.chooseImportFile = { file }
        page.importPresets()
        #expect(errors.titles.isEmpty)
        #expect(page.presets.map(\.name) == ["Coding", "Presenting", "Gaming", "Coding 2", "Presenting 2", "Gaming 2", "Travel", "Panel Key"])
        // Shortcuts that were taken are left off; a free one comes along.
        #expect(page.presets[3...].map(\.shortcut) == [nil, nil, nil, travel.shortcut, nil])
        // Every imported preset has an ID of its own.
        #expect(Set(page.presets.map(\.id)).count == page.presets.count)
    }

    @Test func saysWhenAFileHasNoPresets() throws {
        let file = root.appending(path: "Empty.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try PresetLibrary().data().write(to: file)
        #expect(page.importPresets(from: file) == 0)
        #expect(page.importPresets(from: root.appending(path: "Missing.json")) == 0)
        #expect(errors.titles == ["The presets could not be imported", "The presets could not be imported"])
        #expect(page.presets.count == 3)
        // Cancelling the open panel imports nothing and says nothing.
        page.chooseImportFile = { nil }
        page.importPresets()
        #expect(errors.titles.count == 2)
    }
}
