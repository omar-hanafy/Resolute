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
        #expect(model.add(width: 1920, height: 1080, hiDPI: true, flags: .standard) == nil)
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
        _ = model.add(width: 1920, height: 1080, hiDPI: true, flags: .standard)
        model.select(displayID: second.id)
        #expect(model.selection == OverrideKey(display: first))
        #expect(model.pendingSelection == OverrideKey(display: second))
    }

    @Test func keepsAnEditedDisplayThatIsUnplugged() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let displays = StubDisplays([first, second])
        let model = makeModel(root: root, displays: displays)
        _ = model.add(width: 1920, height: 1080, hiDPI: true, flags: .standard)
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
        _ = model.add(width: 1920, height: 1080, hiDPI: true, flags: .standard)
        let written = try #require(model.draft?.working)

        let save = Task { await model.save() }
        while !model.isWorking { await Task.yield() }
        #expect(model.add(width: 2560, height: 1440, hiDPI: true, flags: .standard) != nil)
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

    @Test(arguments: [("", "1080"), ("1920", ""), ("19x0", "1080"), ("-1920", "1080"), ("0", "1080")])
    func rejectsWhatIsNotASize(width: String, height: String) {
        #expect(ResolutionInput.size(width: width, height: height) == nil)
    }
}
