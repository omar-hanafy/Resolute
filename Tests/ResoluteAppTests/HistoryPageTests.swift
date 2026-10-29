import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit
import ResoluteDesign

/// The History page's logic: its rows per filter, their badges and Undo, and following the
/// file while `resolute` adds to it.
@MainActor
@Suite struct HistoryPageTests {
    let scratch = ScratchDefaults()
    let errors = ShownErrors()
    let service = FakeDisplayService()
    let root = FileManager.default.temporaryDirectory.appending(
        path: "ResoluteHistoryPageTests-\(UUID().uuidString)", directoryHint: .isDirectory
    )
    let model: AppModel

    init() throws {
        model = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults), errors: errors, overridesRoot: root
        )
        let store = HistoryStore(locations: model.support)
        for entry in HistorySamples.entries { try store.append(entry) }
        model.refresh()
    }

    func items(_ filter: HistoryFilter) -> [HistoryItem] {
        HistoryList.items(in: model.historyTimeline, filter: filter, now: HistorySamples.now, locale: HistorySamples.locale)
    }

    @Test func showsFigmasRowsNewestFirst() {
        let rows = items(.all)
        #expect(rows.map(\.time) == ["9:41", "9:38", "9:20", "Yesterday", "Yesterday"])
        #expect(rows.map(\.title) == [
            "DELL U2723QE  2560 × 1440 → 2880 × 1620",
            "DELL U2723QE  1920 × 1080 → 2560 × 1440",
            "Built-in Retina Display  120 Hz → 60 Hz",
            "Mirroring on: Built-in + DELL U2723QE",
            "Built-in Retina Display  1728 × 1117 → 1496 × 967",
        ])
        #expect(rows.map(\.detail) == [
            "From Claude Code (Terminal) · hidden mode · nobody answered",
            "From Terminal",
            "From the panel",
            "From Shortcuts · “Presenting” preset",
            "From the panel",
        ])
        #expect(rows.map { HistoryList.rowStatus($0.status) } == [.reverted, .kept, .kept, .kept, .undone])
        // Undo only where the change is in place.
        #expect(rows.map(\.canUndo) == [false, true, true, true, false])
        #expect(rows.compactMap { Symbol(rawValue: $0.symbolName) } == [.terminal, .terminal, .menubarRectangle, .switch2, .menubarRectangle])
    }

    @Test func filtersBySource() {
        #expect(items(.panel).map(\.time) == ["9:20", "Yesterday"])
        #expect(items(.terminalAndAgents).map(\.time) == ["9:41", "9:38"])
        #expect(items(.shortcuts).map(\.title) == ["Mirroring on: Built-in + DELL U2723QE"])
    }

    @Test func saysWhenAFilterHasNothing() {
        let empty = AppModelTests.makeModel(
            service: service, preferences: Preferences(defaults: scratch.defaults),
            overridesRoot: root.appending(path: "Empty", directoryHint: .isDirectory)
        )
        for filter in HistoryFilter.allCases {
            #expect(HistoryList.items(in: empty.historyTimeline, filter: filter, now: HistorySamples.now, locale: HistorySamples.locale).isEmpty)
        }
        #expect(HistoryFilter.shortcuts.emptyText == "No display changes from Shortcuts in the last 7 days.")
    }

    @Test func showsAFailedChangeAsOverWithoutUndo() {
        #expect(HistoryList.rowStatus(.failed) == .failed)
        let failed = HistoryEntry(
            date: HistorySamples.now, source: .window,
            change: .mirroring(.init(isOn: true, displays: [])), outcome: .failed(message: "The display did not answer")
        )
        let item = HistoryItem(entry: failed, in: HistoryTimeline(entries: [failed]), now: HistorySamples.now, locale: HistorySamples.locale)
        #expect(!item.canUndo)
        #expect(item.accessibilityLabel.hasSuffix("Failed"))
    }

    @Test func undoesFromTheWindow() throws {
        let mode = try #require(FakeDisplayService.dell.modes.first { $0.width == 1920 && $0.refreshRate == 60 && $0.isHiDPI })
        model.apply(mode, to: FakeDisplayService.dell)
        let change = try #require(items(.all).first { $0.entry.source == .panel && $0.canUndo && $0.title.hasPrefix("DELL") })
        model.undo(change.entry, from: .window)
        #expect(errors.titles.isEmpty)
        let undone = try #require(items(.all).first { $0.id == change.id })
        #expect(undone.status == .undone && !undone.canUndo)
        // The Undo is recorded as the window's, and shows as the change's status.
        let undo = try #require(model.historyEntries.first { $0.outcome == .undone(of: change.entry.id) })
        #expect(undo.source == .window)
    }

    @Test func followsTheFileWhileResoluteAddsToIt() async throws {
        let changes = ChangeCount()
        let watcher = HistoryFileWatcher(file: model.support.historyFile) { changes.count += 1 }
        watcher.start()
        defer { watcher.stop() }
        #expect(watcher.isWatching)
        let before = model.historyEntries.count
        let terminal = HistoryRecorder(store: HistoryStore(locations: model.support), source: .terminal(app: "Ghostty"))
        terminal.record(.mirroring(.init(isOn: false, displays: [])), outcome: .applied)
        for _ in 0..<100 where changes.count == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(changes.count > 0)
        model.reloadHistory()
        #expect(model.historyEntries.count == before + 1)
    }

    @Test func waitsForTheSupportFolder() {
        let missing = root.appending(path: "Missing/history.jsonl")
        let watcher = HistoryFileWatcher(file: missing) {}
        watcher.start()
        #expect(!watcher.isWatching)
        watcher.stop()
    }
}

/// How many times something changed.
@MainActor
final class ChangeCount {
    var count = 0
}
