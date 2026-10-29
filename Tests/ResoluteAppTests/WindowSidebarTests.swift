import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// The window's sidebar and routing: what it lists, in which order, and where choosing a row
/// or losing a display goes.
@MainActor
@Suite struct WindowSidebarTests {
    let service = FakeDisplayService()
    let scratch = ScratchDefaults()
    let root = FileManager.default.temporaryDirectory.appending(
        path: "ResoluteWindowSidebarTests-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    let lg = SampleDisplays.lgUltraFine5K

    var builtIn: Display { FakeDisplayService.builtIn }
    var dell: Display { FakeDisplayService.dell }

    func makeModel(installing overrides: [DisplayOverride] = []) throws -> AppModel {
        for override in overrides {
            let url = OverrideLocations.staged(at: root).userFile(for: override.key)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try override.propertyListData().write(to: url)
        }
        return AppModelTests.makeModel(service: service, preferences: Preferences(defaults: scratch.defaults), overridesRoot: root)
    }

    func makeEditors(_ model: AppModel) -> DisplayEditors {
        let locations = OverrideLocations.staged(at: root)
        return DisplayEditors(
            model: model,
            store: OverrideStore(locations: locations),
            installer: OverrideInstaller(locations: locations, runner: RefusingRunner())
        )
    }

    /// Figma 31:5: the connected displays, the main one marked; the displays away with an
    /// override; then Presets with its count, History and Settings.
    @Test func listsDisplaysThenDisplaysAwayThenResolute() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel(installing: [lg.override])
        for name in ["Desk", "Presenting", "Reading"] {
            _ = try model.saveCurrentSetupAsPreset(named: name)
        }
        let content = SidebarContent(model: model, editors: makeEditors(model))

        #expect(content.displays.map(\.title) == ["Built-in Retina Display", "DELL U2723QE"])
        #expect(content.displays.map(\.destination) == [.display(.id(builtIn.id)), .display(.id(dell.id))])
        #expect(content.displays.map(\.detail) == ["Main", nil])
        #expect(content.displays.map(\.symbol) == [.laptopcomputer, .display])
        #expect(content.notConnected.map(\.destination) == [.display(.overrideKey(lg.key))])
        #expect(content.notConnected.allSatisfy { $0.isDimmed })
        #expect(content.resolute.map(\.title) == ["Presets", "History", "Settings"])
        #expect(content.resolute.map(\.detail) == ["3", nil, nil])
    }

    /// One display has the menu bar alone, so it isn't marked; without displays away there
    /// is no Not Connected.
    @Test func marksTheMainDisplayOnlyBesideAnother() throws {
        service.set([dell])
        let model = try makeModel()
        let content = SidebarContent(model: model, editors: makeEditors(model))
        #expect(content.displays.map(\.detail) == [nil])
        #expect(content.notConnected.isEmpty)
        #expect(content.resolute.first?.detail == nil)
    }

    /// A display away with unsaved changes stays listed, even without an override file,
    /// under the name History recorded for it.
    @Test func listsADisplayAwayWithUnsavedChanges() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try makeModel()
        let editors = makeEditors(model)
        let key = OverrideKey(display: dell)
        model.apply(try #require(dell.modes.first { $0.modeID != dell.currentModeID && $0.origin == .system }), to: dell, from: .window)
        #expect(editors.editor(for: key).add(.standard(width: 1280, height: 720)) == nil)
        service.set([builtIn])
        model.displaysDidChange()
        let content = SidebarContent(model: model, editors: editors)
        #expect(content.notConnected.map(\.destination) == [.display(.overrideKey(key))])
        #expect(content.notConnected.map(\.title) == ["DELL U2723QE"])
    }

