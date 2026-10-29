import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// A registrar that keeps its shortcuts to itself, so tests never take a key on the Mac
/// they run on. Shortcuts in `refuses` are refused, as macOS refuses another app's.
@MainActor
final class FakeHotKeyRegistrar: HotKeyRegistering {
    var onPress: (@MainActor (UInt32) -> Void)?
    private(set) var registered: [UInt32: KeyShortcut] = [:]
    private(set) var registrations = 0
    var refuses: Set<KeyShortcut> = []

    func register(_ shortcut: KeyShortcut, id: UInt32) throws {
        if refuses.contains(shortcut) { throw HotKeyRefused(shortcut: shortcut, status: OSStatus(eventHotKeyExistsErr)) }
        registered[id] = shortcut
        registrations += 1
    }

    func unregister(id: UInt32) {
        registered[id] = nil
    }

    /// Presses `shortcut`, as macOS reports a registered one.
    func press(_ shortcut: KeyShortcut) {
        guard let id = registered.first(where: { $0.value == shortcut })?.key else { return }
        onPress?(id)
    }
}

/// The shortcuts that work from anywhere: what is registered, when, and what pressing one does.
@MainActor
@Suite struct ShortcutHotKeyTests {
    let registrar = FakeHotKeyRegistrar()
    let center = NotificationCenter()
    let hotKeys: HotKeyCenter
    let one = KeyShortcut(key: "1", modifiers: [.control, .option])!
    let two = KeyShortcut(key: "2", modifiers: [.control, .option])!
    let coding = UUID()
    let gaming = UUID()

    init() {
        hotKeys = HotKeyCenter(registrar: registrar, notificationCenter: center)
    }

    typealias Assignment = HotKeyCenter.Assignment

    @Test func registersEachShortcutOnceAndKeepsTheOnesThatStay() {
        hotKeys.update([Assignment(shortcut: .openPanel, owner: .panel), Assignment(shortcut: one, owner: .preset(coding))])
        #expect(Set(registrar.registered.values) == [.openPanel, one])
        #expect(registrar.registrations == 2)
        // Coding's shortcut changes; the panel's stays registered as it was.
        hotKeys.update([Assignment(shortcut: .openPanel, owner: .panel), Assignment(shortcut: two, owner: .preset(coding))])
        #expect(Set(registrar.registered.values) == [.openPanel, two])
        #expect(registrar.registrations == 3)
        hotKeys.update([])
        #expect(registrar.registered.isEmpty)
        #expect(hotKeys.registered.isEmpty)
    }

    @Test func givesAShortcutTwoHaveToTheFirst() {
        hotKeys.update([Assignment(shortcut: .openPanel, owner: .panel), Assignment(shortcut: .openPanel, owner: .preset(coding))])
        #expect(Array(hotKeys.registered.values) == [Assignment(shortcut: .openPanel, owner: .panel)])
    }

    @Test func pressingAShortcutDoesWhatItsFor() {
        var performed: [ShortcutOwner] = []
        hotKeys.perform = { performed.append($0) }
        hotKeys.update([Assignment(shortcut: .openPanel, owner: .panel), Assignment(shortcut: one, owner: .preset(coding))])
        registrar.press(one)
        registrar.press(.openPanel)
        registrar.press(two)
        #expect(performed == [.preset(coding), .panel])
    }

    @Test func pausesWhileARecorderRecords() {
        var performed: [ShortcutOwner] = []
        hotKeys.perform = { performed.append($0) }
        hotKeys.update([Assignment(shortcut: .openPanel, owner: .panel)])
        ShortcutRecording.post(ShortcutRecording.didBegin, center: center)
        #expect(hotKeys.isPaused)
        #expect(registrar.registered.isEmpty)
        // A change while recording waits until the recording ends.
        hotKeys.update([Assignment(shortcut: .openPanel, owner: .panel), Assignment(shortcut: one, owner: .preset(gaming))])
        #expect(registrar.registered.isEmpty)
        registrar.press(.openPanel)
        #expect(performed.isEmpty)
        ShortcutRecording.post(ShortcutRecording.didEnd, center: center)
        #expect(!hotKeys.isPaused)
        #expect(Set(registrar.registered.values) == [.openPanel, one])
        // An extra end changes nothing.
        ShortcutRecording.post(ShortcutRecording.didEnd, center: center)
        #expect(Set(registrar.registered.values) == [.openPanel, one])
    }

