import Foundation
import os
import Testing
@testable import ResoluteKit

/// Displays, modes and the History page from Figma (History 37:1957), on Tuesday 27 October
/// 2026 at 9:41 in London.
enum HistorySample {
    static let timeZone = TimeZone(identifier: "Europe/London")!
    static let britain = Locale(identifier: "en_GB")
    static let now = date(day: 27, hour: 9, minute: 41)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func date(day: Int, hour: Int, minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    /// A time of day as `locale` writes it: "9:41" on a British clock in macOS 27 (Figma's),
    /// "9:41 AM" in the United States. Expectations use it, since the patterns come with the
    /// system's locale data.
    static func clock(_ date: Date, _ locale: Locale = britain) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
    }

    static func mode(
        _ id: Int32, _ width: Int, _ height: Int, scale: Int = 1, hz: Double = 60, bits: Int? = nil,
        flags: UInt32 = 0x3, origin: DisplayMode.Origin = .system
    ) -> DisplayMode {
        DisplayMode(
            modeID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale,
            refreshRate: hz, bitsPerSample: bits, ioFlags: flags, origin: origin
        )
    }

    static let dell = Display(
        id: 2, name: "DELL U2723QE", vendorID: 0x10AC, productID: 0x4142, serialNumber: 808_464_432, currentModeID: 2,
        modes: [
            mode(1, 1920, 1080), mode(2, 2560, 1440, flags: 0x0200_0007), mode(3, 2560, 1440, hz: 50),
            mode(90, 2880, 1620, flags: 0x1, origin: .hidden),
        ],
        privateModes: .trusted
    )

    static let builtIn = Display(
        id: 1, name: "Built-in Retina Display", vendorID: 0x610, productID: 0xA050, isBuiltin: true, isMain: true,
        currentModeID: 54,
        modes: [mode(54, 1728, 1117, scale: 2, hz: 120, flags: 0x0200_0007), mode(55, 1728, 1117, scale: 2), mode(42, 1496, 967, scale: 2, hz: 120)]
    )

    /// `display` showing the mode `modeID`.
    static func on(_ display: Display, at modeID: Int32) -> Display {
        var display = display
        display.currentModeID = modeID
        return display
    }

    static func modeChange(_ display: Display, from: Int32, to: Int32) -> HistoryEntry.Change {
        let before = on(display, at: from)
        return .mode(HistoryEntry.ModeChange(display: before, to: before.modes.first { $0.modeID == to }!))
    }

    static let session = "AE062952-A3E9-47CA-80BB-A00418E712FE/100027"

    /// The five rows on the History page, and the Undo of the last one.
    static func figmaPage() -> (entries: [HistoryEntry], undo: HistoryEntry) {
        let resized = HistoryEntry(
            date: date(day: 26, hour: 18, minute: 5), source: .panel, change: modeChange(builtIn, from: 54, to: 42), outcome: .applied
        )
        let undo = HistoryEntry(
            date: date(day: 26, hour: 18, minute: 6), source: .panel, change: modeChange(builtIn, from: 42, to: 54),
            outcome: .undone(of: resized.id)
        )
        let mirrored = HistoryEntry(
            date: date(day: 26, hour: 20, minute: 15), source: .preset(name: "Presenting", via: .shortcuts),
            change: .mirroring(HistoryEntry.MirroringChange(isOn: true, displays: [.init(builtIn), .init(dell)])), outcome: .applied
        )
        let refresh = HistoryEntry(
            date: date(day: 27, hour: 9, minute: 20), source: .panel, change: modeChange(builtIn, from: 54, to: 55), outcome: .applied
        )
        let typed = HistoryEntry(
            date: date(day: 27, hour: 9, minute: 38), source: .terminal(app: "Terminal"), change: modeChange(dell, from: 1, to: 2),
            outcome: .applied
        )
        let tried = HistoryEntry(
            date: date(day: 27, hour: 9, minute: 41), source: .agent(name: "Claude Code", app: "Terminal"),
            change: modeChange(dell, from: 2, to: 90), outcome: .reverted(.noAnswer), loginSession: session
        )
        return ([tried, typed, refresh, mirrored, undo, resized], undo)
    }

    /// A store in a fresh folder whose clock reads `now`.
    static func store(now: Date = HistorySample.now, maximumFileSize: Int = 1 << 20, lockTimeout: Duration = .seconds(2)) throws -> HistoryStore {
        let root = try makeTemporaryDirectory().appending(path: "Support/Resolute", directoryHint: .isDirectory)
        return HistoryStore(
            locations: SupportLocations(root: root), lockTimeout: lockTimeout, maximumFileSize: maximumFileSize, owner: nil,
            now: { now }
        )
    }

    /// Removes the folder `store(…)` made.
    static func remove(_ store: HistoryStore) {
        try? FileManager.default.removeItem(at: store.locations.root.deletingLastPathComponent().deletingLastPathComponent())
    }

    static func entry(_ minutesAgo: Double, from now: Date = HistorySample.now, source: HistoryEntry.Source = .panel) -> HistoryEntry {
        HistoryEntry(
            date: now.addingTimeInterval(-minutesAgo * 60), source: source, change: modeChange(dell, from: 1, to: 2), outcome: .applied
        )
    }

    static func lines(of store: HistoryStore) throws -> [String] {
        try String(contentsOf: store.locations.historyFile, encoding: .utf8).split(separator: "\n").map(String.init)
    }
}

// MARK: - The model

@Suite struct HistoryEntryTests {
    @Test func storesEveryKindOfChangeAndOutcome() throws {
        let id = UUID()
        let sources: [HistoryEntry.Source] = [
            .panel, .menu, .window, .dock, .shortcuts, .terminal(app: nil), .terminal(app: "iTerm"),
            .agent(name: "Claude Code", app: "Terminal"), .agent(name: "Codex", app: nil),
            .preset(name: "Coding", via: .agent(name: "Claude Code", app: "Ghostty")),
        ]
        let changes: [HistoryEntry.Change] = [
            HistorySample.modeChange(HistorySample.dell, from: 2, to: 90),
            .mode(HistoryEntry.ModeChange(display: .init(HistorySample.dell), from: nil, to: .init(HistorySample.dell.modes[0]))),
            .mirroring(HistoryEntry.MirroringChange(isOn: false, displays: [.init(HistorySample.builtIn)])),
        ]
        let outcomes: [HistoryEntry.Outcome] = [
            .applied, .kept, .keptForSession, .undone(of: id), .failed(message: "It did not switch."),
        ] + HistoryEntry.RevertReason.allCases.map { .reverted($0) }
        let encoder = JSONEncoder()
        for source in sources {
            for change in changes {
                for outcome in outcomes {
                    let entry = HistoryEntry(
                        date: HistorySample.now, source: source, change: change, outcome: outcome, loginSession: HistorySample.session
                    )
                    let decoded = try JSONDecoder().decode(HistoryEntry.self, from: try encoder.encode(entry))
                    #expect(decoded == entry)
                }
            }
        }
    }

    @Test func writesOneVersionedLinePerEntry() throws {
        let entry = HistorySample.figmaPage().entries[0]
        let line = try #require(String(data: try HistoryStore.encode(entry), encoding: .utf8))
        #expect(!line.contains("\n"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        #expect(object["v"] as? Int == 1)
        #expect(object["date"] as? String == "2026-10-27T09:41:00.000Z")
        #expect(object["session"] as? String == HistorySample.session)
        #expect((object["source"] as? [String: Any])?["kind"] as? String == "agent")
        #expect((object["outcome"] as? [String: Any])?["reason"] as? String == "noAnswer")
    }

