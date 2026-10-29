import Foundation
import ResoluteKit
import Testing
@testable import resolute

/// `resolute history` reads the file the app and the command share; these tests point the
/// command at a temporary support folder.
@Suite struct HistoryCommandTests {
    let root: URL

    init() throws {
        root = try stagedRoot().appending(path: "Resolute", directoryHint: .isDirectory)
    }

    var support: SupportLocations { SupportLocations(root: root) }

    /// Removes the folder `init` made.
    func cleanUp() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    /// Runs `resolute history` with `arguments`, as `main` does.
    func history(_ arguments: [String] = []) async -> (output: String, errors: String, message: String?, code: Int32) {
        let transcript = Transcript()
        let result = await ResoluteCommand.execute(["history"] + arguments, in: context(transcript))
        return (transcript.output, transcript.errors, result.message, result.code)
    }

    func context(_ transcript: Transcript) -> CommandContext {
        var context = transcript.context(service: FakeDisplays([Sample.builtIn, Sample.monitor]), isRoot: false, decision: .revert)
        context.support = support
        return context
    }

    /// `display` showing `from`, switched to `to`.
    static func change(_ display: Display, from: Int32, to: Int32) -> HistoryEntry.Change {
        var before = display
        before.currentModeID = from
        return .mode(HistoryEntry.ModeChange(display: before, to: display.modes.first { $0.modeID == to }!))
    }

    /// A day of changes, from `now` back: an agent's hidden trial nobody answered, a change
    /// typed in Terminal, the panel's refresh rate, a preset from Shortcuts and a panel change
    /// that was undone.
    static func day(before now: Date) -> [HistoryEntry] {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let resized = HistoryEntry(date: ago(50), source: .panel, change: change(Sample.builtIn, from: 54, to: 42), outcome: .applied)
        return [
            HistoryEntry(
                date: ago(1), source: .agent(name: "Claude Code", app: "Terminal"), change: change(Sample.monitor, from: 1, to: 91),
                outcome: .reverted(.noAnswer)
            ),
            HistoryEntry(date: ago(3), source: .terminal(app: "Terminal"), change: change(Sample.monitor, from: 3, to: 1), outcome: .applied),
            HistoryEntry(date: ago(20), source: .panel, change: change(Sample.builtIn, from: 54, to: 55), outcome: .applied),
            HistoryEntry(
                date: ago(30), source: .preset(name: "Presenting", via: .shortcuts),
                change: .mirroring(.init(isOn: true, displays: [.init(Sample.builtIn), .init(Sample.monitor)])), outcome: .applied
            ),
            HistoryEntry(date: ago(49), source: .panel, change: change(Sample.builtIn, from: 42, to: 54), outcome: .undone(of: resized.id)),
            resized,
        ]
    }

    func write(_ entries: [HistoryEntry]) throws {
        let store = HistoryStore(locations: support)
        for entry in entries.reversed() { try store.append(entry) }
    }

