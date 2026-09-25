import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// Displays the editor can see; tests change the list to simulate unplugging.
final class StubDisplays: DisplayControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [Display]

    init(_ displays: [Display]) {
        list = displays
    }

    func set(_ displays: [Display]) {
        lock.withLock { list = displays }
    }

    func displays() -> [Display] { lock.withLock { list } }
    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? { nil }
    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {}
    func setMirroring(_ enabled: Bool) throws {}
}

/// Holds every script until `open()` is called, like an administrator password prompt.
actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting.removeAll()
    }
}

struct GatedRunner: CommandRunning {
    let gate: Gate

    func run(_ script: String) async throws {
        await gate.wait()
        try await ShellCommandRunner().run(script)
    }
}

@MainActor
@Suite struct CustomResolutionsModelTests {
    let first = Display(id: 5, name: "First", vendorID: 0x10AC, productID: 0x1111, currentModeID: nil, modes: [])
    let second = Display(id: 6, name: "Second", vendorID: 0x10AC, productID: 0x2222, currentModeID: nil, modes: [])

    func makeModel(root: URL, displays: StubDisplays, runner: any CommandRunning = ShellCommandRunner()) -> CustomResolutionsModel {
        let locations = OverrideLocations.staged(at: root)
        return CustomResolutionsModel(
            service: displays,
            store: OverrideStore(locations: locations),
            installer: OverrideInstaller(locations: locations, runner: runner)
        )
    }