    @Test func keepsMillisecondsSoChangesInOneSecondStayInOrder() throws {
        let date = Date(timeIntervalSince1970: 1_793_094_060.25)
        let entry = HistoryEntry(date: date, source: .panel, change: HistorySample.modeChange(HistorySample.dell, from: 1, to: 2), outcome: .applied)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: try HistoryStore.encode(entry))
        #expect(abs(decoded.date.timeIntervalSince(date)) < 0.001)
    }

    @Test func readsAReasonANewerResoluteAddedAsAnUnknownOne() throws {
        let entry = HistorySample.figmaPage().entries[0]
        let line = String(decoding: try HistoryStore.encode(entry), as: UTF8.self).replacingOccurrences(of: "noAnswer", with: "somethingNew")
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: Data(line.utf8))
        #expect(decoded.outcome == .reverted(.unspecified))
    }

    @Test func refusesAnEntryOfANewerFormat() throws {
        let line = String(decoding: try HistoryStore.encode(HistorySample.entry(1)), as: UTF8.self).replacingOccurrences(of: "\"v\":1", with: "\"v\":2")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(HistoryEntry.self, from: Data(line.utf8)) }
        // Its date can still be read, so pruning keeps it until it is old.
        #expect(HistoryStore.envelopeDate(Data(line.utf8)) != nil)
    }

    @Test func knowsAHiddenModeAndWhereAPresetWasApplied() {
        #expect(HistorySample.figmaPage().entries[0].isHiddenMode)
        #expect(!HistorySample.figmaPage().entries[1].isHiddenMode)
        let source = HistoryEntry.Source.preset(name: "Presenting", via: .shortcuts)
        #expect(source.origin == .shortcuts)
        #expect(source.presetName == "Presenting")
        #expect(source.category == .shortcuts)
        #expect(HistoryEntry.Source.agent(name: "Codex", app: nil).category == .terminalAndAgents)
        #expect([HistoryEntry.Source.panel, .menu, .window, .dock].allSatisfy { $0.category == .panel })
    }
}

// MARK: - The file

@Suite struct HistoryStoreTests {
    @Test func readsNewestFirstAndKeepsTheOrderOfOneMoment() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let older = HistorySample.entry(30)
        let first = HistorySample.entry(5)
        var second = HistorySample.entry(5)
        second.source = .menu
        let newest = HistorySample.entry(1)
        for entry in [older, first, newest, second] { try store.append(entry) }
        #expect(try store.entries().map(\.id) == [newest.id, second.id, first.id, older.id])
        #expect(try store.entries(matching: .all, limit: 2).map(\.id) == [newest.id, second.id])
    }

    @Test func filtersByWhereChangesCameFrom() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let page = HistorySample.figmaPage().entries
        for entry in page.reversed() { try store.append(entry) }
        #expect(try store.entries(matching: .terminalAndAgents).map(\.id) == [page[0].id, page[1].id])
        #expect(try store.entries(matching: .shortcuts).map(\.id) == [page[3].id])
        #expect(try store.entries(matching: .panel).map(\.id) == [page[2].id, page[4].id, page[5].id])
    }

    @Test func readsNothingWithoutCreatingTheFolder() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        #expect(try store.entries().isEmpty)
        try store.prune()
        #expect(!FileManager.default.fileExists(atPath: store.locations.root.path(percentEncoded: false)))
    }

    @Test func createsTheFolderAndTheFileOnTheFirstChange() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        try store.append(HistorySample.entry(1))
        #expect(try HistorySample.lines(of: store).count == 1)
        #expect(FileManager.default.fileExists(atPath: store.locations.root.appending(path: "history.lock").path(percentEncoded: false)))
    }

    @Test func keepsSevenDays() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let old = HistorySample.entry(7 * 24 * 60 + 1)
        let recent = HistorySample.entry(7 * 24 * 60 - 1)
        try store.append(old)
        try store.append(recent)
        #expect(try store.entries().map(\.id) == [recent.id])
        // A change just past 7 days stays in the file until a prune, which is not needed yet.
        #expect(try HistorySample.lines(of: store).count == 2)
        try store.prune()
        #expect(try HistorySample.lines(of: store).count == 1)
        #expect(try store.entries().map(\.id) == [recent.id])
    }

    @Test func prunesOnAChangeOnceTheOldestIsADayPastSevenDays() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let veryOld = HistorySample.entry(8 * 24 * 60 + 1)
        try store.append(veryOld)
        try store.append(HistorySample.entry(1))
        let lines = try HistorySample.lines(of: store)
        #expect(lines.count == 1)
        #expect(!lines[0].contains(veryOld.id.uuidString))
    }

    @Test func skipsLinesItCannotRead() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let valid = HistorySample.entry(10)
        let newer = String(decoding: try HistoryStore.encode(HistorySample.entry(5)), as: UTF8.self)
            .replacingOccurrences(of: "\"v\":1", with: "\"v\":2")
        let text = [
            "not json at all", String(decoding: try HistoryStore.encode(valid), as: UTF8.self), "{\"v\":1}", "", "   ", newer,
            "{\"v\":1,\"id\":",
        ].joined(separator: "\n")
        try FileManager.default.createDirectory(at: store.locations.root, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: store.locations.historyFile)
        #expect(try store.entries().map(\.id) == [valid.id])

        // Pruning drops what can't be read but keeps what a newer Resolute wrote.
        try store.prune()
        let lines = try HistorySample.lines(of: store)
        #expect(lines.count == 2)
        #expect(lines.contains { $0.contains("\"v\":2") })
    }

    @Test func startsANewLineAfterOneCutShort() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let before = HistorySample.entry(10)
        try store.append(before)
        let handle = try FileHandle(forWritingTo: store.locations.historyFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"v\":1,\"id\":\"cut".utf8))
        try handle.close()
        let after = HistorySample.entry(1)
        try store.append(after)
        #expect(try store.entries().map(\.id) == [after.id, before.id])
    }

    @Test func capsTheFileSize() throws {
        let store = try HistorySample.store(maximumFileSize: 8 * 1024)
        defer { HistorySample.remove(store) }
        var appended: [HistoryEntry] = []
        for minute in stride(from: 120.0, to: 0, by: -1) {
            let entry = HistorySample.entry(minute)
            appended.append(entry)
            try store.append(entry)
        }
        let size = try #require(try FileManager.default.attributesOfItem(atPath: store.locations.historyFile.path(percentEncoded: false))[.size] as? Int)
        #expect(size <= 8 * 1024)
        let kept = try store.entries()
        #expect(kept.count < appended.count)
        #expect(kept.first?.id == appended.last?.id)
        // What stays is the newest, in order.
        #expect(kept.map(\.id) == appended.suffix(kept.count).reversed().map(\.id))
    }

    @Test func keepsEveryChangeWhenProcessesWriteAtOnce() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let failures = OSAllocatedUnfairLock(initialState: [String]())
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            // Each writer opens the files itself, as separate processes do.
            let writer = store
            for index in 0..<25 {
                do {
                    try writer.append(HistorySample.entry(Double(worker * 25 + index) / 10))
                } catch {
                    failures.withLock { $0.append("\(error)") }
                }
            }
        }
        #expect(failures.withLock { $0 }.isEmpty)
        let entries = try store.entries()
        #expect(entries.count == 200)
        #expect(Set(entries.map(\.id)).count == 200)
        let decoder = JSONDecoder()
        for line in try HistorySample.lines(of: store) {
            #expect((try? decoder.decode(HistoryEntry.self, from: Data(line.utf8))) != nil, "\(line)")
        }
    }

    @Test func staysWholeWhenWritersPruneAtOnce() throws {
        let store = try HistorySample.store(maximumFileSize: 6 * 1024)
        defer { HistorySample.remove(store) }
        let failures = OSAllocatedUnfairLock(initialState: [String]())
        DispatchQueue.concurrentPerform(iterations: 6) { worker in
            for index in 0..<30 {
                do {
                    try store.append(HistorySample.entry(Double(200 - worker * 30 - index)))
                } catch {
                    failures.withLock { $0.append("\(error)") }
                }
            }
        }
        #expect(failures.withLock { $0 }.isEmpty)
        let lines = try HistorySample.lines(of: store)
        #expect(!lines.isEmpty)
        let decoder = JSONDecoder()
        #expect(lines.allSatisfy { (try? decoder.decode(HistoryEntry.self, from: Data($0.utf8))) != nil })
        let size = try #require(try FileManager.default.attributesOfItem(atPath: store.locations.historyFile.path(percentEncoded: false))[.size] as? Int)
        #expect(size <= 6 * 1024)
    }

    @Test func givesUpWhenAnotherProcessHoldsTheFile() throws {
        let store = try HistorySample.store(lockTimeout: .milliseconds(100))
        defer { HistorySample.remove(store) }
        try store.append(HistorySample.entry(5))
        let lock = open(store.locations.root.appending(path: "history.lock").path(percentEncoded: false), O_RDWR)
        #expect(lock >= 0)
        defer { close(lock) }
        #expect(flock(lock, LOCK_EX) == 0)
        #expect(throws: HistoryError.busy(path: store.locations.historyFile.path(percentEncoded: false))) {
            try store.append(HistorySample.entry(1))
        }
        // Reading needs no lock.
        #expect(try store.entries().count == 1)
    }

    @Test func refusesAHistoryFileThatIsALink() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let elsewhere = try makeTemporaryDirectory().appending(path: "elsewhere.jsonl")
        defer { try? FileManager.default.removeItem(at: elsewhere.deletingLastPathComponent()) }
        try Data().write(to: elsewhere)
        try FileManager.default.createDirectory(at: store.locations.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: store.locations.historyFile, withDestinationURL: elsewhere)
        #expect(throws: HistoryError.self) { try store.append(HistorySample.entry(1)) }
        #expect(throws: HistoryError.self) { try store.entries() }
        #expect(try Data(contentsOf: elsewhere).isEmpty)
    }

    @Test func refusesAHistoryFileWithAnotherName() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        try store.append(HistorySample.entry(5))
        let other = store.locations.root.appending(path: "other.jsonl")
        try FileManager.default.linkItem(at: store.locations.historyFile, to: other)
        #expect(throws: HistoryError.self) { try store.append(HistorySample.entry(1)) }
    }
}