    /// The route's display row is selected, also when the route names it by its key.
    @Test func selectsTheRouteRow() throws {
        let model = try makeModel()
        let key = OverrideKey(display: dell)
        #expect(SidebarContent.destination(for: .display(.overrideKey(key), tab: .pictureAndName), model: model)
            == .display(.id(dell.id)))
        #expect(SidebarContent.destination(for: .display(.id(builtIn.id)), model: model) == .display(.id(builtIn.id)))
        #expect(SidebarContent.destination(for: .settings(.about), model: model) == .settings)
        #expect(SidebarContent.destination(for: .history, model: model) == .history)
        #expect(SidebarContent.destination(for: .display(.overrideKey(lg.key)), model: model) == .display(.overrideKey(lg.key)))
    }

    /// Choosing another display keeps the tab the window is on; a display away has no
    /// Resolution tab; Settings keeps its tab.
    @Test func keepsTheTabWhenChoosingAnotherDisplay() throws {
        let model = try makeModel()
        let current = AppRoute.display(.id(builtIn.id), tab: .pictureAndName)
        #expect(SidebarContent.route(for: .display(.id(dell.id)), from: current, model: model)
            == .display(.id(dell.id), tab: .pictureAndName))
        #expect(SidebarContent.route(for: .display(.id(dell.id)), from: .history, model: model)
            == .display(.id(dell.id), tab: .resolution))
        #expect(SidebarContent.route(for: .display(.overrideKey(lg.key)), from: .display(.id(dell.id)), model: model)
            == .display(.overrideKey(lg.key), tab: .customResolutions))
        #expect(SidebarContent.route(for: .settings, from: .settings(.about), model: model) == .settings(.about))
        #expect(SidebarContent.route(for: .settings, from: .presets, model: model) == .settings(.general))
        #expect(SidebarContent.route(for: .presets, from: current, model: model) == .presets)
    }

    /// The tabs: a display away has Custom Resolutions and Picture & Name only.
    @Test func offersTheTabsADisplayHas() {
        #expect(DisplayPagePresentation.tabs(isConnected: true) == [.resolution, .customResolutions, .pictureAndName])
        #expect(DisplayPagePresentation.tabs(isConnected: false) == [.customResolutions, .pictureAndName])
        #expect(DisplayPagePresentation.tab(.resolution, isConnected: false) == .customResolutions)
        #expect(DisplayPagePresentation.tab(.pictureAndName, isConnected: false) == .pictureAndName)
        #expect(DisplayPagePresentation.tab(.resolution, isConnected: true) == .resolution)
    }

    /// When the page's display is unplugged, the window follows it under Not Connected if
    /// it has an override or unsaved changes, and otherwise goes to the main display.
    @Test(arguments: [false, true])
    func followsAnUnpluggedDisplay(hasOverride: Bool) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let key = OverrideKey(display: dell)
        let model = try makeModel(installing: hasOverride ? [DisplayOverride(key: key, resolutions: [.standard(width: 1280, height: 720)])] : [])
        let editors = makeEditors(model)
        let before = model.displays
        service.set([builtIn])
        model.displaysDidChange()
        let route = AppRoute.display(.id(dell.id), tab: .resolution)
        let next = WindowRouting.route(route, afterDisplaysChangedFrom: before, model: model, editors: editors)
        #expect(next == (hasOverride ? .display(.overrideKey(key), tab: .customResolutions) : .display(.id(builtIn.id))))
        // The main display's page stays.
        #expect(WindowRouting.route(.display(.id(builtIn.id)), afterDisplaysChangedFrom: before, model: model, editors: editors) == nil)
        #expect(WindowRouting.route(.history, afterDisplaysChangedFrom: before, model: model, editors: editors) == nil)
    }

    @Test func followsAnUnpluggedDisplayWithUnsavedChanges() throws {
        let model = try makeModel()
        let editors = makeEditors(model)
        let key = OverrideKey(display: dell)
        #expect(editors.editor(for: key).add(.standard(width: 1280, height: 720)) == nil)
        let before = model.displays
        service.set([builtIn])
        model.displaysDidChange()
        let next = WindowRouting.route(
            .display(.id(dell.id), tab: .pictureAndName), afterDisplaysChangedFrom: before, model: model, editors: editors
        )
        #expect(next == .display(.overrideKey(key), tab: .pictureAndName))
    }
}