    func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ResoluteAppTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ override: DisplayOverride, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try override.propertyListData().write(to: url)
    }

    /// Writes `override` where the staged store looks for an installed one.
    func install(_ override: DisplayOverride, under root: URL) throws {
        try write(override, to: OverrideLocations.staged(at: root).userFile(for: override.key))
    }

    let hd = ScaleResolution.hiDPI(width: 1920, height: 1080, flags: .standard)
    let qhd = ScaleResolution.hiDPI(width: 2560, height: 1440, flags: .standard)

    @Test func switchesFreelyWithoutChanges() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root, displays: StubDisplays([first, second]))
        model.requestSelection(OverrideKey(display: second))
        #expect(model.selection == OverrideKey(display: second))
        #expect(model.pendingSelection == nil)
    }

    @Test func asksBeforeDroppingUnsavedChanges() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root, displays: StubDisplays([first, second]))
        #expect(model.add(.hiDPI(width: 1920, height: 1080, flags: .standard)) == nil)
        model.requestSelection(OverrideKey(display: second))
        #expect(model.selection == OverrideKey(display: first))
        #expect(model.pendingSelection == OverrideKey(display: second))
        #expect(model.hasChanges)

        model.cancelPendingSelection()
        #expect(model.pendingSelection == nil)
        #expect(model.hasChanges)

        model.requestSelection(OverrideKey(display: second))
        model.discardChangesAndSelectPending()
        #expect(model.selection == OverrideKey(display: second))
        #expect(!model.hasChanges)
    }

    @Test func menuRequestsAskToo() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root, displays: StubDisplays([first, second]))
        _ = model.add(.hiDPI(width: 1920, height: 1080, flags: .standard))
        model.select(displayID: second.id)
        #expect(model.selection == OverrideKey(display: first))
        #expect(model.pendingSelection == OverrideKey(display: second))
    }

    @Test func keepsAnEditedDisplayThatIsUnplugged() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let displays = StubDisplays([first, second])
        let model = makeModel(root: root, displays: displays)
        _ = model.add(.hiDPI(width: 1920, height: 1080, flags: .standard))
        displays.set([second])
        model.reloadTargets()
        #expect(model.selection == OverrideKey(display: first))
        #expect(model.hasChanges)
        #expect(model.targets.contains { $0.key == OverrideKey(display: first) && !$0.isConnected })
    }

    @Test func holdsStillWhileSaving() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate()
        let model = makeModel(root: root, displays: StubDisplays([first, second]), runner: GatedRunner(gate: gate))
        _ = model.add(.hiDPI(width: 1920, height: 1080, flags: .standard))
        let written = try #require(model.draft?.working)

        let save = Task { await model.save() }
        while !model.isWorking { await Task.yield() }
        #expect(model.add(.hiDPI(width: 2560, height: 1440, flags: .standard)) != nil)
        model.productName = "Renamed"
        model.revert()
        model.requestSelection(OverrideKey(display: second))
        #expect(model.selection == OverrideKey(display: first))
        #expect(model.draft?.working == written)

        await gate.open()
        await save.value
        #expect(!model.hasChanges)
        let stored = try OverrideStore(locations: .staged(at: root)).installedOverride(for: OverrideKey(display: first))
        #expect(stored?.resolutions == written.resolutions)
    }

    // MARK: - Selection

    /// Rows used to be selected by position, so once an add re-sorted the list the
    /// selection sat on another entry, and Remove deleted that one.
    @Test func removesTheSelectedEntryAfterTheListIsResorted() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(root: root, displays: StubDisplays([first, second]))
        _ = model.add(hd)
        model.selectedEntries = [hd]
        _ = model.add(qhd)
        #expect(model.rows.map(\.entry) == [
            .standard(width: 5120, height: 2880), .standard(width: 3840, height: 2160), qhd, hd,
        ])
        #expect(model.selectedEntries == [hd])

        model.removeSelection()
        // The 1× partner added with the entry goes with it; nothing else does.
        #expect(model.rows.map(\.entry) == [.standard(width: 5120, height: 2880), qhd])
        #expect(model.selectedEntries.isEmpty)
    }

    @Test func revertClearsTheSelection() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let native = ScaleResolution.standard(width: 2560, height: 1440)
        try install(DisplayOverride(key: OverrideKey(display: first), resolutions: [native]), under: root)
        let model = makeModel(root: root, displays: StubDisplays([first, second]))
        _ = model.add(hd)
        model.selectedEntries = [native, hd]

        model.revert()
        #expect(model.selectedEntries.isEmpty)
        model.removeSelection()
        #expect(model.rows.map(\.entry) == [native])
    }

    @Test func switchingDisplaysClearsTheSelection() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        for display in [first, second] {
            try install(DisplayOverride(key: OverrideKey(display: display), resolutions: [hd]), under: root)
        }
        let model = makeModel(root: root, displays: StubDisplays([first, second]))
        model.selectedEntries = [hd]

        model.requestSelection(OverrideKey(display: second))
        #expect(model.selectedEntries.isEmpty)
        model.removeSelection()
        #expect(model.rows.map(\.entry) == [hd])
    }

    /// Remove and Delete share this: offered for a selection, and never while saving.
    @Test func removingTheSelectionWaitsForTheSave() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = Gate()
        let model = makeModel(root: root, displays: StubDisplays([first, second]), runner: GatedRunner(gate: gate))
        _ = model.add(hd)
        #expect(!model.canRemoveSelection)
        model.selectedEntries = [hd]
        #expect(model.canRemoveSelection)

        let save = Task { await model.save() }
        while !model.isWorking { await Task.yield() }
        #expect(!model.canRemoveSelection)
        model.removeSelection()
        #expect(model.rows.map(\.entry) == [.standard(width: 3840, height: 2160), hd])

        await gate.open()
        await save.value
        #expect(model.canRemoveSelection)
    }

    /// After Remove Override… the list is read again, here from Apple's file, which has
    /// the entry that was selected.
    @Test func readingTheOverrideAgainClearsTheSelection() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = OverrideKey(display: first)
        try write(DisplayOverride(key: key, resolutions: [hd]), to: OverrideLocations.staged(at: root).systemFile(for: key))
        try install(DisplayOverride(key: key, resolutions: [qhd, hd]), under: root)
        let model = makeModel(root: root, displays: StubDisplays([first, second]))
        model.selectedEntries = [hd]

        await model.removeOverride()
        #expect(model.source == .system)
        #expect(model.rows.map(\.entry) == [hd])
        #expect(model.selectedEntries.isEmpty)
    }

    // MARK: - Unreadable overrides

    enum Breakage: CaseIterable, Sendable {
        case notAPropertyList, folder, noPermission

        /// Root can read any file, so there the permission case cannot be staged.
        static var stageable: [Breakage] { geteuid() == 0 ? [.notAPropertyList, .folder] : allCases }
    }

    /// Puts an override file at `url` that cannot be read.
    func stageUnreadable(_ breakage: Breakage, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch breakage {
        case .notAPropertyList:
            try Data("<plist><dict><key>broken".utf8).write(to: url)
        case .folder:
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        case .noPermission:
            try DisplayOverride(key: OverrideKey(display: first), resolutions: [hd]).propertyListData().write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path(percentEncoded: false))
        }
    }

    @Test(arguments: Breakage.stageable)
    func showsAnUnreadableOverrideInPlace(_ breakage: Breakage) throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = OverrideKey(display: first)
        let file = OverrideLocations.staged(at: root).userFile(for: key)
        try stageUnreadable(breakage, at: file)
        let model = makeModel(root: root, displays: StubDisplays([first, second]))

        #expect(model.selection == key)
        #expect(model.draft == nil)
        #expect(model.readFailure?.contains(file.path(percentEncoded: false)) == true)
        // What Remove Override… and Show in Finder act on.
        #expect(model.source == .installed)
        #expect(model.notice == nil)
    }

    @Test func removingAnUnreadableOverrideLoadsTheDisplay() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = OverrideKey(display: first)
        let locations = OverrideLocations.staged(at: root)
        try stageUnreadable(.notAPropertyList, at: locations.userFile(for: key))
        let model = makeModel(root: root, displays: StubDisplays([first, second]))

        await model.removeOverride()
        #expect(!FileManager.default.fileExists(atPath: locations.userFile(for: key).path(percentEncoded: false)))
        let backups = locations.backupRoot.appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).count == 1)
        #expect(model.readFailure == nil)
        #expect(model.draft != nil)
        #expect(model.source == .missing)
        #expect(model.targets.first { $0.key == key }?.hasOverride == false)
    }

    /// Apple's file is not Resolute's to remove, even after showing a display whose
    /// installed override could be removed.
    @Test func offersNoRemovalForAnUnreadableSystemOverride() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = OverrideLocations.staged(at: root)
        let secondKey = OverrideKey(display: second)
        try install(DisplayOverride(key: OverrideKey(display: first), resolutions: [hd]), under: root)
        try stageUnreadable(.folder, at: locations.systemFile(for: secondKey))
        let model = makeModel(root: root, displays: StubDisplays([first, second]))
        #expect(model.source == .installed)

        model.requestSelection(secondKey)
        #expect(model.readFailure?.contains(locations.systemFile(for: secondKey).path(percentEncoded: false)) == true)
        #expect(model.source == .system)
        await model.removeOverride()
        #expect(model.notice == nil)
        #expect(FileManager.default.fileExists(atPath: locations.systemFile(for: secondKey).path(percentEncoded: false)))
    }
}