    @Test func saysWhenMacOSRefusesAShortcutSomeoneJustChose() {
        var told: [[Assignment]] = []
        hotKeys.onRefused = { told.append($0) }
        registrar.refuses = [one]
        // At launch nobody has just chosen it: only logged.
        hotKeys.update([Assignment(shortcut: one, owner: .preset(coding))])
        #expect(hotKeys.refused == [Assignment(shortcut: one, owner: .preset(coding))])
        #expect(told.isEmpty)
        hotKeys.update([Assignment(shortcut: one, owner: .preset(coding)), Assignment(shortcut: two, owner: .preset(gaming))])
        #expect(told.isEmpty)
        registrar.refuses = [one, two]
        hotKeys.update([Assignment(shortcut: one, owner: .preset(coding)), Assignment(shortcut: .openPanel, owner: .panel),
                        Assignment(shortcut: two, owner: .preset(gaming))])
        // Two was registered before, so it stays; nothing new was refused.
        #expect(told.isEmpty)
        hotKeys.update([Assignment(shortcut: one, owner: .preset(coding))])
        hotKeys.update([Assignment(shortcut: one, owner: .preset(coding)), Assignment(shortcut: two, owner: .preset(gaming))])
        #expect(told == [[Assignment(shortcut: two, owner: .preset(gaming))]])
        // Freed, it is registered on the next pass.
        registrar.refuses = []
        hotKeys.update([Assignment(shortcut: one, owner: .preset(coding))])
        #expect(hotKeys.refused.isEmpty)
        #expect(Set(registrar.registered.values) == [one])
    }

    @Test func followsThePanelShortcutAndThePresets() async throws {
        let scratch = ScratchDefaults()
        let preferences = Preferences(defaults: scratch.defaults)
        let shell = RecordingShell()
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ResoluteShortcutHotKeyTests-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        let model = AppModelTests.makeModel(service: FakeDisplayService(), preferences: preferences, overridesRoot: root)
        model.shell = shell
        let desk = try model.saveCurrentSetupAsPreset(named: "Desk")
        try model.updatePresets { library in try library.setShortcut(one, forPresetWithID: desk.id) }
        hotKeys.start(model: model)
        try await waitUntil { Set(registrar.registered.values) == [.openPanel, one] }
        registrar.press(.openPanel)
        #expect(shell.panelOpens == 1)
        // Away from Desk, its shortcut switches back, recorded as the menu bar app's.
        let dell = FakeDisplayService.dell
        let other = try #require(dell.modes.first { $0.origin != .hidden && $0.isHiDPI && $0.modeID != dell.currentModeID })
        model.apply(other, to: dell)
        #expect(!model.isActive(desk))
        registrar.press(one)
        #expect(model.isActive(desk))
        #expect(model.historyEntries.first?.source == .preset(name: "Desk", via: .keyboard))

        preferences.panelShortcut = two
        try await waitUntil { Set(registrar.registered.values) == [two, one] }
        try model.updatePresets { library in try library.setShortcut(nil, forPresetWithID: desk.id) }
        try await waitUntil { Set(registrar.registered.values) == [two] }
        hotKeys.stop()
        #expect(registrar.registered.isEmpty)
    }

    @Test func turnsModifiersIntoCarbonsMask() {
        #expect(CarbonHotKeyRegistrar.carbonModifiers([.control, .option]) == UInt32(controlKey | optionKey))
        #expect(CarbonHotKeyRegistrar.carbonModifiers([.shift, .command]) == UInt32(shiftKey | cmdKey))
    }

    /// Lets the main run loop take up observed changes until `condition` holds, for up to
    /// two seconds.
    func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }
}
