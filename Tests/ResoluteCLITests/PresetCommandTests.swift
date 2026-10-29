import CoreGraphics
import Foundation
import ResoluteKit
import Testing
@testable import resolute

/// Runs `resolute preset …` against fake displays and a presets file in a fresh temporary
/// folder. Never the shared `resolute(_:)` helper: its context reads and writes the
/// person's own Application Support.
struct PresetHarness {
    let displays: FakeDisplays
    let service: any DisplayControlling
    let support: SupportLocations
    var isRoot = false

    init(_ displays: [Display] = [Sample.builtIn, Sample.monitor], refusing: Set<Int32> = [], ignoring: Set<Int32> = []) {
        let fake = FakeDisplays(displays, ignoring: ignoring)
        self.displays = fake
        service = refusing.isEmpty ? fake : PresetRefusingDisplays(fake, refusing: refusing)
        support = SupportLocations(root: FileManager.default.temporaryDirectory.appending(
            path: "Resolute preset 'tests' \(UUID().uuidString)", directoryHint: .isDirectory
        ))
    }

    private init(displays: FakeDisplays, support: SupportLocations) {
        self.displays = displays
        service = displays
        self.support = support
    }

    /// The same presets with other displays connected.
    func with(_ displays: [Display]) -> PresetHarness {
        PresetHarness(displays: FakeDisplays(displays), support: support)
    }

    var store: PresetStore { PresetStore(locations: support) }

    func remove() {
        try? FileManager.default.removeItem(at: support.root)
    }

    func context(_ transcript: Transcript) -> CommandContext {
        var context = transcript.context(service: service, isRoot: isRoot, decision: .revert)
        context.support = support
        return context
    }

    /// Parses `arguments` as a shell passes them and runs the command.
    @discardableResult
    func run(_ arguments: [String]) async throws -> Transcript {
        let command = try ResoluteCommand.parseAsRoot(arguments)
        guard let runnable = command as? any ContextCommand else {
            throw CLITestError.notRunnable(String(describing: type(of: command)))
        }
        let transcript = Transcript()
        try await runnable.run(in: context(transcript))
        return transcript
    }

    /// What the command line shows for `arguments`, through the same `execute` as `main`.
    func execute(_ arguments: [String]) async -> (message: String?, code: Int32, transcript: Transcript) {
        let transcript = Transcript()
        let result = await ResoluteCommand.execute(arguments, in: context(transcript))
        return (result.message, result.code, transcript)
    }
}

/// Fails chosen modes as CoreGraphics does, and passes everything else to `base`.
final class PresetRefusingDisplays: DisplayControlling, @unchecked Sendable {
    private let base: FakeDisplays
    private let refused: Set<Int32>

    init(_ base: FakeDisplays, refusing: Set<Int32>) {
        self.base = base
        refused = refusing
    }

    func displays() -> [Display] { base.displays() }
    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? { base.currentModeID(of: displayID) }
    func setMirroring(_ enabled: Bool) throws { try base.setMirroring(enabled) }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        guard !refused.contains(modeID) else { throw ResoluteError.coreGraphics(code: 1001, operation: "select the display mode") }
        try base.apply(modeID: modeID, to: displayID, scope: scope)
    }
}