// MARK: - Running as root under sudo

@Suite struct HistoryOwnershipTests {
    @Test func namesThePersonWhoRanSudo() {
        let sudo = ["SUDO_UID": "501", "SUDO_GID": "20", "SUDO_USER": "omar"]
        #expect(FileOwner.sudoPerson(environment: sudo, isRoot: true) == FileOwner(uid: 501, gid: 20))
        #expect(FileOwner.sudoPerson(environment: sudo, isRoot: false) == nil)
        #expect(FileOwner.sudoPerson(environment: [:], isRoot: true) == nil)
        #expect(FileOwner.sudoPerson(environment: ["SUDO_UID": "0", "SUDO_GID": "0"], isRoot: true) == nil)
        #expect(FileOwner.sudoPerson(environment: ["SUDO_UID": "x", "SUDO_GID": "20"], isRoot: true) == nil)
    }

    @Test func followsNoLinkBelowTheHomeAsRoot() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let elsewhere = home.appending(path: "Elsewhere", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appending(path: "Library"), withDestinationURL: elsewhere)
        let support = home.appending(path: "Library/Application Support/Resolute", directoryHint: .isDirectory)
        #expect(throws: HistoryError.self) { try SupportFolder.open(support, creating: true, owner: nil, home: home, isRoot: true) }
        #expect(!FileManager.default.fileExists(atPath: elsewhere.appending(path: "Application Support").path(percentEncoded: false)))
        // The person's own links are theirs to make.
        #expect(try SupportFolder.open(support, creating: true, owner: nil, home: home, isRoot: false) != nil)
        #expect(FileManager.default.fileExists(atPath: elsewhere.appending(path: "Application Support/Resolute").path(percentEncoded: false)))
    }

    @Test func keepsRootsFilesInsideThePersonsHome() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let outside = try makeTemporaryDirectory().appending(path: "Resolute", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: outside.deletingLastPathComponent()) }
        #expect(throws: HistoryError.self) { try SupportFolder.open(outside, creating: true, owner: nil, home: home, isRoot: true) }
        let inside = home.appending(path: "Library/Application Support/Resolute", directoryHint: .isDirectory)
        #expect(try SupportFolder.open(inside, creating: true, owner: nil, home: home, isRoot: true) != nil)
    }

    @Test func givesWhatItCreatesToTheOwner() throws {
        let root = try makeTemporaryDirectory().appending(path: "New/Resolute", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent().deletingLastPathComponent()) }
        let me = FileOwner(uid: getuid(), gid: getgid())
        let store = HistoryStore(locations: SupportLocations(root: root), maximumFileSize: 1 << 20, owner: me, now: { HistorySample.now })
        try store.append(HistorySample.entry(1))
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path(percentEncoded: false))
        #expect((attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid())
        #expect(try store.entries().count == 1)
    }
}

// MARK: - Texts

@Suite struct HistoryTextTests {
    let dell = HistorySample.dell
    let builtIn = HistorySample.builtIn

    @Test func titlesSayWhatChanged() {
        #expect(HistoryText.title(of: HistorySample.modeChange(dell, from: 2, to: 90)) == "DELL U2723QE  2560 × 1440 → 2880 × 1620")
        #expect(HistoryText.title(of: HistorySample.modeChange(builtIn, from: 54, to: 55)) == "Built-in Retina Display  120 Hz → 60 Hz")
        #expect(HistoryText.title(of: HistorySample.modeChange(builtIn, from: 54, to: 42)) == "Built-in Retina Display  1728 × 1117 → 1496 × 967")
        let unknown = HistoryEntry.Change.mode(HistoryEntry.ModeChange(display: .init(dell), from: nil, to: .init(dell.modes[1])))
        #expect(HistoryText.title(of: unknown) == "DELL U2723QE → 2560 × 1440")
        let scaled = HistoryEntry.Change.mode(HistoryEntry.ModeChange(
            display: .init(dell), from: .init(HistorySample.mode(7, 1920, 1080)), to: .init(HistorySample.mode(8, 1920, 1080, scale: 2))
        ))
        #expect(HistoryText.title(of: scaled) == "DELL U2723QE  1920 × 1080 1× → 1920 × 1080 HiDPI")
        let on = HistoryEntry.Change.mirroring(.init(isOn: true, displays: [.init(builtIn), .init(dell)]))
        #expect(HistoryText.title(of: on) == "Mirroring on: Built-in + DELL U2723QE")
        #expect(HistoryText.title(of: .mirroring(.init(isOn: false, displays: [.init(dell)]))) == "Mirroring off: DELL U2723QE")
        #expect(HistoryText.title(of: .mirroring(.init(isOn: false, displays: []))) == "Mirroring off")
    }

    @Test func thePanelNamesOnlyTheNewMode() {
        #expect(HistoryText.activityTitle(of: HistorySample.modeChange(dell, from: 1, to: 2)) == "DELL U2723QE → 2560 × 1440")
        #expect(HistoryText.activityTitle(of: HistorySample.modeChange(builtIn, from: 54, to: 55)) == "Built-in Retina Display → 60 Hz")
    }

