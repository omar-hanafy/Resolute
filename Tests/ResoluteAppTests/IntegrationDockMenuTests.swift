import AppKit
import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// The Dock menu, built from the fake displays and Figma's presets; its items run through the
/// app model with the Dock as their source.
@MainActor
@Suite struct IntegrationDockMenuTests {
    let service = FakeDisplayService()
    let scratch = ScratchDefaults()
    let model: AppModel

    init() throws {
        model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults),
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteDockTests-\(UUID().uuidString)")
        )
        try model.updatePresets { library in
            for preset in PresetsSamples.figma { try library.add(preset) }
        }
    }

    func item(_ title: String, in menu: NSMenu) throws -> NSMenuItem {
        let all = menu.items + menu.items.compactMap(\.submenu).flatMap(\.items)
        return try #require(all.first { $0.title == title })
    }

    func perform(_ item: NSMenuItem) {
        DockMenuAction.shared.perform(item)
    }

    @Test func listsEachDisplaysSizesAtHandItsRefreshRateThenPresetsAndMirroring() {
        let menu = DockMenu.make(model: model)
        #expect(MenuRenderer.describe(menu) == """
            # Built-in Retina Display
            ✓ 1728 × 1117 — Default
              1496 × 967
              Refresh Rate: 120 Hz ▸
                ✓ 120 Hz
                  60 Hz
                  50 Hz
                  48 Hz
            ---
            # DELL U2723QE
            ✓ 2560 × 1440
              1920 × 1080 — Default
              Refresh Rate: 60 Hz ▸
                ✓ 60 Hz
                  50 Hz
                  30 Hz
            ---
              Presets ▸
                  Coding
                  Presenting
                  Gaming
              Mirror Displays
            """)
    }

    @Test func aSizeSwitchesTheDisplayFromTheDock() throws {
        perform(try item("1496 × 967", in: DockMenu.make(model: model)))
        let change = try #require(service.changes.last)
        #expect(change.displayID == FakeDisplayService.builtInID)
        #expect(model.displays.first { $0.id == FakeDisplayService.builtInID }?.currentMode?.width == 1496)
        #expect(model.historyEntries.first?.source == .dock)
    }

    @Test func aRefreshRateSwitchesFromTheDock() throws {
        perform(try item("60 Hz", in: try #require(try item("Refresh Rate: 120 Hz", in: DockMenu.make(model: model)).submenu)))
        #expect(model.displays.first { $0.id == FakeDisplayService.builtInID }?.currentMode?.refreshRate == 60)
        #expect(model.historyEntries.first?.source == .dock)
    }

    @Test func aPresetIsAppliedFromTheDock() throws {
        perform(try item("Coding", in: DockMenu.make(model: model)))
        #expect(model.isActive(try #require(model.presets.first { $0.name == "Coding" })))
        #expect(model.historyEntries.first?.source.origin == .dock)
        #expect(model.historyEntries.first?.source.presetName == "Coding")
    }

    @Test func mirrorDisplaysTurnsMirroringOnFromTheDock() throws {
        perform(try item("Mirror Displays", in: DockMenu.make(model: model)))
        #expect(service.mirroringRequests == [true])
        #expect(model.historyEntries.first?.source == .dock)
    }

    /// A rate the Dock lists comes from a listed mode, and the Dock switches to a listed
    /// one, even where a hidden mode at that rate matches the bit depth better: nothing is
    /// tried from the Dock, where nobody may look.
    @Test func aRefreshRateSwitchesToAListedModeOnly() throws {
        var dell = FakeDisplayService.dell
        dell.modes = [
            DisplayMode(modeID: 100, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 60, bitsPerSample: 10),
            DisplayMode(modeID: 101, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 50, bitsPerSample: 8),
            DisplayMode(
                modeID: 102, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 50, bitsPerSample: 10,
                origin: .hidden
            ),
        ]
        dell.currentModeID = 100
        let service = FakeDisplayService(displays: [FakeDisplayService.builtIn, dell])
        let answers = TrialAnswers()
        let model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), answers: answers,
            overridesRoot: FileManager.default.temporaryDirectory.appending(path: "ResoluteDockTests-\(UUID().uuidString)")
        )
        let menu = DockMenu.make(model: model)
        let rates = try #require(menu.items.first { $0.title == "Refresh Rate: 60 Hz" })
        perform(try #require(rates.submenu?.items.first { $0.title == "50 Hz" }))
        #expect(service.changes.map(\.modeID) == [101])
        #expect(answers.asked.isEmpty)
    }

    @Test func hiddenModesStayOutOfTheDockMenu() {
        let dell = FakeDisplayService.dell
        let sizes = DockMenu.sizes(of: dell, presets: [], displays: [dell])
        #expect(!sizes.contains { $0.mode.origin == .hidden })
        #expect(sizes.map(\.title) == ["2560 × 1440", "1920 × 1080 — Default"])
    }

    @Test func aHiddenModeInUseIsShownChecked() throws {
        var dell = FakeDisplayService.dell
        let hidden = try #require(dell.modes.first { $0.origin == .hidden })
        dell.currentModeID = hidden.modeID
        let sizes = DockMenu.sizes(of: dell, presets: [], displays: [dell])
        #expect(sizes.first { $0.isCurrent }?.title == "2880 × 1620")
    }

    @Test func oneDisplayHasNoMirroringAndNoPresetsMeansNoPresetsMenu() throws {
        service.set([FakeDisplayService.builtIn])
        try model.updatePresets { library in
            for preset in library.presets { _ = library.delete(id: preset.id) }
        }
        let menu = DockMenu.make(model: model)
        #expect(!menu.items.contains { $0.title == "Mirror Displays" || $0.title == "Presets" })
        #expect(menu.items.last?.isSeparatorItem == false)
    }
}
