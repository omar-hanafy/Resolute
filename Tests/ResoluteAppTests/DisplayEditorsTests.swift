import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// The window's override editors: one per display, shared by its Custom Resolutions and
/// Picture & Name tabs, kept across pages and disconnects, and asked before quitting.
@MainActor
@Suite struct DisplayEditorsTests {
    let service = FakeDisplayService()
    let scratch = ScratchDefaults()
    let root = FileManager.default.temporaryDirectory.appending(
        path: "ResoluteDisplayEditorsTests-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    let model: AppModel

    var locations: OverrideLocations { .staged(at: root) }
    var dell: Display { FakeDisplayService.dell }
    var dellKey: OverrideKey { OverrideKey(display: dell) }
    var builtInKey: OverrideKey { OverrideKey(display: FakeDisplayService.builtIn) }

    /// Every icon file is on this Mac, but it lists no pictures: each Apple skin writes its
    /// icon only, and the ultrawide and TV skins have no artwork at all.
    static let everyIcon = DisplayIcons(appleIcons: [:], fileExists: { _ in true })

    init() {
        model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), overridesRoot: root
        )
    }

    func makeEditors(runner: any CommandRunning = ShellCommandRunner(), icons: DisplayIcons = everyIcon) -> DisplayEditors {
        DisplayEditors(
            model: model,
            store: OverrideStore(locations: locations),
            installer: OverrideInstaller(locations: locations, runner: runner),
            icons: icons
        )
    }

    func install(_ override: DisplayOverride) throws {
        let url = locations.userFile(for: override.key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try override.propertyListData().write(to: url)
    }

    let entry = ScaleResolution.hiDPI(width: 1600, height: 900, flags: .standard)

    /// Opening a display's page again, by its ID or its key, finds the same editor with
    /// its unsaved changes.
    @Test func keepsOneEditorPerDisplay() {
        let editors = makeEditors()
        let editor = editors.editor(for: dellKey)
        #expect(editor.add(entry) == nil)
        #expect(editors.editor(for: .id(dell.id)) === editor)
        #expect(editors.editor(for: .overrideKey(dellKey)) === editor)
        #expect(editors.editor(for: builtInKey) !== editor)
        #expect(editors.existingEditor(for: dellKey)?.hasChanges == true)
        #expect(editor.selection == dellKey)
    }

    /// The picture, the name and the custom resolutions are one draft, written by one save,
    /// after which the app reads the file again, so the panel and the header show the
    /// picture at once.
    @Test func savesPictureNameAndResolutionsTogether() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let editors = makeEditors()
        // The Custom Resolutions tab.
        let resolutions = try #require(editors.editor(for: .id(dell.id)))
        #expect(resolutions.add(entry) == nil)
        // The Picture & Name tab, on the same display.
        let pictureAndName = try #require(editors.editor(for: .id(dell.id)))
        #expect(pictureAndName.choosePicture("studioDisplay"))
        pictureAndName.productName = "Studio"
        #expect(resolutions.draft?.changes.count == 4)
        #expect(resolutions.unsavedMessage == "4 unsaved changes. Saving asks for an administrator password.")
        #expect(model.skin(for: dell) == .display)

        await editors.save(resolutions)

        let written = try #require(try OverrideStore(locations: locations).installedOverride(for: dellKey))
        #expect(written.productName == "Studio")
        #expect(written.resolutions.contains(entry))
        #expect(written.resolutions.contains(.standard(width: 3200, height: 1800)))
        #expect(DisplayIcons.skin(for: written.picture) == "studioDisplay")
        #expect(!resolutions.hasChanges)
        #expect(model.skin(for: dell) == .studioDisplay)
        #expect(model.overrideTargets.first { $0.key == dellKey }?.hasOverride == true)
    }

    /// Unplugging the display keeps its editor on it, with the edits, under Not Connected.
    @Test func keepsUnsavedChangesWhenTheDisplayIsUnplugged() {
        let editors = makeEditors()
        let editor = editors.editor(for: dellKey)
        #expect(editor.add(entry) == nil)
        service.set([FakeDisplayService.builtIn])
        model.displaysDidChange()
        editors.displaysDidChange()
        editor.refresh()
        #expect(editor.selection == dellKey)
        #expect(editor.hasChanges)
        #expect(editors.unsavedDisplayName == "DELL U2723QE")
        #expect(editors.key(for: .id(dell.id)) == nil)
        #expect(editors.editor(for: .overrideKey(dellKey)) === editor)
    }

    /// An editor belongs to its display: it never moves to another, even when asked.
    @Test func staysOnItsDisplay() {
        let editors = makeEditors()
        let editor = editors.editor(for: dellKey)
        editor.requestSelection(builtInKey)
        editor.select(builtInKey)
        #expect(editor.selection == dellKey)
        #expect(editor.pendingSelection == nil)
    }

    /// Quitting names every display whose changes it would lose.
    @Test func namesEveryDisplayWithUnsavedChanges() {
        let editors = makeEditors()
        #expect(editors.unsavedDisplayName == nil)
        #expect(editors.editor(for: dellKey).add(entry) == nil)
        #expect(editors.unsavedDisplayName == "DELL U2723QE")
        #expect(editors.editor(for: builtInKey).add(entry) == nil)
        #expect(editors.unsavedDisplayName == "Built-in Retina Display and DELL U2723QE")
    }

    /// While one override waits for the administrator password, no other save starts, and
    /// quitting is refused.
    @Test func refusesASecondSaveWhileOneIsWritten() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate()
        let editors = makeEditors(runner: GatedRunner(gate: gate))
        let first = editors.editor(for: dellKey)
        let second = editors.editor(for: builtInKey)
        #expect(first.add(entry) == nil)
        #expect(second.add(entry) == nil)

        let saving = Task { await editors.save(first) }
        while !first.isWorking { await Task.yield() }
        #expect(editors.isWorking)
        await editors.save(second)
        #expect(second.hasChanges)
        #expect(!second.isWorking)

        await gate.open()
        await saving.value
        #expect(!editors.isWorking)
        #expect(!first.hasChanges)
        #expect(second.hasChanges)
    }

    /// Remove Override… on another display while one override waits for the administrator
    /// password starts no second write, and says why.
    @Test func removesNothingWhileAnotherOverrideIsWritten() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try install(DisplayOverride(key: dellKey))
        let gate = Gate()
        let editors = makeEditors(runner: GatedRunner(gate: gate))
        let first = editors.editor(for: builtInKey)
        #expect(first.add(entry) == nil)
        let second = editors.editor(for: dellKey)
        #expect(second.canRemoveOverride)

        let saving = Task { await editors.save(first) }
        while !first.isWorking { await Task.yield() }
        // On its own, so a second write that did start waits behind the same prompt.
        let removing = Task { await second.removeOverride() }
        for _ in 0..<1000 where !second.isWorking && second.notice == nil { await Task.yield() }
        #expect(!second.isWorking)
        #expect(second.notice?.detail == "Another override is being written. Try again once it has finished.")

        await gate.open()
        await saving.value
        await removing.value
        #expect(FileManager.default.fileExists(atPath: locations.userFile(for: dellKey).path(percentEncoded: false)))
    }

    /// A picture this Mac has no artwork for can't be chosen; the one the file already has
    /// can always be chosen back.
    @Test func offersOnlyPicturesThisMacCanDraw() throws {
        let none = DisplayIcons(appleIcons: [:], fileExists: { _ in false })
        let editors = makeEditors(icons: none)
        let editor = editors.editor(for: dellKey)
        #expect(!editor.canChoosePicture("studioDisplay"))
        #expect(!editor.choosePicture("studioDisplay"))
        #expect(editor.canChoosePicture("display"))
        #expect(!editor.hasChanges)

        let choices = DisplayPagePresentation.pictureChoices(canChoose: editor.canChoosePicture)
        #expect(choices.map(\.title) == [
            "MacBook Pro", "iMac", "Studio Display", "Pro Display XDR", "Display (default)", "Ultrawide Display", "TV",
        ])
        #expect(choices.filter(\.isEnabled).map(\.title) == ["Display (default)"])
        #expect(choices.first { $0.model == .tv }?.help == "macOS has no picture of a TV to show in System Settings.")

        let some = DisplayPagePresentation.pictureChoices(canChoose: makeEditors().editor(for: dellKey).canChoosePicture)
        #expect(some.filter { !$0.isEnabled }.map(\.title) == ["Ultrawide Display", "TV"])
        #expect(DisplayPagePresentation.unavailablePicturesNote(some)
            == "This Mac has no picture for Ultrawide Display and TV, so macOS can't show them in System Settings.")
        #expect(DisplayPagePresentation.unavailablePicturesNote(some.filter(\.isEnabled)) == nil)
    }

    /// A display that is away is edited through its override file.
    @Test func editsADisplayThatIsAway() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let lg = SampleDisplays.lgUltraFine5K
        try install(lg.override)
        model.refresh()
        let editors = makeEditors()
        let editor = try #require(editors.editor(for: .overrideKey(lg.key)))
        #expect(editor.rows.map(\.entry) == lg.override.resolutions)
        #expect(editor.selectedTarget?.isConnected == false)
        #expect(editor.installedPath == locations.userFile(for: lg.key).path(percentEncoded: false))
    }
}