    @Test func detailsSayWhereAChangeCameFromAndHowItEnded() {
        func detail(_ source: HistoryEntry.Source, _ outcome: HistoryEntry.Outcome, hidden: Bool = false) -> String {
            HistoryText.detail(of: HistoryEntry(
                date: HistorySample.now, source: source, change: HistorySample.modeChange(dell, from: 2, to: hidden ? 90 : 1), outcome: outcome
            ))
        }
        #expect(detail(.agent(name: "Claude Code", app: "Terminal"), .reverted(.noAnswer), hidden: true)
            == "From Claude Code (Terminal) · hidden mode · nobody answered")
        #expect(detail(.terminal(app: "Terminal"), .applied) == "From Terminal")
        #expect(detail(.terminal(app: nil), .applied) == "From the resolute command")
        #expect(detail(.agent(name: "Codex", app: nil), .kept) == "From Codex")
        #expect(detail(.panel, .keptForSession, hidden: true) == "From the panel · hidden mode · until you log out")
        #expect(detail(.menu, .reverted(.declined), hidden: true) == "From the menu · hidden mode · you chose Revert")
        #expect(detail(.window, .reverted(.displayWentDark), hidden: true) == "From the window · hidden mode · the display went dark")
        #expect(detail(.dock, .reverted(.displayChanged)) == "From the Dock · the display changed during the trial")
        #expect(detail(.panel, .reverted(.unspecified)) == "From the panel")
        #expect(detail(.shortcuts, .failed(message: "DELL U2723QE did not switch.")) == "From Shortcuts · DELL U2723QE did not switch.")
        #expect(detail(.preset(name: "Presenting", via: .shortcuts), .applied) == "From Shortcuts · “Presenting” preset")
        #expect(detail(.panel, .undone(of: UUID())) == "From the panel · undo of an earlier change")
    }

    @Test func timesReadLikeTheHistoryPage() {
        let now = HistorySample.now
        func time(_ date: Date, _ locale: Locale = HistorySample.britain) -> String {
            HistoryText.time(of: date, now: now, timeZone: HistorySample.timeZone, locale: locale)
        }
        #expect(time(HistorySample.date(day: 27, hour: 9, minute: 41)) == HistorySample.clock(HistorySample.date(day: 27, hour: 9, minute: 41)))
        #expect(time(HistorySample.date(day: 27, hour: 0, minute: 5)) == HistorySample.clock(HistorySample.date(day: 27, hour: 0, minute: 5)))
        let american = time(HistorySample.date(day: 27, hour: 9, minute: 41), Locale(identifier: "en_US"))
        #expect(american.hasPrefix("9:41") && american.hasSuffix("AM"))
        #expect(time(HistorySample.date(day: 26, hour: 23, minute: 59)) == "Yesterday")
        #expect(time(HistorySample.date(day: 24, hour: 12, minute: 0)) == "Saturday")
        #expect(time(HistorySample.date(day: 21, hour: 12, minute: 0)) == "Wednesday")
        #expect(time(HistorySample.date(day: 20, hour: 12, minute: 0)) == "20 Oct")
        #expect(time(HistorySample.date(day: 20, hour: 12, minute: 0), Locale(identifier: "en_US")) == "Oct 20")
        // Resolute's words are English whatever the language; only the conventions follow it.
        #expect(time(HistorySample.date(day: 24, hour: 12, minute: 0), Locale(identifier: "fr_FR")) == "Saturday")
        #expect(time(HistorySample.date(day: 26, hour: 12, minute: 0), Locale(identifier: "fr_FR")) == "Yesterday")
        // A clock that moved back shows the time rather than a day in the future.
        #expect(time(HistorySample.date(day: 27, hour: 9, minute: 45)) == HistorySample.clock(HistorySample.date(day: 27, hour: 9, minute: 45)))
    }

    @Test func thePanelSaysHowLongAgo() {
        let now = HistorySample.now
        func ago(_ seconds: TimeInterval, from now: Date = HistorySample.now) -> String {
            HistoryText.relativeTime(of: now.addingTimeInterval(-seconds), now: now, timeZone: HistorySample.timeZone)
        }
        #expect(ago(20) == "just now")
        #expect(ago(-30) == "just now")
        #expect(ago(150) == "2 min ago")
        #expect(ago(59 * 60) == "59 min ago")
        #expect(ago(3 * 60 * 60 + 60) == "3 hr ago")
        #expect(ago(24 * 60 * 60) == "yesterday")
        #expect(ago(3 * 24 * 60 * 60) == "3 days ago")
        // Across midnight, minutes still count as minutes.
        #expect(ago(20 * 60, from: HistorySample.date(day: 27, hour: 0, minute: 10)) == "20 min ago")
        #expect(HistoryText.relativeTime(of: now, now: now, timeZone: HistorySample.timeZone) == "just now")
    }

    @Test func readsSizesWithByForVoiceOver() {
        #expect(HistoryText.spoken("DELL U2723QE  2560 × 1440 → 2880 × 1620") == "DELL U2723QE, 2560 by 1440 to 2880 by 1620")
        #expect(HistoryText.spoken("From Claude Code (Terminal) · hidden mode") == "From Claude Code (Terminal), hidden mode")
        #expect(HistoryText.spoken("1920 × 1080 1× → 1920 × 1080 HiDPI") == "1920 by 1080 1x to 1920 by 1080 HiDPI")
    }

    @Test func undoSaysWhatComesBack() {
        #expect(HistoryText.undoDescription(of: HistorySample.modeChange(dell, from: 1, to: 2)) == "Put DELL U2723QE back to 1920 × 1080")
        #expect(HistoryText.undoDescription(of: HistorySample.modeChange(builtIn, from: 54, to: 55)) == "Put Built-in Retina Display back to 120 Hz")
        #expect(HistoryText.undoDescription(of: .mirroring(.init(isOn: true, displays: []))) == "Turn mirroring off")
        #expect(HistoryText.undoDescription(of: .mirroring(.init(isOn: false, displays: []))) == "Turn mirroring back on")
    }

    @Test func usesFigmasWords() {
        #expect(HistoryFilter.allCases.map(\.title) == ["All", "Panel", "Terminal & Agents", "Shortcuts"])
        // Without Shortcuts, which isn't built yet.
        #expect(HistoryText.pageDescription
            == "Every switch from the panel, the menu, the resolute command and agents. Undo puts back what was there before; a hidden mode undone after logout cannot come back.")
        #expect(HistoryText.footnote
            == "History keeps 7 days. The resolute command writes here too, so agents’ changes are always visible.")
        #expect([HistoryStatus.kept, .reverted, .undone, .failed].map(\.title) == ["Kept", "Reverted", "Undone", "Failed"])
        #expect([HistoryStatus.kept, .reverted, .undone, .failed].map(\.tone) == [.accent, .neutral, .neutral, .warning])
    }

    @Test func picksASymbolForWhereAChangeCameFrom() {
        let symbols = [
            HistoryEntry.Source.panel, .menu, .window, .dock, .terminal(app: nil), .agent(name: "Codex", app: nil), .shortcuts,
            .preset(name: "Coding", via: .shortcuts),
        ].map(\.symbolName)
        #expect(symbols == ["menubar.rectangle", "menubar.rectangle", "macwindow", "dock.rectangle", "terminal", "terminal", "switch.2", "switch.2"])
    }
}

// MARK: - The list and the panel