@Suite struct PresetSaveCommandTests {
    @Test func savesTheCurrentSetupWithoutSwitchingAnything() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        let transcript = try await harness.run(["preset", "save", "Coding"])
        #expect(transcript.output == "Saved “Coding”: Built-in 1728 × 1117 at 120 Hz · DELL P2419H 1920 × 1080 at 60 Hz")
        #expect(transcript.errors.isEmpty)
        #expect(harness.displays.changes.isEmpty)
        #expect(harness.displays.mirroringCalls.isEmpty)
        let saved = try #require(try harness.store.load().presets.first)
        #expect(saved.displays.map(\.display.name) == ["Built-in Retina Display", "DELL P2419H"])
        #expect(saved.mirroring == false)
        #expect(FileManager.default.fileExists(atPath: harness.support.presetsFile.path(percentEncoded: false)))
    }

    @Test func savesOverAPresetOnlyWhenAsked() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        try harness.displays.apply(modeID: 42, to: 1, scope: .permanent)
        let refused = await harness.execute(["preset", "save", "coding"])
        #expect(refused.message == "Error: There is already a preset named “Coding”. "
            + "To save the current setup over it: resolute preset save coding --replace")
        #expect(refused.code == 1)
        let replaced = try await harness.run(["preset", "save", "coding", "--replace"])
        #expect(replaced.output == "Replaced “Coding” with the current setup: Built-in 1496 × 967 at 120 Hz · DELL P2419H 1920 × 1080 at 60 Hz")
        #expect(try harness.store.load().presets.map(\.name) == ["Coding"])
    }

    @Test func leavesOutADisplayInAHiddenMode() async throws {
        var hidden = Sample.monitor
        hidden.currentModeID = 90
        let harness = PresetHarness([Sample.builtIn, hidden])
        defer { harness.remove() }
        let transcript = try await harness.run(["preset", "save", "Coding"])
        #expect(transcript.output == "Saved “Coding”: Built-in 1728 × 1117 at 120 Hz")
        #expect(transcript.errors == "warning: DELL P2419H uses a hidden mode, which presets don’t switch to, so it was left out.")

        let alone = harness.with([hidden])
        let nothing = await alone.execute(["preset", "save", "Monitor"])
        #expect(nothing.message == "Error: There is nothing to save. "
            + "DELL P2419H uses a hidden mode, which presets don’t switch to, so it was left out.")
        #expect(nothing.code == 1)
    }

    @Test func refusesANameThatCantBeShown() async {
        let harness = PresetHarness()
        defer { harness.remove() }
        let blank = await harness.execute(["preset", "save", "  "])
        #expect(blank.code == 64)
        #expect(blank.message?.hasPrefix("Error: A preset needs a name.\nUsage: resolute preset save ") == true)
        let rename = await harness.execute(["preset", "rename", "Coding", "Two\nlines"])
        #expect(rename.code == 64)
        #expect(rename.message?.hasPrefix("Error: A preset name can’t have line breaks, tabs or other control characters.") == true)
        #expect(!FileManager.default.fileExists(atPath: harness.support.root.path(percentEncoded: false)))
    }

    /// Presets belong to the person: written under sudo, the file would be root's.
    @Test func leavesPresetsAloneUnderSudo() async throws {
        var harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        harness.isRoot = true
        for arguments in [["preset", "save", "Other"], ["preset", "delete", "Coding"], ["preset", "rename", "Coding", "Focus"]] {
            let result = await harness.execute(arguments)
            #expect(result.message == "Error: Presets belong to you, not the administrator: run resolute preset \(arguments[1]) without sudo.")
            #expect(result.code == 1)
        }
        #expect(try harness.store.load().presets.map(\.name) == ["Coding"])
        // Reading and applying need no writing.
        #expect(try await harness.run(["preset", "list"]).output.contains("Coding"))
        #expect(await harness.execute(["preset", "apply", "Coding"]).code == 0)
    }
}