@MainActor
@Suite struct MainMenuTests {
    @Test func givesTextFieldsAndWindowsTheirShortcuts() {
        let menu = MainMenu.make()
        let items = menu.items.compactMap(\.submenu).flatMap(\.items)
        func shortcut(_ action: String) -> String? {
            items.first { $0.action.map(NSStringFromSelector) == action }?.keyEquivalent
        }
        #expect(shortcut("cut:") == "x")
        #expect(shortcut("copy:") == "c")
        #expect(shortcut("paste:") == "v")
        #expect(shortcut("selectAll:") == "a")
        #expect(shortcut("undo:") == "z")
        #expect(shortcut("performClose:") == "w")
        #expect(shortcut("terminate:") == "q")
    }
}

@Suite struct ResolutionInputTests {
    @Test func readsWhatWasTyped() throws {
        let size = try #require(ResolutionInput.size(width: " 2560", height: "1440 "))
        #expect(size.width == 2560)
        #expect(size.height == 1440)
    }

    @Test(arguments: [
        ("", "1080"), ("1920", ""), ("19x0", "1080"), ("-1920", "1080"), ("0", "1080"),
        ("4611686018427387904", "1080"), ("1920", "70000"),
    ])
    func rejectsWhatIsNotASize(width: String, height: String) {
        #expect(ResolutionInput.size(width: width, height: height) == nil)
    }

    /// The flags field is hidden for 1× entries, so whatever was left in it must not
    /// stop one being added.
    @Test func ignoresTheFlagsOfA1xEntry() throws {
        let entry = try ResolutionInput.entry(width: "2560", height: "1440", hiDPI: false, flags: "left over")
        #expect(entry == .standard(width: 2560, height: 1440))
    }

    @Test func readsTheFlagsOfAHiDPIEntry() throws {
        let entry = try ResolutionInput.entry(width: "1920", height: "1080", hiDPI: true, flags: "0000000b 00a00000")
        #expect(entry == .hiDPI(width: 1920, height: 1080, flags: HiDPIFlags(primary: 0xB, secondary: 0xA0_0000)))
    }

    @Test func rejectsBadFlagsForAHiDPIEntry() {
        #expect(throws: ResoluteError.invalidFlags("left over")) {
            try ResolutionInput.entry(width: "1920", height: "1080", hiDPI: true, flags: "left over")
        }
    }

    @Test func rejectsAnEntryWithoutASize() {
        #expect(throws: ResoluteError.self) {
            try ResolutionInput.entry(width: "19x0", height: "1080", hiDPI: false, flags: "")
        }
    }
}