@Suite struct HistoryTimelineTests {
    @Test func showsTheHistoryPageFromFigma() {
        let page = HistorySample.figmaPage()
        let items = HistoryTimeline(entries: page.entries).items(
            now: HistorySample.now, timeZone: HistorySample.timeZone, locale: HistorySample.britain
        )
        let clock = { (minute: Int) in HistorySample.clock(HistorySample.date(day: 27, hour: 9, minute: minute)) }
        #expect(items.map(\.time) == [clock(41), clock(38), clock(20), "Yesterday", "Yesterday"])
        #expect(items.map(\.symbolName) == ["terminal", "terminal", "menubar.rectangle", "switch.2", "menubar.rectangle"])
        #expect(items.map(\.title) == [
            "DELL U2723QE  2560 × 1440 → 2880 × 1620",
            "DELL U2723QE  1920 × 1080 → 2560 × 1440",
            "Built-in Retina Display  120 Hz → 60 Hz",
            "Mirroring on: Built-in + DELL U2723QE",
            "Built-in Retina Display  1728 × 1117 → 1496 × 967",
        ])
        #expect(items.map(\.detail) == [
            "From Claude Code (Terminal) · hidden mode · nobody answered",
            "From Terminal",
            "From the panel",
            "From Shortcuts · “Presenting” preset",
            "From the panel",
        ])
        #expect(items.map(\.status) == [.reverted, .kept, .kept, .kept, .undone])
        #expect(items.map(\.canUndo) == [false, true, true, true, false])
        #expect(items[1].accessibilityLabel == "\(clock(38)), DELL U2723QE, 1920 by 1080 to 2560 by 1440, From Terminal, Kept")
        #expect(items[1].undoAccessibilityLabel == "Undo, put DELL U2723QE back to 1920 by 1080")
        #expect(items[3].undoAccessibilityLabel == "Undo, turn mirroring off")
    }

    @Test func filtersLikeTheSegments() {
        let timeline = HistoryTimeline(entries: HistorySample.figmaPage().entries)
        #expect(timeline.changes(in: .terminalAndAgents).map(\.source.name) == ["Claude Code (Terminal)", "Terminal"])
        #expect(timeline.changes(in: .shortcuts).count == 1)
        #expect(timeline.changes(in: .panel).map { HistoryText.title(of: $0.change) } == [
            "Built-in Retina Display  120 Hz → 60 Hz", "Built-in Retina Display  1728 × 1117 → 1496 × 967",
        ])
    }

    /// Shortcuts actions aren't built yet, so its filter is offered only once History has
    /// a change from one.
    @Test func offersTheShortcutsFilterOnlyWithChangesFromShortcuts() {
        let page = HistorySample.figmaPage().entries
        #expect(HistoryFilter.offered(for: page) == HistoryFilter.allCases)
        let withoutShortcuts = page.filter { $0.source.category != .shortcuts }
        #expect(HistoryFilter.offered(for: withoutShortcuts) == [.all, .panel, .terminalAndAgents])
        #expect(HistoryFilter.offered(for: []) == [.all, .panel, .terminalAndAgents])
    }

    @Test func showsAnUndoAsTheStatusOfWhatItUndid() {
        let page = HistorySample.figmaPage()
        let timeline = HistoryTimeline(entries: page.entries)
        let resized = page.entries[5]
        #expect(timeline.undo(of: resized) == page.undo)
        #expect(timeline.status(of: resized) == .undone)
        #expect(!timeline.changes().contains(page.undo))
        // Without the change it undid, an Undo is a change of its own.
        let alone = HistoryTimeline(entries: [page.undo])
        #expect(alone.changes() == [page.undo])
        #expect(alone.status(of: page.undo) == .kept)
        #expect(HistoryText.detail(of: page.undo) == "From the panel · undo of an earlier change")
    }

    @Test func offersNoUndoWithoutTheModeBefore() {
        let unknown = HistoryEntry(
            date: HistorySample.now, source: .panel,
            change: .mode(.init(display: .init(HistorySample.dell), from: nil, to: .init(HistorySample.dell.modes[1]))), outcome: .applied
        )
        #expect(!HistoryTimeline(entries: [unknown]).canUndo(unknown))
        let failed = HistorySample.entry(1)
        var failing = failed
        failing.outcome = .failed(message: "No.")
        #expect(!HistoryTimeline(entries: [failing]).canUndo(failing))
    }

    @Test func thePanelShowsTheLastChangeFromOutside() throws {
        let page = HistorySample.figmaPage()
        let timeline = HistoryTimeline(entries: page.entries)
        // The agent's trial was reverted, so what Terminal did is the last change in place.
        #expect(timeline.lastOutsideChange == page.entries[1])
        let now = HistorySample.date(day: 27, hour: 9, minute: 40, second: 30)
        let activity = try #require(timeline.lastOutsideActivity(now: now, timeZone: HistorySample.timeZone))
        #expect(activity.title == "DELL U2723QE → 2560 × 1440")
        #expect(activity.detail == "From Terminal · 2 min ago")
        #expect(activity.symbolName == "terminal")
        #expect(activity.accessibilityLabel == "DELL U2723QE to 2560 by 1440, From Terminal, 2 min ago")
        #expect(activity.undoAccessibilityLabel == "Undo, put DELL U2723QE back to 1920 by 1080")
    }

    @Test func thePanelLeavesOutChangesNoLongerInPlace() {
        let typed = HistoryEntry(
            date: HistorySample.date(day: 27, hour: 9, minute: 0), source: .terminal(app: "Terminal"),
            change: HistorySample.modeChange(HistorySample.dell, from: 1, to: 2), outcome: .applied
        )
        // The person changed the same display in the panel afterwards.
        let replaced = HistoryEntry(
            date: HistorySample.date(day: 27, hour: 9, minute: 5), source: .panel,
            change: HistorySample.modeChange(HistorySample.dell, from: 2, to: 3), outcome: .applied
        )
        #expect(HistoryTimeline(entries: [typed, replaced]).lastOutsideChange == nil)
        // An undone change is no longer in place either.
        let undo = HistoryEntry(
            date: HistorySample.date(day: 27, hour: 9, minute: 5), source: .panel,
            change: HistorySample.modeChange(HistorySample.dell, from: 2, to: 1), outcome: .undone(of: typed.id)
        )
        #expect(HistoryTimeline(entries: [typed, undo]).lastOutsideChange == nil)
        // A change to another display does not replace it.
        let other = HistoryEntry(
            date: HistorySample.date(day: 27, hour: 9, minute: 5), source: .panel,
            change: HistorySample.modeChange(HistorySample.builtIn, from: 54, to: 55), outcome: .applied
        )
        #expect(HistoryTimeline(entries: [typed, other]).lastOutsideChange == typed)
        // Shortcuts are outside the panel too; the panel's own changes never are.
        let shortcut = HistoryEntry(
            date: HistorySample.date(day: 27, hour: 9, minute: 6), source: .preset(name: "Presenting", via: .shortcuts),
            change: .mirroring(.init(isOn: true, displays: [])), outcome: .applied
        )
        #expect(HistoryTimeline(entries: [typed, other, shortcut]).lastOutsideChange == shortcut)
        #expect(HistoryTimeline(entries: [replaced, other]).lastOutsideChange == nil)
        #expect(HistoryText.activityDetail(of: shortcut, now: HistorySample.date(day: 27, hour: 9, minute: 6), timeZone: HistorySample.timeZone)
            == "From Shortcuts · “Presenting” preset · just now")
    }
}

// MARK: - Undo

@Suite struct HistoryUndoTests {
    let dell = HistorySample.dell
    let session = HistorySample.session

    func plan(_ entry: HistoryEntry, displays: [Display], others: [HistoryEntry] = [], session: String? = HistorySample.session) -> HistoryUndo.Plan {
        HistoryUndo.plan(for: entry, in: HistoryTimeline(entries: [entry] + others), displays: displays, loginSession: session)
    }

    func change(_ from: Int32, _ to: Int32, outcome: HistoryEntry.Outcome = .applied, on display: Display = HistorySample.dell) -> HistoryEntry {
        HistoryEntry(date: HistorySample.now, source: .terminal(app: "Terminal"), change: HistorySample.modeChange(display, from: from, to: to),
                     outcome: outcome, loginSession: HistorySample.session)
    }