    @Test func printsTwoLinesPerChangeLikeTheHistoryPage() {
        defer { cleanUp() }
        var calendar = Calendar(identifier: .gregorian)
        let london = TimeZone(identifier: "Europe/London")!
        calendar.timeZone = london
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9, minute: 41))!
        func at(_ day: Int, _ hour: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        let resized = HistoryEntry(date: at(22, 10), source: .panel, change: Self.change(Sample.builtIn, from: 54, to: 42), outcome: .applied)
        let entries = [
            HistoryEntry(
                date: at(26, 20), source: .agent(name: "Claude Code", app: "Terminal"), change: Self.change(Sample.monitor, from: 1, to: 91),
                outcome: .reverted(.noAnswer)
            ),
            HistoryEntry(date: at(26, 19), source: .terminal(app: "Terminal"), change: Self.change(Sample.monitor, from: 3, to: 1), outcome: .applied),
            HistoryEntry(date: at(24, 12), source: .panel, change: Self.change(Sample.builtIn, from: 54, to: 55), outcome: .applied),
            HistoryEntry(
                date: at(24, 11), source: .preset(name: "Presenting", via: .shortcuts),
                change: .mirroring(.init(isOn: true, displays: [.init(Sample.builtIn), .init(Sample.monitor)])), outcome: .applied
            ),
            HistoryEntry(date: at(22, 11), source: .panel, change: Self.change(Sample.builtIn, from: 42, to: 54), outcome: .undone(of: resized.id)),
            resized,
        ]
        let items = HistoryTimeline(entries: entries).items(now: now, timeZone: london, locale: Locale(identifier: "en_GB"))
        #expect(HistoryCommand.render(items) == """
            Yesterday  Reverted  DELL P2419H  1920 × 1080 → 2560 × 1440
                                 From Claude Code (Terminal) · hidden mode · nobody answered
            Yesterday  Kept      DELL P2419H  1280 × 720 → 1920 × 1080
                                 From Terminal
            Saturday   Kept      Built-in Retina Display  120 Hz → 60 Hz
                                 From the panel
            Saturday   Kept      Mirroring on: Built-in + DELL P2419H
                                 From Shortcuts · “Presenting” preset
            Thursday   Undone    Built-in Retina Display  1728 × 1117 → 1496 × 967
                                 From the panel
            """)
    }

    @Test func listsChangesNewestFirst() async throws {
        defer { cleanUp() }
        let entries = Self.day(before: Date())
        try write(entries)
        let run = await history()
        #expect(run.code == 0)
        let expected = HistoryCommand.render(HistoryTimeline(entries: try HistoryStore(locations: support).entries()).items())
        #expect(run.output == expected)
        let lines = run.output.split(separator: "\n").map(String.init)
        #expect(lines.count == 10)
        #expect(lines[0].hasSuffix("Reverted  DELL P2419H  1920 × 1080 → 2560 × 1440"))
        #expect(lines[1].hasSuffix("  From Claude Code (Terminal) · hidden mode · nobody answered"))
        #expect(lines[8].hasSuffix("Undone    Built-in Retina Display  1728 × 1117 → 1496 × 967"))
    }

    @Test func filtersByWhereChangesCameFrom() async throws {
        defer { cleanUp() }
        try write(Self.day(before: Date()))
        /// Two lines per change.
        func changes(_ source: String) async -> Int {
            await history(["--source", source]).output.split(separator: "\n").count / 2
        }
        #expect(await changes("terminal") == 2)
        #expect(await history(["--source", "terminal"]).output.contains("From Claude Code (Terminal)"))
        #expect(await history(["--source", "shortcuts"]).output.contains("Mirroring on: Built-in + DELL P2419H"))
        #expect(await changes("shortcuts") == 1)
        #expect(await changes("panel") == 2)
        #expect(await changes("all") == 5)
        #expect(!(await history(["--source", "panel"]).output.contains("From Terminal")))
    }

    @Test func showsAtMostTheLimit() async throws {
        defer { cleanUp() }
        try write(Self.day(before: Date()))
        let output = await history(["--limit", "2"]).output
        #expect(output.split(separator: "\n").count == 4)
        #expect(output.contains("From Terminal"))
        #expect(!output.contains("From the panel"))
    }

    @Test func saysWhenThereIsNothing() async throws {
        defer { cleanUp() }
        #expect(await history().output == "No display changes in the last 7 days.")
        #expect(!FileManager.default.fileExists(atPath: root.path(percentEncoded: false)))
        try write([Self.day(before: Date())[2]])
        #expect(await history(["--source", "shortcuts"]).output == "No display changes from Shortcuts in the last 7 days.")
        #expect(await history(["--source", "terminal"]).output == "No display changes from Terminal or agents in the last 7 days.")
        let json = await history(["--json", "--source", "shortcuts"]).output
        #expect((try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any])?.isEmpty == true)
    }

    @Test func skipsLinesItCannotRead() async throws {
        defer { cleanUp() }
        let entry = Self.day(before: Date())[1]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let line = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        try Data("garbage\n\(line)\n{\"v\":1".utf8).write(to: support.historyFile)
        let run = await history()
        #expect(run.code == 0)
        #expect(run.output.hasSuffix("From Terminal"))
        #expect(run.output.split(separator: "\n").count == 2)
    }

    @Test func rejectsALimitBelowOneAndAnUnknownSource() async {
        defer { cleanUp() }
        let limit = await history(["--limit", "0"])
        #expect(limit.code == 64)
        #expect(limit.message?.hasPrefix("Error: --limit takes 1 or more.\nUsage: resolute history") == true)
        let source = await history(["--source", "agents"])
        #expect(source.code == 64)
        #expect(source.message?.contains("'all', 'panel', 'terminal' or 'shortcuts'") == true)
    }

    /// Every key is always present, null when there is no value, like every other command's JSON.
    @Test func givesEveryKeyInJSON() async throws {
        defer { cleanUp() }
        var entries = Self.day(before: Date())
        let failed = HistoryEntry(
            date: Date().addingTimeInterval(-90 * 60), source: .terminal(app: nil), change: Self.change(Sample.monitor, from: 1, to: 90),
            outcome: .failed(message: "DELL P2419H did not switch to that mode, so it was left as it was.")
        )
        let gone = UUID()
        let orphan = HistoryEntry(
            date: Date().addingTimeInterval(-100 * 60), source: .window, change: Self.change(Sample.monitor, from: 2, to: 1),
            outcome: .undone(of: gone)
        )
        entries += [failed, orphan]
        try write(entries)
        let output = await history(["--json"]).output
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
        let keys: Set<String> = [
            "id", "date", "source", "agent", "app", "preset", "change", "display", "displayID", "from", "to", "mirroring",
            "mirroredDisplays", "hiddenMode", "outcome", "reason", "message", "status", "canUndo", "undoneAt", "undoneFrom", "undoes",
            "title", "detail",
        ]
        #expect(rows.count == 7)
        #expect(rows.allSatisfy { Set($0.keys) == keys })

        let tried = rows[0]
        #expect(tried["id"] as? String == entries[0].id.uuidString)
        #expect(tried["date"] as? String == ISO8601DateFormatter().string(from: entries[0].date))
        #expect(tried["source"] as? String == "agent")
        #expect(tried["agent"] as? String == "Claude Code")
        #expect(tried["app"] as? String == "Terminal")
        #expect(tried["preset"] is NSNull)
        #expect(tried["change"] as? String == "mode")
        #expect(tried["display"] as? String == "DELL P2419H")
        #expect(tried["displayID"] as? Int == 2)
        let to = try #require(tried["to"] as? [String: Any])
        #expect(Set(to.keys) == ["modeID", "width", "height", "pixelWidth", "pixelHeight", "refreshRate", "hidden"])
        #expect(to["modeID"] as? Int == 91)
        #expect(to["hidden"] as? Bool == true)
        #expect((tried["from"] as? [String: Any])?["width"] as? Int == 1920)
        #expect(tried["mirroring"] is NSNull)
        #expect(tried["mirroredDisplays"] is NSNull)
        #expect(tried["hiddenMode"] as? Bool == true)
        #expect(tried["outcome"] as? String == "reverted")
        #expect(tried["reason"] as? String == "noAnswer")
        #expect(tried["message"] is NSNull)
        #expect(tried["status"] as? String == "reverted")
        #expect(tried["canUndo"] as? Bool == false)
        #expect(tried["undoneAt"] is NSNull)
        #expect(tried["undoneFrom"] is NSNull)
        #expect(tried["undoes"] is NSNull)
        #expect(tried["title"] as? String == "DELL P2419H  1920 × 1080 → 2560 × 1440")
        #expect(tried["detail"] as? String == "From Claude Code (Terminal) · hidden mode · nobody answered")

        let typed = rows[1]
        #expect(typed["source"] as? String == "terminal")
        #expect(typed["agent"] is NSNull)
        #expect(typed["status"] as? String == "kept")
        #expect(typed["canUndo"] as? Bool == true)

        let mirrored = rows[3]
        #expect(mirrored["source"] as? String == "shortcuts")
        #expect(mirrored["preset"] as? String == "Presenting")
        #expect(mirrored["change"] as? String == "mirroring")
        #expect(mirrored["display"] is NSNull)
        #expect(mirrored["displayID"] is NSNull)
        #expect(mirrored["from"] is NSNull)
        #expect(mirrored["to"] is NSNull)
        #expect(mirrored["mirroring"] as? Bool == true)
        #expect(mirrored["mirroredDisplays"] as? [String] == ["Built-in Retina Display", "DELL P2419H"])
        #expect(mirrored["app"] is NSNull)

        let resized = rows[4]
        #expect(resized["outcome"] as? String == "applied")
        #expect(resized["status"] as? String == "undone")
        #expect(resized["canUndo"] as? Bool == false)
        #expect(resized["undoneAt"] as? String == ISO8601DateFormatter().string(from: entries[4].date))
        #expect(resized["undoneFrom"] as? String == "panel")

        let failure = rows[5]
        #expect(failure["outcome"] as? String == "failed")
        #expect(failure["status"] as? String == "failed")
        #expect(failure["message"] as? String == "DELL P2419H did not switch to that mode, so it was left as it was.")
        #expect(failure["app"] is NSNull)
        #expect(failure["detail"] as? String
            == "From the resolute command · hidden mode · DELL P2419H did not switch to that mode, so it was left as it was.")

        let undo = rows[6]
        #expect(undo["source"] as? String == "window")
        #expect(undo["outcome"] as? String == "undone")
        #expect(undo["undoes"] as? String == gone.uuidString)
        #expect(undo["status"] as? String == "kept")
    }

    @Test func limitsAndFiltersJSONLikeText() async throws {
        defer { cleanUp() }
        try write(Self.day(before: Date()))
        let output = await history(["--json", "--source", "terminal", "--limit", "1"]).output
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
        #expect(rows.count == 1)
        #expect(rows.first?["agent"] as? String == "Claude Code")
    }

    @Test func recordsTheCommandsChangesAsWhoeverRanIt() async throws {
        defer { cleanUp() }
        let transcript = Transcript()
        var recording = context(transcript)
        recording.requester = { Requester(agent: "Codex", app: "iTerm") }
        let entry = try #require(recording.history.record(.applied, switching: Sample.monitor, to: Sample.monitor.modes[2]))
        #expect(entry.source == .agent(name: "Codex", app: "iTerm"))
        #expect(transcript.errors.isEmpty)
        let output = await history().output
        #expect(output.contains("DELL P2419H  1920 × 1080 → 1280 × 720"))
        #expect(output.contains(HistoryText.sourceText(.agent(name: "Codex", app: "iTerm"))))
    }

    @Test func warnsWhenTheChangeCannotBeAdded() throws {
        defer { cleanUp() }
        // A file where the support folder should be.
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: root)
        let transcript = Transcript()
        #expect(context(transcript).history.record(.applied, switching: Sample.monitor, to: Sample.monitor.modes[2]) == nil)
        #expect(transcript.errors.hasPrefix("warning: The change could not be added to Resolute’s history: Could not use "))
        #expect(transcript.errors.hasSuffix(": not a directory."))
    }
}