@Suite struct PresetListCommandTests {
    @Test func saysHowToSaveTheFirstPreset() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        #expect(try await harness.run(["preset"]).output
            == "There are no presets yet. To save the current setup as one: resolute preset save <name>")
        let listed = try await harness.run(["preset", "list", "--json"]).output
        #expect((try JSONSerialization.jsonObject(with: Data(listed.utf8)) as? [Any])?.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: harness.support.root.path(percentEncoded: false)))
    }

    @Test func marksThePresetTheSetupMatches() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        try harness.displays.apply(modeID: 42, to: 1, scope: .permanent)
        try await harness.run(["preset", "save", "Small"])
        #expect(try await harness.run(["preset"]).output == """
               Coding  Built-in 1728 × 1117 at 120 Hz · DELL P2419H 1920 × 1080 at 60 Hz
            *  Small   Built-in 1496 × 967 at 120 Hz · DELL P2419H 1920 × 1080 at 60 Hz
            """)
        let coding = try #require(try harness.store.load().preset(named: "Coding"))
        let shortcut = try #require(KeyShortcut(key: "1", modifiers: [.control, .option]))
        try harness.store.update { try $0.setShortcut(shortcut, forPresetWithID: coding.id) }
        #expect(try await harness.run(["preset", "list"]).output == """
               Coding  ⌃⌥1  Built-in 1728 × 1117 at 120 Hz · DELL P2419H 1920 × 1080 at 60 Hz
            *  Small        Built-in 1496 × 967 at 120 Hz · DELL P2419H 1920 × 1080 at 60 Hz
            """)
    }

    @Test func warnsAboutAPresetItCantRead() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try FileManager.default.createDirectory(at: harness.support.root, withIntermediateDirectories: true)
        let file = harness.support.presetsFile
        try Data("""
            {"version": 1, "presets": [
              {"id": "11111111-1111-1111-1111-111111111111", "name": "Single", "displays": [{"isBuiltin": true, "refreshRate": 60}]},
              {"id": "22222222-2222-2222-2222-222222222222", "name": "Broken", "displays": [{"name": "DELL", "width": "wide", "height": 1}]}
            ]}
            """.utf8).write(to: file)
        let transcript = try await harness.run(["preset", "list"])
        #expect(transcript.output == "   Single  Built-in 60 Hz")
        #expect(transcript.errors == "warning: preset 2 (“Broken”) in \(file.path(percentEncoded: false)) can’t be read, "
            + "so it is left out: “displays.0.width” has the wrong type.")

        try Data("{not json".utf8).write(to: file)
        let unreadable = await harness.execute(["preset", "list"])
        #expect(unreadable.message == "Error: Could not read the presets in \(file.path(percentEncoded: false)): "
            + "it is not valid JSON. Fix the file, or move it away to start a new one.")
        #expect(unreadable.code == 1)
    }
}

@Suite struct PresetShowCommandTests {
    @Test func showsWhatApplyingWouldChange() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        #expect(try await harness.run(["preset", "show", "coding"]).output == """
            Coding
              Built-in Retina Display: 1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54 (in use)
              DELL P2419H: 1920 × 1080 @ 60 Hz, mode 1 (in use)
              Mirroring: off (in use)
            The current setup matches it.
            """)
        try harness.displays.apply(modeID: 42, to: 1, scope: .permanent)
        #expect(try await harness.run(["preset", "show", "Coding"]).output == """
            Coding
              Built-in Retina Display: 1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54
              DELL P2419H: 1920 × 1080 @ 60 Hz, mode 1 (in use)
              Mirroring: off (in use)
            Applying it would switch 1 display.
            """)
        let laptop = harness.with([Sample.builtIn])
        #expect(try await laptop.run(["preset", "show", "Coding"]).output == """
            Coding
              Built-in Retina Display: 1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54 (in use)
              DELL P2419H: 1920 × 1080 at 60 Hz (skipped: it is not connected)
              Mirroring: off (in use)
            Applying it would change nothing now.
            """)
    }

    @Test func suggestsTheNameThatWasMeant() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        let none = await harness.execute(["preset", "apply", "Morning Desk"])
        #expect(none.message == "Error: There is no preset named “Morning Desk”: there are no presets yet. "
            + "To save the current setup as one: resolute preset save 'Morning Desk'")
        #expect(none.code == 1)
        try await harness.run(["preset", "save", "Coding"])
        let typo = await harness.execute(["preset", "apply", "Codng"])
        #expect(typo.message == "Error: There is no preset named “Codng”. Did you mean “Coding”?")
        #expect(typo.code == 1)
        #expect(harness.displays.changes.isEmpty)
        #expect(await harness.execute(["preset", "show", "Office"]).message
            == "Error: There is no preset named “Office”. List them with `resolute preset list`.")
    }

    /// `ResoluteCommand.unknownCommandMessage` passes the word after `preset` here, since
    /// `list`, the default, would report it only as an unexpected argument.
    @Test func explainsAMistypedPresetCommand() {
        #expect(PresetCommand.commandNames == ["list", "show", "save", "apply", "delete", "rename"])
        #expect(PresetCommand.unknownCommandMessage(for: "aply") == "“aply” is not a preset command. Did you mean “resolute preset apply”?")
        #expect(PresetCommand.unknownCommandMessage(for: "delet") == "“delet” is not a preset command. Did you mean “resolute preset delete”?")
        #expect(PresetCommand.unknownCommandMessage(for: "Remove") == "“Remove” is not a preset command. Did you mean “resolute preset delete”?")
        #expect(PresetCommand.unknownCommandMessage(for: "use") == "“use” is not a preset command. Did you mean “resolute preset apply”?")
        #expect(PresetCommand.unknownCommandMessage(for: "help") == "“help” is not a preset command. Did you mean “resolute help preset”?")
        #expect(PresetCommand.unknownCommandMessage(for: "Morning Desk")
            == "“Morning Desk” is not a preset command. To apply a preset by that name, run “resolute preset apply 'Morning Desk'”.")
        for word in PresetCommand.commandNames + ["--json", "-h"] {
            #expect(PresetCommand.unknownCommandMessage(for: word) == nil, "\(word)")
        }
    }
}

@Suite struct PresetApplyCommandTests {
    @Test func switchesEveryDisplayBack() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        try harness.displays.apply(modeID: 42, to: 1, scope: .permanent)
        try harness.displays.apply(modeID: 2, to: 2, scope: .permanent)
        let before = harness.displays.changes.count
        let transcript = try await harness.run(["preset", "apply", "coding"])
        #expect(Array(harness.displays.changes.dropFirst(before)) == [
            .init(displayID: 1, modeID: 54, scope: .permanent), .init(displayID: 2, modeID: 1, scope: .permanent),
        ])
        #expect(transcript.output == """
            Mirroring is already off.
            Built-in Retina Display: 1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54
            DELL P2419H: 1920 × 1080 @ 60 Hz, mode 1
            """)
        #expect(transcript.errors.isEmpty)
        let again = try await harness.run(["preset", "apply", "Coding"])
        #expect(again.output == """
            Mirroring is already off.
            Built-in Retina Display is already at 1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54.
            DELL P2419H is already at 1920 × 1080 @ 60 Hz, mode 1.
            """)
        #expect(harness.displays.changes.count == before + 2)
    }

    /// Each display a preset switches is its own History entry, named after the preset.
    @Test func recordsEachSwitchInHistory() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        try harness.displays.apply(modeID: 42, to: 1, scope: .permanent)
        try await harness.run(["preset", "apply", "Coding"])
        let entries = try HistoryStore(locations: harness.support).entries()
        #expect(entries.count == 1)
        #expect(entries.first?.source == .preset(name: "Coding", via: .terminal(app: nil)))
        #expect(entries.first?.outcome == .applied)
        // Applying again changes nothing, so History gains nothing.
        try await harness.run(["preset", "apply", "Coding"])
        #expect(try HistoryStore(locations: harness.support).entries().count == 1)
    }

    @Test func previewsWithoutChangingAnything() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        try harness.displays.apply(modeID: 42, to: 1, scope: .permanent)
        let before = harness.displays.changes
        #expect(try await harness.run(["preset", "apply", "Coding", "--dry-run"]).output == """
            Mirroring is already off.
            Would switch Built-in Retina Display to 1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54.
            DELL P2419H is already at 1920 × 1080 @ 60 Hz, mode 1.
            """)
        #expect(harness.displays.changes == before)
    }

    @Test func skipsADisplayThatIsNotConnected() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        let laptop = harness.with([Sample.builtIn])
        try laptop.displays.apply(modeID: 42, to: 1, scope: .permanent)
        let partly = await laptop.execute(["preset", "apply", "Coding"])
        #expect(partly.code == 0)
        #expect(partly.transcript.output == """
            Mirroring is already off.
            Built-in Retina Display: 1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54
            Skipped DELL P2419H: it is not connected.
            """)

        try await harness.with([Sample.monitor]).run(["preset", "save", "Monitor"])
        let nothing = await laptop.execute(["preset", "apply", "Monitor"])
        #expect(nothing.message == "Error: Nothing in “Monitor” applies to the displays connected now.")
        #expect(nothing.code == 1)
        #expect(nothing.transcript.output == "Skipped DELL P2419H: it is not connected.")
    }

    /// A display that can't switch doesn't stop the others; the command says which, and fails.
    @Test func reportsAPartialFailure() async throws {
        let harness = PresetHarness(refusing: [54])
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        try harness.displays.apply(modeID: 42, to: 1, scope: .permanent)
        try harness.displays.apply(modeID: 2, to: 2, scope: .permanent)
        let result = await harness.execute(["preset", "apply", "Coding"])
        #expect(result.message == "Error: “Coding” was applied only in part.")
        #expect(result.code == 1)
        #expect(result.transcript.output == "Mirroring is already off.\nDELL P2419H: 1920 × 1080 @ 60 Hz, mode 1")
        #expect(result.transcript.errors == "Could not switch Built-in Retina Display to 1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, "
            + "mode 54: CoreGraphics could not select the display mode: illegal argument (1001).")
    }

    @Test func doubtsASwitchTheDisplayDidNotShow() async throws {
        let harness = PresetHarness(ignoring: [54])
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        try harness.displays.apply(modeID: 42, to: 1, scope: .permanent)
        let result = await harness.execute(["preset", "apply", "Coding"])
        #expect(result.code == 0)
        #expect(result.transcript.errors == "warning: macOS accepted the change but Built-in Retina Display shows "
            + "1496 × 967 HiDPI (2992 × 1934 px) @ 120 Hz, mode 42 now.")
    }

    @Test func turnsMirroringOnFirst() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try harness.store.update { try $0.add(Preset(name: "Presenting", displays: [], mirroring: true)) }
        #expect(try await harness.run(["preset", "apply", "Presenting"]).output == "Mirroring is on.")
        #expect(harness.displays.mirroringCalls == [true])
        let alone = await harness.with([Sample.builtIn]).execute(["preset", "apply", "Presenting"])
        #expect(alone.transcript.output == "Skipped mirroring: it needs at least two displays.")
        #expect(alone.message == "Error: Nothing in “Presenting” applies to the displays connected now.")
    }
}

@Suite struct PresetEditCommandTests {
    @Test func renamesAndDeletes() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        try await harness.run(["preset", "save", "Gaming"])
        #expect(try await harness.run(["preset", "rename", "coding", "Focus"]).output == "Renamed “Coding” to “Focus”.")
        #expect(try await harness.run(["preset", "rename", "focus", "FOCUS"]).output == "Renamed “Focus” to “FOCUS”.")
        #expect(try await harness.run(["preset", "rename", "FOCUS", "FOCUS"]).output == "“FOCUS” already has that name.")
        let taken = await harness.execute(["preset", "rename", "FOCUS", "gaming"])
        #expect(taken.message == "Error: There is already a preset named “Gaming”.")
        #expect(taken.code == 1)
        #expect(try await harness.run(["preset", "delete", "GAMING"]).output == "Deleted “Gaming”.")
        #expect(try harness.store.load().presets.map(\.name) == ["FOCUS"])
        #expect(await harness.execute(["preset", "delete", "Gaming"]).message
            == "Error: There is no preset named “Gaming”. List them with `resolute preset list`.")
    }
}

/// Every key is always present, null when there is no value, as docs/json.md promises.
@Suite struct PresetJSONTests {
    let settingKeys: Set<String> = [
        "name", "vendorID", "productID", "serialNumber", "isBuiltin", "width", "height", "pixelWidth", "pixelHeight", "refreshRate",
    ]

    func json(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    @Test func givesEveryPresetKey() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        let saved = try #require(try json(try await harness.run(["preset", "save", "Coding", "--json"]).output) as? [String: Any])
        let keys: Set<String> = ["id", "name", "summary", "shortcut", "mirroring", "mirroringStatus", "isActive", "displays"]
        #expect(Set(saved.keys) == keys)
        #expect(saved["shortcut"] is NSNull)
        #expect(saved["mirroring"] as? Bool == false)
        #expect(saved["mirroringStatus"] as? String == "inUse")
        #expect(saved["isActive"] as? Bool == true)

        let shown = try #require(try json(try await harness.with([Sample.builtIn]).run(["preset", "show", "Coding", "--json"]).output)
            as? [String: Any])
        #expect(Set(shown.keys) == keys)
        #expect(shown["isActive"] as? Bool == false)
        let displays = try #require(shown["displays"] as? [[String: Any]])
        let displayKeys = settingKeys.union(["summary", "connectedDisplay", "connectedDisplayID", "currentMode", "mode", "status", "reason"])
        #expect(displays.allSatisfy { Set($0.keys) == displayKeys })
        #expect(displays[0]["status"] as? String == "inUse")
        #expect(displays[0]["reason"] is NSNull)
        #expect(displays[0]["vendorID"] as? String == "610")
        #expect((displays[0]["mode"] as? [String: Any])?["modeID"] as? Int == 54)
        #expect(displays[1]["status"] as? String == "notConnected")
        #expect(displays[1]["reason"] as? String == "it is not connected")
        for key in ["connectedDisplay", "connectedDisplayID", "currentMode", "mode"] {
            #expect(displays[1][key] is NSNull, "\(key)")
        }
        #expect(displays[1]["summary"] as? String == "DELL P2419H 1920 × 1080 at 60 Hz")

        let listed = try #require(try json(try await harness.run(["preset", "list", "--json"]).output) as? [[String: Any]])
        #expect(listed.map { Set($0.keys) } == [keys])
    }

    @Test func givesEveryResultKey() async throws {
        let harness = PresetHarness()
        defer { harness.remove() }
        try await harness.run(["preset", "save", "Coding"])
        let laptop = harness.with([Sample.builtIn])
        try laptop.displays.apply(modeID: 42, to: 1, scope: .permanent)
        let result = try #require(try json(try await laptop.run(["preset", "apply", "Coding", "--json"]).output) as? [String: Any])
        #expect(Set(result.keys) == ["id", "name", "succeeded", "changed", "mirroring", "mirroringResult", "mirroringReason", "displays"])
        #expect(result["succeeded"] as? Bool == true)
        #expect(result["changed"] as? Bool == true)
        #expect(result["mirroringResult"] as? String == "alreadyInUse")
        #expect(result["mirroringReason"] is NSNull)
        let displays = try #require(result["displays"] as? [[String: Any]])
        let displayKeys = settingKeys.union(["summary", "connectedDisplay", "connectedDisplayID", "result", "reason", "previousMode", "mode"])
        #expect(displays.allSatisfy { Set($0.keys) == displayKeys })
        #expect(displays.map { $0["result"] as? String } == ["switched", "notConnected"])
        #expect((displays[0]["previousMode"] as? [String: Any])?["modeID"] as? Int == 42)
        #expect((displays[0]["mode"] as? [String: Any])?["modeID"] as? Int == 54)
        #expect(displays[1]["previousMode"] is NSNull)
        #expect(displays[1]["reason"] as? String == "it is not connected")

        let preview = try #require(try json(try await laptop.run(["preset", "apply", "Coding", "--json", "--dry-run"]).output)
            as? [String: Any])
        #expect(preview["isActive"] as? Bool == false)
    }
}