    @Test func putsBackTheListedModeBefore() {
        let entry = change(1, 2)
        let now = HistorySample.on(dell, at: 2)
        #expect(plan(entry, displays: [now]) == .switchMode(display: now, mode: dell.modes[0]))
        #expect(!plan(entry, displays: [now]).needsTrial)
    }

    @Test func findsTheModeUnderANewIDAfterAReconnect() {
        var reconnected = HistorySample.on(dell, at: 2)
        reconnected.id = 9
        reconnected.modes[0].modeID = 41
        guard case .switchMode(let display, let mode) = plan(change(1, 2), displays: [HistorySample.builtIn, reconnected]) else {
            Issue.record("Expected a switch")
            return
        }
        #expect(display.id == 9)
        #expect(mode.modeID == 41)
    }

    @Test func saysWhenTheDisplayIsGoneOrCannotBeToldApart() {
        #expect(plan(change(1, 2), displays: [HistorySample.builtIn]) == .unavailable("DELL U2723QE is not connected."))
        var first = dell, second = dell
        first.id = 7
        second.id = 8
        #expect(plan(change(1, 2), displays: [first, second])
            == .unavailable("More than one connected display looks like DELL U2723QE, so Resolute can’t tell which one changed."))
        // The display that had the change keeps its ID, so it is the one.
        #expect(plan(change(1, 2), displays: [first, HistorySample.on(dell, at: 2)]) == .switchMode(display: HistorySample.on(dell, at: 2), mode: dell.modes[0]))
    }

    @Test func doesNothingWhenTheModeIsAlreadyBack() {
        #expect(plan(change(1, 2), displays: [HistorySample.on(dell, at: 1)]) == .alreadyCurrent("DELL U2723QE is already at 1920 × 1080."))
        let refresh = change(54, 55, on: HistorySample.builtIn)
        #expect(plan(refresh, displays: [HistorySample.on(HistorySample.builtIn, at: 54)])
            == .alreadyCurrent("Built-in Retina Display is already at 120 Hz."))
    }

    @Test func putsBackAHiddenModeOnlyInTheSameLogin() {
        let entry = change(90, 2)
        let now = HistorySample.on(dell, at: 2)
        let back = plan(entry, displays: [now])
        #expect(back == .switchMode(display: now, mode: dell.modes[3]))
        #expect(back.needsTrial)
        let loggedOut = HistoryUndo.Plan.unavailable("2880 × 1620 was a hidden mode, and a hidden mode can’t come back after you log out.")
        #expect(plan(entry, displays: [now], session: "AE062952-A3E9-47CA-80BB-A00418E712FE/100031") == loggedOut)
        #expect(plan(entry, displays: [now], session: nil) == loggedOut)
        var unknownLogin = entry
        unknownLogin.loginSession = nil
        #expect(plan(unknownLogin, displays: [now]) == loggedOut)
    }

    @Test func saysWhenAModeIsNoLongerOffered() {
        var withoutHidden = HistorySample.on(dell, at: 2)
        withoutHidden.modes.removeAll { $0.origin == .hidden }
        #expect(plan(change(90, 2), displays: [withoutHidden]) == .unavailable("2880 × 1620 was a hidden mode that DELL U2723QE no longer offers."))
        // A listed mode comes back only as a listed one.
        var hiddenNow = HistorySample.on(dell, at: 2)
        hiddenNow.modes[0].origin = .hidden
        #expect(plan(change(1, 2), displays: [hiddenNow]) == .unavailable("DELL U2723QE no longer offers 1920 × 1080."))
        // When only the rate changed, the message names the whole mode.
        var builtIn = HistorySample.on(HistorySample.builtIn, at: 55)
        let refresh = change(54, 55, on: builtIn)
        builtIn.modes.removeAll { $0.modeID == 54 }
        #expect(plan(refresh, displays: [builtIn]) == .unavailable("Built-in Retina Display no longer offers 1728 × 1117 at 120 Hz."))
        var fast = dell
        fast.modes.append(HistorySample.mode(92, 2560, 1440, hz: 75, flags: 0x1, origin: .hidden))
        let hiddenRate = change(92, 2, on: fast)
        #expect(plan(hiddenRate, displays: [HistorySample.on(fast, at: 2)], session: nil)
            == .unavailable("2560 × 1440 at 75 Hz was a hidden mode, and a hidden mode can’t come back after you log out."))
    }

    @Test func prefersTheClosestOfModesThatLookAlike() {
        var display = HistorySample.on(dell, at: 2)
        display.modes = [
            HistorySample.mode(5, 1920, 1080, bits: 8, origin: .hidden), HistorySample.mode(6, 1920, 1080, bits: 8),
            HistorySample.mode(7, 1920, 1080, bits: 10), display.modes[1],
        ]
        let before = HistorySample.on(display, at: 7)
        let entry = HistoryEntry(
            date: HistorySample.now, source: .panel,
            change: .mode(.init(display: before, to: display.modes[3])), outcome: .applied, loginSession: session
        )
        #expect(plan(entry, displays: [display]) == .switchMode(display: display, mode: display.modes[2]))
        var renumbered = display
        renumbered.modes[2].modeID = 70
        #expect(plan(entry, displays: [renumbered]) == .switchMode(display: renumbered, mode: renumbered.modes[2]))
    }

    @Test func undoesOnlyAChangeThatIsInPlace() {
        let reverted = change(2, 90, outcome: .reverted(.noAnswer))
        #expect(plan(reverted, displays: [dell]) == .unavailable("This change was reverted, so there is nothing to undo."))
        let failed = change(1, 2, outcome: .failed(message: "No."))
        #expect(plan(failed, displays: [dell]) == .unavailable("This change did not happen, so there is nothing to undo."))
        let done = change(1, 2)
        let undo = HistoryEntry(source: .panel, change: HistorySample.modeChange(dell, from: 2, to: 1), outcome: .undone(of: done.id))
        #expect(plan(done, displays: [dell], others: [undo]) == .unavailable("This change was already undone."))
        let unknown = HistoryEntry(source: .panel, change: .mode(.init(display: .init(dell), from: nil, to: .init(dell.modes[1]))), outcome: .applied)
        #expect(plan(unknown, displays: [dell])
            == .unavailable("Resolute did not learn which mode DELL U2723QE used before this change, so there is nothing to put back."))
    }

    @Test func turnsMirroringBack() {
        let on = HistoryEntry(source: .shortcuts, change: .mirroring(.init(isOn: true, displays: [])), outcome: .applied)
        var mirrored = [HistorySample.builtIn, dell]
        for index in mirrored.indices { mirrored[index].isInMirrorSet = true }
        #expect(plan(on, displays: mirrored) == .setMirroring(false))
        #expect(plan(on, displays: [HistorySample.builtIn, dell]) == .alreadyCurrent("Mirroring is already off."))
        let off = HistoryEntry(source: .shortcuts, change: .mirroring(.init(isOn: false, displays: [])), outcome: .applied)
        #expect(plan(off, displays: [HistorySample.builtIn, dell]) == .setMirroring(true))
        #expect(plan(off, displays: mirrored) == .alreadyCurrent("Mirroring is already on."))
        #expect(plan(off, displays: [dell]) == .unavailable("Mirroring needs at least two displays."))
    }

    @Test func knowsThisLogin() throws {
        let login = try #require(LoginSession.current)
        #expect(login.contains("/"))
        #expect(LoginSession.current == login)
    }
}

// MARK: - Recording

@Suite struct HistoryRecorderTests {
    let dell = HistorySample.dell

    func recorder(_ store: HistoryStore, source: HistoryEntry.Source = .panel) -> HistoryRecorder {
        HistoryRecorder(store: store, source: source, onFailure: { _ in }, now: { HistorySample.now }, loginSession: { HistorySample.session })
    }

    @Test func recordsHowEachSwitchEnded() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let history = recorder(store)
        let before = HistorySample.on(dell, at: 2)
        let hidden = dell.modes[3]
        #expect(history.record(.alreadyCurrent, switching: before, to: hidden) == nil)
        let pending = ModeSwitcher.PendingRestore(displayID: 2, displayName: "DELL U2723QE", modeID: 2, fallbackModeID: nil, trialModeID: 90)
        #expect(history.record(.restorePending(pending), switching: before, to: hidden) == nil)
        let outcomes: [(ModeSwitcher.Outcome, HistoryEntry.Outcome)] = [
            (.applied, .applied), (.kept, .kept), (.keptForSession, .keptForSession),
            (.reverted(to: 2), .reverted(.noAnswer)), (.leftAlone(current: 3), .reverted(.displayChanged)),
        ]
        for (switched, recorded) in outcomes {
            let entry = try #require(history.record(switched, switching: before, to: hidden, revertReason: .noAnswer))
            #expect(entry.outcome == recorded)
            #expect(entry.loginSession == HistorySample.session)
            #expect(entry.change == .mode(.init(display: .init(before), from: .init(dell.modes[1]), to: .init(hidden))))
        }
        #expect(try store.entries().count == outcomes.count)
    }

    @Test func recordsFailuresButNotRefusals() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let history = recorder(store)
        #expect(history.record(ResoluteError.usage("No."), switching: dell, to: dell.modes[3]) == nil)
        #expect(history.record(ResoluteError.displayChangedDuringTrial(display: "DELL U2723QE"), switching: dell, to: dell.modes[3])?.outcome
            == .reverted(.displayChanged))
        let failure = ResoluteError.modeNotApplied(display: "DELL U2723QE")
        #expect(history.record(failure, switching: dell, to: dell.modes[3])?.outcome == .failed(message: failure.localizedDescription))
    }

    /// Mirroring a single display changes nothing, so it is not recorded; a real failure is.
    @Test func recordsMirroringFailuresButNotRefusals() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let history = recorder(store)
        let displays = [HistorySample.builtIn]
        #expect(history.recordMirroring(true, displays: displays, failedWith: ResoluteError.mirroringNeedsTwoDisplays) == nil)
        #expect(history.recordMirroring(true, displays: displays, failedWith: ResoluteError.usage("No.")) == nil)
        let failure = ResoluteError.coreGraphics(code: 1001, operation: "mirror the displays")
        #expect(history.recordMirroring(true, displays: displays, failedWith: failure)?.outcome == .failed(message: failure.localizedDescription))
        #expect(try store.entries().count == 1)
    }

    @Test func recordsMirroringWithTheDisplaysItInvolved() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let history = recorder(store, source: .shortcuts)
        let builtIn = HistorySample.builtIn
        let on = try #require(history.recordMirroring(true, displays: [builtIn, dell]))
        #expect(HistoryText.title(of: on.change) == "Mirroring on: Built-in + DELL U2723QE")
        var mirrored = [builtIn, dell, HistorySample.on(dell, at: 1)]
        mirrored[2].name = "Studio Display"
        mirrored[0].isInMirrorSet = true
        mirrored[1].isInMirrorSet = true
        let off = try #require(history.recordMirroring(false, displays: mirrored))
        #expect(HistoryText.title(of: off.change) == "Mirroring off: Built-in + DELL U2723QE")
    }

    @Test func recordsAPresetsChangesAsItsOwn() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let history = recorder(store, source: .agent(name: "Claude Code", app: "Terminal"))
        let entry = try #require(history.applying(preset: "Coding").recordSwitch(of: dell, to: dell.modes[0], outcome: .applied))
        #expect(entry.source == .preset(name: "Coding", via: .agent(name: "Claude Code", app: "Terminal")))
        #expect(HistoryText.detail(of: entry) == "From Claude Code (Terminal) · “Coding” preset")
        #expect(history.from(.dock).source == .dock)
    }

    @Test func recordsAnUndoAsTheStatusOfTheChange() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let history = recorder(store, source: .terminal(app: "Terminal"))
        let original = try #require(history.record(.applied, switching: HistorySample.on(dell, at: 1), to: dell.modes[1]))
        let now = HistorySample.on(dell, at: 2)
        let plan = HistoryUndo.plan(for: original, in: HistoryTimeline(entries: try store.entries()), displays: [now], loginSession: HistorySample.session)
        let undo = try #require(history.from(.panel).recordUndo(of: original, plan: plan))
        #expect(undo.outcome == .undone(of: original.id))
        #expect(undo.change == .mode(.init(display: .init(now), from: .init(dell.modes[1]), to: .init(dell.modes[0]))))
        let timeline = HistoryTimeline(entries: try store.entries())
        #expect(timeline.changes() == [original])
        #expect(timeline.status(of: original) == .undone)
        #expect(timeline.lastOutsideChange == nil)
    }

    @Test func leavesAChangeInPlaceWhenItsUndoIsReverted() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let history = recorder(store)
        let original = try #require(history.record(.applied, switching: HistorySample.on(dell, at: 90), to: dell.modes[1]))
        let plan = HistoryUndo.Plan.switchMode(display: HistorySample.on(dell, at: 2), mode: dell.modes[3])
        let attempt = try #require(history.recordUndo(of: original, plan: plan, outcome: .reverted(to: 2)))
        #expect(attempt.outcome == .reverted(.unspecified))
        let timeline = HistoryTimeline(entries: try store.entries())
        #expect(timeline.status(of: original) == .kept)
        #expect(timeline.changes().count == 2)
    }

    @Test func marksAChangeUndoneWhenNothingNeededToSwitch() throws {
        let store = try HistorySample.store()
        defer { HistorySample.remove(store) }
        let history = recorder(store)
        let original = try #require(history.recordMirroring(true, displays: [HistorySample.builtIn, dell]))
        #expect(history.recordUndo(of: original, plan: .unavailable("No.")) == nil)
        let undo = try #require(history.recordUndo(of: original, plan: .alreadyCurrent("Mirroring is already off.")))
        #expect(HistoryText.title(of: undo.change) == "Mirroring off: Built-in + DELL U2723QE")
        #expect(HistoryTimeline(entries: try store.entries()).status(of: original) == .undone)
        let failed = try #require(history.recordFailedUndo(of: original, plan: .setMirroring(false), error: ResoluteError.mirroringNeedsTwoDisplays))
        #expect(failed.outcome == .failed(message: "Mirroring needs at least two displays."))
    }

    @Test func goesOnWhenHistoryCannotBeWritten() throws {
        // A file where the support folder should be.
        let file = try makeTemporaryDirectory().appending(path: "Resolute")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try Data().write(to: file)
        let failures = OSAllocatedUnfairLock(initialState: 0)
        let store = HistoryStore(locations: SupportLocations(root: file), maximumFileSize: 1 << 20, owner: nil, now: { HistorySample.now })
        let history = HistoryRecorder(
            store: store, source: .panel, onFailure: { _ in failures.withLock { $0 += 1 } }, now: { HistorySample.now }, loginSession: { nil }
        )
        #expect(history.recordSwitch(of: dell, to: dell.modes[0], outcome: .applied) == nil)
        #expect(failures.withLock { $0 } == 1)
    }

    @Test func namesWhoRanTheCommand() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let history = HistoryRecorder.commandLine(support: SupportLocations(root: root), requester: Requester(agent: "Codex", app: "Ghostty"))
        #expect(history.source == .agent(name: "Codex", app: "Ghostty"))
        #expect(history.store.locations.root == root)
    }
}

// MARK: - Who ran the command

@Suite struct RequesterTests {
    func who(_ environment: [String: String], _ ancestors: [Requester.Ancestor] = []) -> Requester {
        Requester.identify(environment: environment, ancestors: ancestors)
    }

    @Test func namesClaudeCodeAndItsTerminal() {
        let requester = who(["CLAUDECODE": "1", "TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"])
        #expect(requester == Requester(agent: "Claude Code", app: "Terminal"))
        #expect(requester.name == "Claude Code (Terminal)")
        #expect(requester.source == .agent(name: "Claude Code", app: "Terminal"))
        // As this Mac's Claude Code runs commands in iTerm.
        #expect(who([
            "CLAUDECODE": "1", "AI_AGENT": "claude-code_2-1-312_agent", "TERM_PROGRAM": "iTerm.app",
            "LC_TERMINAL": "iTerm2", "__CFBundleIdentifier": "com.googlecode.iterm2",
        ]) == Requester(agent: "Claude Code", app: "iTerm"))
    }

    @Test func namesAPersonByTheirTerminal() {
        let person = who(["TERM_PROGRAM": "Apple_Terminal"])
        #expect(person == Requester(agent: nil, app: "Terminal"))
        #expect(person.name == "Terminal")
        #expect(person.source == .terminal(app: "Terminal"))
        #expect(who(["TERM_PROGRAM": "iTerm.app"]).app == "iTerm")
        #expect(who(["TERM_PROGRAM": "ghostty"]).app == "Ghostty")
        #expect(who(["TERM_PROGRAM": "WarpTerminal"]).app == "Warp")
        #expect(who(["TERM_PROGRAM": "zed"]).app == "Zed")
        #expect(who(["TERM_PROGRAM": "vscode"]).app == "VS Code")
        #expect(who(["TERM_PROGRAM": "vscode", "__CFBundleIdentifier": "com.todesktop.230313mzl4w4u92"]).app == "Cursor")
        #expect(who(["TERM_PROGRAM": "MyTerm"]).app == "MyTerm")
        #expect(who(["KITTY_WINDOW_ID": "1"]).app == "kitty")
        #expect(who(["ALACRITTY_SOCKET": "/tmp/a.sock"]).app == "Alacritty")
        // tmux hides the terminal; iTerm's own variable still names it.
        #expect(who(["TERM_PROGRAM": "tmux", "LC_TERMINAL": "iTerm2"]).app == "iTerm")
        #expect(who(["TERM_PROGRAM": "tmux"]).app == "tmux")
        #expect(who([:]) == Requester())
        #expect(who([:]).name == "the resolute command")
    }

    @Test func namesOtherAgentsByWhatTheyMarkCommandsWith() {
        #expect(who(["CODEX_THREAD_ID": "019a", "TERM_PROGRAM": "ghostty"]) == Requester(agent: "Codex", app: "Ghostty"))
        #expect(who(["CODEX_SANDBOX": "seatbelt"]).agent == "Codex")
        #expect(who(["GEMINI_CLI": "1", "TERM_PROGRAM": "WarpTerminal"]) == Requester(agent: "Gemini CLI", app: "Warp"))
        #expect(who(["QWEN_CODE": "1"]).agent == "Qwen Code")
        #expect(who(["CURSOR_AGENT": "1", "TERM_PROGRAM": "Apple_Terminal"]) == Requester(agent: "Cursor", app: "Terminal"))
        #expect(who(["ANTIGRAVITY_AGENT": "1"]).agent == "Antigravity")
        #expect(who(["OPENCODE": "1", "AGENT": "1"]).agent == "OpenCode")
        // OpenCode's terminal panel is a person typing.
        #expect(who(["OPENCODE": "1", "OPENCODE_TERMINAL": "1"]) == Requester(agent: nil, app: "OpenCode"))
        #expect(who(["AI_AGENT": "claude-code_2-1-312_agent"]).agent == "Claude Code")
        #expect(who(["AI_AGENT": "some-new-agent_1-0_agent"]).agent == "Some New Agent")
        #expect(who(["CLAUDECODE": "0"]).agent == nil)
        #expect(who(["CLAUDECODE": ""]).agent == nil)
        #expect(who(["GEMINI_CLI": "false"]).agent == nil)
    }

    @Test func namesAnAgentInItsOwnAppOnce() {
        let desktop = who(["CLAUDECODE": "1", "__CFBundleIdentifier": "com.anthropic.claudefordesktop"])
        #expect(desktop == Requester(agent: "Claude Code", app: nil))
        #expect(desktop.name == "Claude Code")
        #expect(who(["CURSOR_AGENT": "1", "TERM_PROGRAM": "vscode", "__CFBundleIdentifier": "com.todesktop.230313mzl4w4u92"])
            == Requester(agent: "Cursor", app: nil))
    }

    @Test func looksAtTheProcessesUnderSudo() {
        // sudo drops the variables, so the processes that started the command tell.
        let chain = [
            Requester.Ancestor(name: "sudo"), .init(name: "zsh"), .init(name: "claude"), .init(name: "bash"), .init(name: "zsh"),
            .init(name: "login"), .init(name: "iTermServer-3.7.6"),
            .init(name: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", bundleName: "iTerm2"),
        ]
        #expect(who(["SUDO_USER": "omar"], chain) == Requester(agent: "Claude Code", app: "iTerm"))
        #expect(who([:], [.init(name: "sudo"), .init(name: "zsh"), .init(name: "login"), .init(name: "Terminal")]) == Requester(app: "Terminal"))
        #expect(who([:], [.init(name: "zsh"), .init(name: "Nova", bundleIdentifier: "com.panic.Nova", bundleName: "Nova")]).app == "Nova")
        #expect(who([:], [.init(name: "zsh"), .init(name: "codex")]).agent == "Codex")
    }

    @Test func picksTheNearestOfTwoAgents() {
        let marks = ["CLAUDECODE": "1", "CODEX_THREAD_ID": "019a"]
        #expect(who(marks, [.init(name: "zsh"), .init(name: "claude"), .init(name: "zsh"), .init(name: "codex")]).agent == "Claude Code")
        #expect(who(marks, [.init(name: "zsh"), .init(name: "codex"), .init(name: "zsh"), .init(name: "claude")]).agent == "Codex")
        #expect(who(marks).agent == "Claude Code")
    }

    @Test func readsTheProcessesThatStartedThisOne() {
        let ancestors = Requester.Ancestor.current()
        #expect(!ancestors.isEmpty)
        #expect(ancestors.allSatisfy { !$0.name.isEmpty })
    }

    @Test func countsOnlyAnAppsOwnProgramsAsTheApp() {
        #expect(Requester.Ancestor.appPath(containing: "/Applications/iTerm.app/Contents/MacOS/iTerm2") == "/Applications/iTerm.app")
        #expect(Requester.Ancestor.appPath(containing: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
            == "/System/Applications/Utilities/Terminal.app")
        // A helper app is part of its app.
        #expect(Requester.Ancestor.appPath(
            containing: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"
        ) == "/Applications/Visual Studio Code.app")
        // Tools that only live inside an app, like `swift` in Xcode, are not the app.
        #expect(Requester.Ancestor.appPath(
            containing: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-package"
        ) == nil)
        #expect(Requester.Ancestor.appPath(containing: "/Applications/Claude.app/Contents/Resources/claude-code/claude") == nil)
        #expect(Requester.Ancestor.appPath(containing: "/bin/zsh") == nil)
    }
}

/// A preset applied with its keyboard shortcut says so in History.
@Suite struct KeyboardSourceTests {
    @Test func namesAndFilesAKeyboardShortcut() throws {
        let source = HistoryEntry.Source.preset(name: "Coding", via: .keyboard)
        #expect(source.name == "a keyboard shortcut")
        #expect(source.symbolName == "keyboard")
        #expect(source.category == .panel)
        let data = try JSONEncoder().encode(source)
        #expect(try JSONDecoder().decode(HistoryEntry.Source.self, from: data) == source)
    }
}
