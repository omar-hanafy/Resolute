import CoreGraphics
import Foundation
import Testing
@testable import ResoluteKit

/// Displays for preset tests: several at once, with mode switches and mirroring changes
/// logged in the order they came and reflected in later snapshots, like the real system.
final class PresetDisplays: DisplayControlling, @unchecked Sendable {
    enum Event: Equatable {
        case mode(CGDirectDisplayID, Int32, ConfigurationScope)
        case mirroring(Bool)
    }

    private let lock = NSLock()
    private var list: [Display]
    private var log: [Event] = []
    private let refused: Set<Int32>
    private let ignored: Set<Int32>
    private let dropping: Set<Int32>

    /// `refusing` modes fail as CoreGraphics fails; `ignoring` modes report success but
    /// leave the display as it was; `dropping` modes make the display go away, as one that
    /// can't show a mode may.
    init(_ displays: [Display], refusing: Set<Int32> = [], ignoring: Set<Int32> = [], dropping: Set<Int32> = []) {
        list = displays
        refused = refusing
        ignored = ignoring
        self.dropping = dropping
    }

    var events: [Event] { lock.withLock { log } }

    func displays() -> [Display] { lock.withLock { list } }

    func currentModeID(of displayID: CGDirectDisplayID) -> Int32? {
        lock.withLock { list.first { $0.id == displayID }?.currentModeID }
    }

    func apply(modeID: Int32, to displayID: CGDirectDisplayID, scope: ConfigurationScope) throws {
        try lock.withLock {
            guard !refused.contains(modeID) else {
                throw ResoluteError.coreGraphics(code: 1001, operation: "select the display mode")
            }
            guard let index = list.firstIndex(where: { $0.id == displayID }),
                  list[index].modes.contains(where: { $0.modeID == modeID })
            else { throw ResoluteError.modeNotFound("mode \(modeID)", suggestions: []) }
            log.append(.mode(displayID, modeID, scope))
            if dropping.contains(modeID) {
                list.remove(at: index)
            } else if !ignored.contains(modeID) {
                list[index].currentModeID = modeID
            }
        }
    }

    func setMirroring(_ enabled: Bool) throws {
        try lock.withLock {
            guard list.count > 1 else { throw ResoluteError.mirroringNeedsTwoDisplays }
            log.append(.mirroring(enabled))
            for index in list.indices { list[index].isInMirrorSet = enabled }
        }
    }
}

enum PresetSample {
    static func mode(
        _ id: Int32, _ width: Int, _ height: Int, scale: Int = 2, hz: Double = 60, bits: Int = 10,
        flags: UInt32 = 0x3, origin: DisplayMode.Origin = .system
    ) -> DisplayMode {
        DisplayMode(
            modeID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale,
            refreshRate: hz, bitsPerSample: bits, ioFlags: flags, origin: origin
        )
    }

    /// Like the panel of a 16-inch MacBook Pro, at 1728 × 1117 HiDPI and 120 Hz, with an
    /// 8-bit twin of its default mode and one hidden mode.
    static func builtIn(id: CGDirectDisplayID = 1, current: Int32 = 54) -> Display {
        Display(
            id: id, name: "Built-in Retina Display", vendorID: 0x610, productID: 0xA050,
            isBuiltin: true, isMain: true, currentModeID: current,
            modes: [
                mode(54, 1728, 1117, hz: 120, flags: 0x0200_0007), mode(56, 1728, 1117, hz: 120, bits: 8),
                mode(55, 1728, 1117, hz: 60),
                mode(42, 1496, 967, hz: 120), mode(43, 1496, 967, hz: 60),
                mode(126, 3456, 2234, scale: 1, hz: 120, flags: 0x0200_0003), mode(127, 3456, 2234, scale: 1, hz: 60),
                mode(99, 1800, 1169, hz: 120, flags: 0x1, origin: .hidden),
            ],
            privateModes: .trusted
        )
    }

    /// Like a 27-inch 4K monitor: 2560 × 1440 HiDPI at 60 and 50 Hz, 1920 × 1080 HiDPI at
    /// 59.94 and 30 Hz, 1× modes, and two hidden modes.
    static func dell(
        id: CGDirectDisplayID = 2, serial: UInt32 = 0x4C35_3031, name: String = "DELL U2723QE", current: Int32 = 10
    ) -> Display {
        Display(
            id: id, name: name, vendorID: 0x10AC, productID: 0x42A8, serialNumber: serial, currentModeID: current,
            modes: [
                mode(10, 2560, 1440, hz: 60), mode(11, 2560, 1440, hz: 50),
                mode(12, 1920, 1080, hz: 59.94), mode(13, 1920, 1080, hz: 30),
                mode(20, 3840, 2160, scale: 1, hz: 60, flags: 0x0200_0007), mode(21, 2560, 1440, scale: 1, hz: 60),
                mode(90, 2560, 1440, hz: 75, flags: 0x1, origin: .hidden),
                mode(91, 3008, 1692, hz: 60, flags: 0x1, origin: .hidden),
            ],
            privateModes: .trusted
        )
    }

    static func setting(
        _ display: Display, _ size: (Int, Int)? = nil, pixels: (Int, Int)? = nil, hz: Double? = nil
    ) -> DisplaySetting {
        DisplaySetting(
            display: DisplayReference(display),
            size: size.map { DisplaySetting.Size(width: $0.0, height: $0.1) },
            pixelSize: pixels.map { DisplaySetting.Size(width: $0.0, height: $0.1) },
            refreshRate: hz
        )
    }

    /// A store in a fresh temporary folder.
    static func store() throws -> PresetStore {
        PresetStore(file: try makeTemporaryDirectory().appending(path: "Resolute/presets.json"))
    }
}

// MARK: - Model and summaries

@Suite struct PresetSummaryTests {
    /// The three cards on the Presets page in Figma (37:2289).
    @Test func readsLikeTheCardsInTheDesign() {
        let builtIn = PresetSample.builtIn(), dell = PresetSample.dell()
        let coding = Preset(name: "Coding", displays: [
            PresetSample.setting(builtIn, (1496, 967)), PresetSample.setting(dell, (2560, 1440), hz: 60),
        ])
        #expect(coding.summary == "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz")
        let presenting = Preset(name: "Presenting", displays: [
            PresetSample.setting(builtIn, (1920, 1080), hz: 60), PresetSample.setting(dell, (1920, 1080), hz: 60),
        ], mirroring: true)
        #expect(presenting.summary == "Mirroring on · 1920 × 1080 at 60 Hz")
        let gaming = Preset(name: "Gaming", displays: [
            PresetSample.setting(dell, (1920, 1080), hz: 60), PresetSample.setting(builtIn, hz: 120),
        ])
        #expect(gaming.summary == "DELL U2723QE 1920 × 1080 at 60 Hz · Built-in 120 Hz")
        #expect(coding.spokenSummary == "Built-in 1496 by 967, DELL U2723QE 2560 by 1440 at 60 Hz")
    }

    @Test func namesEachMirroredDisplayWhenTheirModesDiffer() {
        let preset = Preset(name: "Mixed", displays: [
            PresetSample.setting(PresetSample.builtIn(), (1496, 967), hz: 120),
            PresetSample.setting(PresetSample.dell(), (1920, 1080), hz: 60),
        ], mirroring: true)
        #expect(preset.summary == "Mirroring on · Built-in 1496 × 967 at 120 Hz · DELL U2723QE 1920 × 1080 at 60 Hz")
        #expect(Preset(name: "Off", displays: [], mirroring: false).summary == "Mirroring off")
    }

    @Test func showsShortcutsTheWayMenusDo() throws {
        let shortcut = try #require(KeyShortcut(key: "1", modifiers: [.option, .control]))
        #expect(shortcut.displayText == "⌃⌥1")
        #expect(shortcut.spokenText == "Control-Option-1")
        #expect(KeyShortcut(key: "K", modifiers: [.command, .shift, .option, .control])?.displayText == "⌃⌥⇧⌘K")
        #expect(KeyShortcut(key: "F5", modifiers: [])?.displayText == "F5")
        #expect(KeyShortcut(key: "space", modifiers: [.control])?.displayText == "⌃Space")
        #expect(KeyShortcut(key: "left", modifiers: [.option])?.spokenText == "Option-Left Arrow")
        #expect(KeyShortcut(key: "A", modifiers: [.control])?.key == "a")
        for key in ["", "ab", " ", "\t", "\u{7}", "f21", "Ctrl"] {
            #expect(KeyShortcut(key: key, modifiers: [.control]) == nil, "\(key.debugDescription)")
        }
    }
}

// MARK: - Store

@Suite struct PresetStoreTests {
    @Test func startsEmptyWithoutAFile() throws {
        let store = try PresetSample.store()
        #expect(try store.load() == PresetLibrary())
        #expect(!FileManager.default.fileExists(atPath: store.file.path(percentEncoded: false)))
    }

    @Test func keepsEveryPartOfAPresetThroughTheFile() throws {
        let store = try PresetSample.store()
        let builtIn = PresetSample.builtIn(), dell = PresetSample.dell()
        let shortcut = try #require(KeyShortcut(key: "1", modifiers: [.control, .option]))
        let presets = [
            Preset(name: "Coding", displays: [
                PresetSample.setting(builtIn, (1496, 967), pixels: (2992, 1934), hz: 120),
                PresetSample.setting(dell, (2560, 1440), hz: 59.94),
            ], mirroring: false, shortcut: shortcut),
            Preset(name: "Presenting", displays: [PresetSample.setting(builtIn, hz: 60)], mirroring: true),
            Preset(name: "Mirror Only", displays: [], mirroring: true),
        ]
        try store.update { library in
            for preset in presets { try library.add(preset) }
        }
        #expect(try store.load().presets == presets)
    }

    /// Every key is written, null when the preset leaves it open, and IDs are hex strings
    /// as `resolute displays --json` prints them.
    @Test func writesEveryKey() throws {
        let store = try PresetSample.store()
        let preset = Preset(name: "Refresh", displays: [PresetSample.setting(PresetSample.dell(), hz: 50)])
        try store.update { try $0.add(preset) }
        let file = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any])
        #expect(file["version"] as? Int == 1)
        let saved = try #require((file["presets"] as? [[String: Any]])?.first)
        #expect(Set(saved.keys) == ["id", "name", "displays", "mirroring", "shortcut"])
        #expect(saved["mirroring"] is NSNull)
        #expect(saved["shortcut"] is NSNull)
        let display = try #require((saved["displays"] as? [[String: Any]])?.first)
        #expect(Set(display.keys) == [
            "name", "vendorID", "productID", "serialNumber", "isBuiltin", "width", "height", "pixelWidth", "pixelHeight", "refreshRate",
        ])
        #expect(display["vendorID"] as? String == "10ac")
        #expect(display["width"] is NSNull)
        #expect(display["refreshRate"] as? Double == 50)
    }

    /// A preset Resolute can't read is left out, said why, and kept in its place when the
    /// file is written back, so a slip in one never costs the others or itself.
    @Test func skipsAnUnreadablePresetWithoutLosingIt() throws {
        let store = try PresetSample.store()
        try FileManager.default.createDirectory(at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let broken = #"{"id": "8F7C3A2E-9B71-4C55-9D3B-2E1F0A4B6C7D", "name": "Broken", "displays": [{"name": "DELL", "width": "wide", "height": 1440}]}"#
        try Data("""
            {"version": 1, "presets": [
              {"id": "11111111-1111-1111-1111-111111111111", "name": "First", "displays": [{"isBuiltin": true, "refreshRate": 60}]},
              \(broken),
              {"id": "22222222-2222-2222-2222-222222222222", "name": "Last", "mirroring": true}
            ]}
            """.utf8).write(to: store.file)

        let library = try store.load()
        #expect(library.presets.map(\.name) == ["First", "Last"])
        #expect(library.problems == [.init(index: 1, name: "Broken", reason: "“displays.0.width” has the wrong type")])

        try store.update { try $0.add(Preset(name: "New", displays: [], mirroring: false)) }
        let entries = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: store.file)) as? [String: Any]
        )["presets"] as? [[String: Any]]
        #expect(entries?.map { $0["name"] as? String } == ["First", "Broken", "Last", "New"])
        let kept = try #require(entries?[1])
        let original = try #require(try JSONSerialization.jsonObject(with: Data(broken.utf8)) as? NSDictionary)
        #expect(NSDictionary(dictionary: kept) == original)
        #expect(try store.load().problems.map(\.name) == ["Broken"])
    }

    @Test(arguments: [
        (#"{"id": "not-a-uuid", "name": "A", "mirroring": true}"#, "its id, “not-a-uuid”, is not a UUID"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "  ", "mirroring": true}"#, "it has no name"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A\nB", "mirroring": true}"#,
         "its name has a line break, a tab or another control character"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A", "displays": [{"name": "X", "serialNumber": -1, "refreshRate": 60}]}"#,
         "the preset has a value Resolute can’t read"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A", "displays": [{"name": "X", "width": 0, "height": 10}]}"#,
         "0 × 10 is not a size a display has"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A"}"#, "it sets no display and leaves mirroring as it is"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A", "displays": [{"name": "X"}]}"#,
         "it sets neither a resolution nor a refresh rate"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A", "displays": [{"refreshRate": 60}]}"#,
         "a display that is not built in needs its name"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A", "displays": [{"name": "X", "pixelWidth": 10, "pixelHeight": 10, "refreshRate": 60}]}"#,
         "a pixel size needs the size in points too"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A", "displays": [{"name": "X", "vendorID": "zz", "refreshRate": 60}]}"#,
         "“vendorID” is not a hexadecimal ID: “zz”"),
        (#"{"id": "11111111-1111-1111-1111-111111111111", "name": "A", "mirroring": true, "shortcut": {"key": "1", "modifiers": ["hyper"]}}"#,
         "the shortcut’s modifiers are control, option, shift and command, not hyper"),
        (#""just a string""#, "the preset has the wrong type"),
    ])
    func saysWhyAnEntryCantBeRead(entry: String, reason: String) throws {
        let library = try PresetLibrary(data: Data(#"{"version": 1, "presets": [\#(entry)]}"#.utf8), path: "presets.json")
        #expect(library.presets.isEmpty)
        #expect(library.problems.map(\.reason) == [reason])
    }

    /// Hand-written settings may give IDs as numbers or hex, and leave out what they don't need.
    @Test func readsSettingsWrittenByHand() throws {
        let library = try PresetLibrary(data: Data("""
            {"presets": [{"id": "11111111-1111-1111-1111-111111111111", "name": " Desk ", "displays": [
              {"name": "DELL U2723QE", "vendorID": 4268, "productID": "0x42a8", "width": 2560, "height": 1440},
              {"isBuiltin": true, "refreshRate": 120}
            ]}]}
            """.utf8), path: "presets.json")
        let preset = try #require(library.presets.first)
        #expect(preset.name == "Desk")
        #expect(preset.displays[0].display.vendorID == 0x10AC)
        #expect(preset.displays[0].display.productID == 0x42A8)
        #expect(preset.displays[0].pixelSize == nil)
        #expect(preset.displays[1].display.isBuiltin)
        #expect(preset.summary == "DELL U2723QE 2560 × 1440 · Built-in 120 Hz")
    }

    @Test func leavesAFileThatIsNotPresetsAlone() throws {
        let store = try PresetSample.store()
        try FileManager.default.createDirectory(at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        for contents in ["{not json", "[1, 2]", #"{"version": 0, "presets": []}"#] {
            try Data(contents.utf8).write(to: store.file)
            #expect(throws: PresetError.self) { try store.load() }
            #expect(throws: PresetError.self) { try store.update { try $0.add(Preset(name: "A", displays: [], mirroring: true)) } }
            #expect(try String(contentsOf: store.file, encoding: .utf8) == contents)
        }
        try Data("{not json".utf8).write(to: store.file)
        do {
            _ = try store.load()
            Issue.record("A file that is not JSON was read")
        } catch {
            #expect(error.localizedDescription == "Could not read the presets in \(store.file.path(percentEncoded: false)): "
                + "it is not valid JSON. Fix the file, or move it away to start a new one.")
        }
        try Data(" \n".utf8).write(to: store.file)
        #expect(try store.load() == PresetLibrary())
    }

    /// A newer file is read as well as it can be, but never overwritten with the old format.
    @Test func readsButNeverWritesANewerFormat() throws {
        let store = try PresetSample.store()
        try FileManager.default.createDirectory(at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let contents = #"{"version": 2, "presets": [{"id": "11111111-1111-1111-1111-111111111111", "name": "Desk", "mirroring": true}]}"#
        try Data(contents.utf8).write(to: store.file)
        #expect(try store.load().presets.map(\.name) == ["Desk"])
        let path = store.file.path(percentEncoded: false)
        #expect(throws: PresetError.newerFile(path: path, version: 2)) {
            try store.update { try $0.delete(named: "Desk") }
        }
        #expect(try String(contentsOf: store.file, encoding: .utf8) == contents)
    }

    @Test func readsTwinsOnlyOnce() throws {
        let library = try PresetLibrary(data: Data("""
            {"presets": [
              {"id": "11111111-1111-1111-1111-111111111111", "name": "Desk", "mirroring": true},
              {"id": "22222222-2222-2222-2222-222222222222", "name": "DESK", "mirroring": false},
              {"id": "11111111-1111-1111-1111-111111111111", "name": "Other", "mirroring": false}
            ]}
            """.utf8), path: "presets.json")
        #expect(library.presets.map(\.name) == ["Desk"])
        #expect(library.problems.map(\.reason) == ["“Desk” already has that name", "another preset has the same id"])
    }

    /// The app and the command line may save at the same moment; the lock makes each
    /// read-change-write whole, so no save is lost.
    @Test func keepsEverySaveWhenManyWritersOverlap() throws {
        let file = try PresetSample.store().file
        let failures = PresetWriteFailures()
        DispatchQueue.concurrentPerform(iterations: 24) { number in
            do {
                try PresetStore(file: file).update { library in
                    try library.add(Preset(name: "Preset \(number)", displays: [], mirroring: number.isMultiple(of: 2)))
                }
            } catch {
                failures.record(error)
            }
        }
        #expect(failures.all.isEmpty)
        #expect(Set(try PresetStore(file: file).load().presets.map(\.name)) == Set((0..<24).map { "Preset \($0)" }))
    }

    @Test func givesUpOnALockHeldTooLong() throws {
        let store = try PresetSample.store()
        let holding = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? store.update { _ in
                holding.signal()
                release.wait()
            }
            done.signal()
        }
        holding.wait()
        var impatient = store
        impatient.lockTimeout = .milliseconds(50)
        #expect(throws: PresetError.busy(path: store.lockFile.path(percentEncoded: false))) {
            try impatient.update { try $0.add(Preset(name: "A", displays: [], mirroring: true)) }
        }
        release.signal()
        done.wait()
        try impatient.update { try $0.add(Preset(name: "A", displays: [], mirroring: true)) }
        #expect(try store.load().presets.map(\.name) == ["A"])
    }

    @Test func writesNothingWhenNothingChanged() throws {
        let store = try PresetSample.store()
        try store.update { _ in }
        #expect(!FileManager.default.fileExists(atPath: store.file.path(percentEncoded: false)))
        #expect(throws: PresetError.self) { try store.update { try $0.delete(named: "Nothing") } }
        #expect(!FileManager.default.fileExists(atPath: store.file.path(percentEncoded: false)))
    }
}

/// Errors from concurrent work, collected under a lock.
final class PresetWriteFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [any Error] = []

    func record(_ error: any Error) { lock.withLock { errors.append(error) } }
    var all: [any Error] { lock.withLock { errors } }
}

// MARK: - Library

@Suite struct PresetLibraryTests {
    let capture = PresetCapture(displays: [PresetSample.builtIn(), PresetSample.dell()])

    @Test func ignoresCaseInNames() throws {
        var library = PresetLibrary()
        _ = try library.save(capture, named: "Coding", replacing: false)
        #expect(throws: PresetError.nameTaken("Coding")) { try library.save(capture, named: "CODING", replacing: false) }
        #expect(throws: PresetError.nameTaken("Coding")) { try library.add(Preset(name: " coding ", displays: [], mirroring: true)) }
        #expect(try library.find(named: "cOdInG").name == "Coding")
        #expect(try library.rename("coding", to: "CODING").name == "CODING")
        try library.add(Preset(name: "Gaming", displays: [], mirroring: false))
        #expect(throws: PresetError.nameTaken("Gaming")) { try library.rename("CODING", to: "gaming") }
    }

    @Test(arguments: [
        ("", PresetError.NameProblem.empty), ("   ", .empty), ("Line\nbreak", .controlCharacters), ("Tab\there", .controlCharacters),
        (String(repeating: "x", count: PresetName.maximumLength + 1), .tooLong),
    ])
    func refusesNamesThatCantBeShown(name: String, problem: PresetError.NameProblem) {
        var library = PresetLibrary()
        do {
            _ = try library.save(capture, named: name, replacing: false)
            Issue.record("Saved a preset named \(name.debugDescription)")
        } catch PresetError.invalidName(_, let found) {
            #expect(found == problem)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(library.presets.isEmpty)
    }

    @Test func suggestsTheNameThatWasMeant() throws {
        var library = PresetLibrary()
        for name in ["Coding", "Morning Desk", "Gaming", "TV"] {
            try library.add(Preset(name: name, displays: [], mirroring: true))
        }
        #expect(throws: PresetError.notFound("Codng", suggestions: ["Coding"])) { try library.find(named: "Codng") }
        #expect(throws: PresetError.notFound("desk", suggestions: ["Morning Desk"])) { try library.find(named: "desk") }
        #expect(throws: PresetError.notFound("cod", suggestions: ["Coding"])) { try library.find(named: "cod") }
        #expect(throws: PresetError.notFound("Gamin", suggestions: ["Gaming"])) { try library.find(named: "Gamin") }
        #expect(throws: PresetError.notFound("Office", suggestions: [])) { try library.find(named: "Office") }
        #expect(throws: PresetError.notFound("XY", suggestions: [])) { try library.find(named: "XY") }
        #expect(PresetError.notFound("Codng", suggestions: ["Coding", "Code"]).localizedDescription
            == "There is no preset named “Codng”. Did you mean “Coding” or “Code”?")
    }

    /// Saving appends; replacing, renaming and changing a shortcut keep a preset's place.
    @Test func keepsTheOrderPresetsWereSavedIn() throws {
        var library = PresetLibrary()
        let shortcut = try #require(KeyShortcut(key: "2", modifiers: [.control, .option]))
        for name in ["A", "B", "C"] { _ = try library.save(capture, named: name, replacing: false) }
        let before = try library.find(named: "B")
        try library.setShortcut(shortcut, forPresetWithID: before.id)

        let other = PresetCapture(displays: [PresetSample.builtIn(current: 42)])
        let (replaced, didReplace) = try library.save(other, named: "b", replacing: true)
        #expect(didReplace)
        #expect(replaced.id == before.id)
        #expect(replaced.name == "B")
        #expect(replaced.shortcut == shortcut)
        #expect(replaced.displays == other.displays)
        try library.rename("A", to: "Z")
        #expect(library.presets.map(\.name) == ["Z", "B", "C"])
        try library.delete(named: "b")
        _ = try library.save(capture, named: "D", replacing: false)
        #expect(library.presets.map(\.name) == ["Z", "C", "D"])
    }

    @Test func givesEachShortcutToOnePreset() throws {
        var library = PresetLibrary()
        let shortcut = try #require(KeyShortcut(key: "1", modifiers: [.control, .option]))
        let first = try library.add(Preset(name: "First", displays: [], mirroring: true, shortcut: shortcut))
        let second = try library.add(Preset(name: "Second", displays: [], mirroring: false))
        #expect(throws: PresetError.shortcutTaken(shortcut, by: "First")) {
            try library.setShortcut(shortcut, forPresetWithID: second.id)
        }
        try library.setShortcut(nil, forPresetWithID: first.id)
        #expect(try library.setShortcut(shortcut, forPresetWithID: second.id).shortcut == shortcut)
        #expect(library.delete(id: first.id)?.name == "First")
        #expect(library.delete(id: first.id) == nil)
        #expect(throws: PresetError.noLongerExists(first.id)) {
            try library.setShortcut(nil, forPresetWithID: first.id)
        }
    }

    @Test func refusesToSaveNothing() {
        var library = PresetLibrary()
        let hidden = PresetCapture(displays: [PresetSample.dell(current: 90)])
        #expect(throws: PresetError.nothingToSave(reasons: [
            "DELL U2723QE uses a hidden mode, which presets don’t switch to, so it was left out.",
        ])) {
            try library.save(hidden, named: "Hidden", replacing: false)
        }
        #expect(throws: PresetError.nothingToSave(reasons: [])) { try library.add(Preset(name: "Empty", displays: [])) }
    }

    @Test func picksAFreeName() throws {
        var library = PresetLibrary()
        #expect(library.availableName("New Preset") == "New Preset")
        try library.add(Preset(name: "New Preset", displays: [], mirroring: true))
        try library.add(Preset(name: "new preset 2", displays: [], mirroring: true))
        #expect(library.availableName("New Preset") == "New Preset 3")
    }

    /// A taken name as long as a name may be is shortened to make room for its number, so
    /// the numbered name is a valid one.
    @Test func picksAFreeNameThatFits() throws {
        var library = PresetLibrary()
        let long = String(repeating: "a", count: PresetName.maximumLength)
        try library.add(Preset(name: long, displays: [], mirroring: true))
        let free = library.availableName(long)
        #expect(free == String(repeating: "a", count: PresetName.maximumLength - 2) + " 2")
        #expect(try PresetName.validated(free) == free)
        try library.add(Preset(name: free, displays: [], mirroring: true))
    }

    @Test func givesAnImportedTwinANewID() throws {
        var library = PresetLibrary()
        let original = try library.add(Preset(name: "Desk", displays: [], mirroring: true))
        let imported = try library.add(Preset(id: original.id, name: "Desk 2", displays: [], mirroring: true))
        #expect(imported.id != original.id)
    }

    /// What one Mac exports, another imports: the same presets, by the file's own rules.
    @Test func exportsWhatImportReads() throws {
        let shortcut = try #require(KeyShortcut(key: "f5", modifiers: [.command]))
        let exported = PresetLibrary(presets: [
            Preset(name: "Coding", displays: PresetCapture(displays: [PresetSample.builtIn(), PresetSample.dell()]).displays,
                   mirroring: false, shortcut: shortcut),
            Preset(name: "Presenting", displays: [], mirroring: true),
        ])
        let imported = try PresetLibrary(data: try exported.data(), path: "Exported.json")
        #expect(imported == exported)
        #expect(imported.presets[0].shortcut?.displayText == "⌘F5")
    }
}

// MARK: - Capture

@Suite struct PresetCaptureTests {
    @Test func remembersTheModeOfEveryDisplay() {
        var dell = PresetSample.dell()
        dell.isMain = true
        var builtIn = PresetSample.builtIn(current: 42)
        builtIn.isMain = false
        let capture = PresetCapture(displays: [builtIn, dell])
        // The main display comes first.
        #expect(capture.displays == [
            DisplaySetting(
                display: DisplayReference(vendorID: 0x10AC, productID: 0x42A8, serialNumber: 0x4C35_3031, name: "DELL U2723QE"),
                size: .init(width: 2560, height: 1440), pixelSize: .init(width: 5120, height: 2880), refreshRate: 60
            ),
            DisplaySetting(
                display: DisplayReference(vendorID: 0x610, productID: 0xA050, isBuiltin: true, name: "Built-in Retina Display"),
                size: .init(width: 1496, height: 967), pixelSize: .init(width: 2992, height: 1934), refreshRate: 120
            ),
        ])
        #expect(capture.mirroring == false)
        #expect(capture.leftOut.isEmpty)
        #expect(Preset(name: "Now", displays: capture.displays, mirroring: capture.mirroring).summary
            == "DELL U2723QE 2560 × 1440 at 60 Hz · Built-in 1496 × 967 at 120 Hz")
    }

    @Test func leavesOutWhatAPresetCantSwitchTo() {
        var unknown = PresetSample.dell(id: 3, serial: 7, name: "LG UltraFine 5K")
        unknown.currentModeID = nil
        let capture = PresetCapture(displays: [PresetSample.builtIn(), PresetSample.dell(current: 90), unknown])
        #expect(capture.displays.map(\.display.name) == ["Built-in Retina Display"])
        #expect(capture.leftOut.map(\.message) == [
            "DELL U2723QE uses a hidden mode, which presets don’t switch to, so it was left out.",
            "The current mode of LG UltraFine 5K is unknown, so it was left out.",
        ])
    }

    @Test func remembersMirroringOnlyWithTwoDisplays() {
        #expect(PresetCapture(displays: [PresetSample.builtIn()]).mirroring == nil)
        var builtIn = PresetSample.builtIn(), dell = PresetSample.dell()
        builtIn.isInMirrorSet = true
        dell.isInMirrorSet = true
        #expect(PresetCapture(displays: [builtIn, dell]).mirroring == true)
    }

    @Test func keepsNoRateADisplayDoesNotReport() {
        var display = PresetSample.dell()
        display.modes[0].refreshRate = 0
        #expect(PresetCapture(displays: [display]).displays.first?.refreshRate == nil)
    }
}

// MARK: - Matching and planning

@Suite struct PresetPlanTests {
    func plan(_ settings: [DisplaySetting], mirroring: Bool? = nil, on displays: [Display]) -> PresetPlan {
        Preset(name: "Test", displays: settings, mirroring: mirroring).plan(for: displays)
    }

    @Test func findsADisplayWhoseIDChanged() {
        let saved = PresetSample.setting(PresetSample.dell(id: 2), (2560, 1440), pixels: (5120, 2880), hz: 50)
        let step = plan([saved], on: [PresetSample.builtIn(), PresetSample.dell(id: 731)]).steps[0]
        #expect(step.display?.id == 731)
        #expect(step.mode?.modeID == 11)
        #expect(step.status == .switches)
    }

    /// Identical monitors are told apart by serial number, whatever order they come in.
    @Test func tellsIdenticalMonitorsApartBySerialNumber() {
        let left = PresetSample.dell(id: 2, serial: 100, name: "DELL U2723QE (1)")
        let right = PresetSample.dell(id: 3, serial: 200, name: "DELL U2723QE (2)")
        let settings = [
            PresetSample.setting(left, (2560, 1440), pixels: (5120, 2880), hz: 60),
            PresetSample.setting(right, (1920, 1080), pixels: (3840, 2160), hz: 59.94),
        ]
        var swappedRight = right, swappedLeft = left
        swappedRight.id = 5
        swappedLeft.id = 6
        let steps = plan(settings, on: [swappedRight, swappedLeft]).steps
        #expect(steps.map(\.display?.id) == [6, 5])
    }

    /// Without serial numbers, identical monitors are told apart by the names
    /// `resolute displays` gives them.
    @Test func tellsIdenticalMonitorsWithoutSerialsApartByName() {
        let first = PresetSample.dell(id: 2, serial: 0, name: "DELL U2723QE (1)")
        let second = PresetSample.dell(id: 3, serial: 0, name: "DELL U2723QE (2)")
        let settings = [PresetSample.setting(second, (2560, 1440), hz: 50), PresetSample.setting(first, (1920, 1080), hz: 30)]
        #expect(plan(settings, on: [first, second]).steps.map(\.display?.id) == [3, 2])
    }

    @Test func usesAnotherMonitorOfTheSameModel() {
        let saved = PresetSample.setting(PresetSample.dell(serial: 100), (2560, 1440), hz: 50)
        #expect(plan([saved], on: [PresetSample.dell(id: 9, serial: 999)]).steps[0].display?.id == 9)
    }

    /// A weaker match is tried only after every stronger one, so it never takes a display
    /// another setting names exactly.
    @Test func neverGivesAWeakMatchTheDisplayAStrongOneNames() {
        let exact = PresetSample.dell(id: 2, serial: 100)
        let sameModel = PresetSample.dell(id: 3, serial: 300, name: "Office Dell")
        let settings = [PresetSample.setting(sameModel, (1920, 1080)), PresetSample.setting(exact, (2560, 1440))]
        let steps = plan(settings, on: [PresetSample.dell(id: 8, serial: 100)]).steps
        #expect(steps[0].status == .skipped(.notConnected))
        #expect(steps[1].display?.id == 8)
    }

    @Test func findsTheBuiltInDisplayOfAnotherMac() {
        var other = PresetSample.builtIn()
        other.productID = 0xA033
        let saved = PresetSample.setting(PresetSample.builtIn(), (1496, 967), hz: 120)
        #expect(plan([saved], on: [PresetSample.dell(), other]).steps[0].display?.productID == 0xA033)
    }

    @Test func findsADisplayKnownOnlyByName() {
        let byName = DisplaySetting(display: DisplayReference(name: "dell u2723qe"), size: .init(width: 1920, height: 1080))
        let step = plan([byName], on: [PresetSample.builtIn(), PresetSample.dell()]).steps[0]
        #expect(step.display?.id == 2)
        #expect(step.mode?.modeID == 12)
    }

    @Test func skipsADisplayThatIsNotConnected() {
        let steps = plan([
            PresetSample.setting(PresetSample.builtIn(), (1496, 967), hz: 120), PresetSample.setting(PresetSample.dell(), (2560, 1440)),
        ], on: [PresetSample.builtIn()]).steps
        #expect(steps.map(\.status) == [.switches, .skipped(.notConnected)])
        #expect(PresetPlan.Problem.notConnected.reason(for: steps[1].setting) == "it is not connected")
        #expect(steps[1].displayName == "DELL U2723QE")
    }

    @Test func takesTheClosestRateWhenTheSavedOneIsGone() {
        let dell = PresetSample.dell()
        // 1920 × 1080 HiDPI comes at 59.94 and 30 Hz.
        #expect(plan([PresetSample.setting(dell, (1920, 1080), pixels: (3840, 2160), hz: 60)], on: [dell]).steps[0].mode?.modeID == 12)
        // Equally far from 60 and 50 Hz: the faster one.
        #expect(plan([PresetSample.setting(dell, (2560, 1440), pixels: (5120, 2880), hz: 55)], on: [dell]).steps[0].mode?.modeID == 10)
    }

    /// Presets switch only to modes macOS lists, even when a hidden one matches exactly.
    @Test func neverChoosesAHiddenMode() {
        let dell = PresetSample.dell(current: 11)
        let exactHidden = plan([PresetSample.setting(dell, (2560, 1440), pixels: (5120, 2880), hz: 75)], on: [dell]).steps[0]
        #expect(exactHidden.mode?.modeID == 10)
        #expect(exactHidden.mode?.origin == .system)
        let hiddenOnly = plan([PresetSample.setting(dell, (3008, 1692), hz: 60)], on: [dell]).steps[0]
        #expect(hiddenOnly.status == .skipped(.resolutionNotOffered))
        #expect(hiddenOnly.mode == nil)
        #expect(PresetPlan.Problem.resolutionNotOffered.reason(for: hiddenOnly.setting) == "it does not list 3008 × 1692")
    }

    @Test func keepsToTheSavedScale() {
        let dell = PresetSample.dell()
        let oneX = plan([PresetSample.setting(dell, (2560, 1440), pixels: (2560, 1440), hz: 60)], on: [dell]).steps[0]
        #expect(oneX.mode?.modeID == 21)
        let missing = plan([PresetSample.setting(dell, (1920, 1080), pixels: (1920, 1080), hz: 60)], on: [dell]).steps[0]
        #expect(missing.status == .skipped(.resolutionNotOffered))
        #expect(PresetPlan.Problem.resolutionNotOffered.reason(for: missing.setting) == "it does not list 1920 × 1080 at 1×")
        // Without a pixel size: the scale in use, else HiDPI.
        #expect(plan([PresetSample.setting(dell, (2560, 1440), hz: 60)], on: [dell]).steps[0].mode?.modeID == 10)
        #expect(plan([PresetSample.setting(dell, (2560, 1440), hz: 60)], on: [PresetSample.dell(current: 20)]).steps[0].mode?.modeID == 21)
    }

    @Test func keepsTheCurrentRateWhenTheSettingHasNone() {
        let builtIn = PresetSample.builtIn(current: 55)
        #expect(plan([PresetSample.setting(builtIn, (1496, 967), pixels: (2992, 1934))], on: [builtIn]).steps[0].mode?.modeID == 43)
    }

    @Test func changesOnlyTheRateForARateAlone() {
        let builtIn = PresetSample.builtIn(current: 42)
        let step = plan([PresetSample.setting(builtIn, hz: 60)], on: [builtIn]).steps[0]
        #expect(step.mode?.modeID == 43)
        let hidden = PresetSample.builtIn(current: 99)
        #expect(plan([PresetSample.setting(hidden, hz: 60)], on: [hidden]).steps[0].status == .skipped(.currentResolutionHidden))
        var unknown = PresetSample.builtIn()
        unknown.currentModeID = nil
        #expect(plan([PresetSample.setting(unknown, hz: 60)], on: [unknown]).steps[0].status == .skipped(.currentModeUnknown))
    }

    /// A mode that differs only in bit depth is the one asked for, so the display stays.
    @Test func leavesAnEquivalentModeInUse() {
        let builtIn = PresetSample.builtIn(current: 56)
        let step = plan([PresetSample.setting(builtIn, (1728, 1117), pixels: (3456, 2234), hz: 120)], on: [builtIn]).steps[0]
        #expect(step.status == .inUse)
        #expect(step.mode?.modeID == 56)
    }

    @Test func turnsMirroringOnlyWhenItDiffers() {
        let displays = [PresetSample.builtIn(), PresetSample.dell()]
        #expect(plan([], mirroring: true, on: displays).mirroring == .turns(true))
        #expect(plan([], mirroring: false, on: displays).mirroring == .inUse(false))
        #expect(plan([PresetSample.setting(displays[0], hz: 60)], on: displays).mirroring == .leftAlone)
        #expect(plan([], mirroring: true, on: [PresetSample.builtIn()]).mirroring == .notPossible)
    }
}

@Suite struct PresetActiveTests {
    @Test func isActiveWhileTheSetupMatches() {
        let displays = [PresetSample.builtIn(current: 42), PresetSample.dell()]
        let capture = PresetCapture(displays: displays)
        let preset = Preset(name: "Coding", displays: capture.displays, mirroring: capture.mirroring)
        #expect(preset.isActive(on: displays))
        // Another display that the preset does not name changes nothing.
        #expect(preset.isActive(on: displays + [PresetSample.dell(id: 7, serial: 7, name: "Projector")]))
        #expect(!preset.isActive(on: [PresetSample.builtIn(current: 54), PresetSample.dell()]))
        #expect(!preset.isActive(on: [PresetSample.builtIn(current: 42)]))
        var mirrored = displays
        for index in mirrored.indices { mirrored[index].isInMirrorSet = true }
        #expect(!preset.isActive(on: mirrored))
        #expect(Preset(name: "Any", displays: capture.displays).isActive(on: mirrored))
    }

    /// After applying a preset whose rate is gone, the closest rate counts as the preset's,
    /// so the badge still shows.
    @Test func countsTheClosestRateAsMatching() {
        let dell = PresetSample.dell(current: 12)
        #expect(Preset(name: "TV", displays: [PresetSample.setting(dell, (1920, 1080), pixels: (3840, 2160), hz: 60)])
            .isActive(on: [dell]))
    }

    @Test func isNeverActiveForMirroringItCantTurnOn() {
        #expect(!Preset(name: "Mirror", displays: [], mirroring: true).isActive(on: [PresetSample.builtIn()]))
        #expect(Preset(name: "Single", displays: [], mirroring: false).isActive(on: [PresetSample.builtIn()]))
    }
}

// MARK: - Applying

@Suite struct PresetApplierTests {
    @Test func switchesEveryDisplayToItsListedMode() throws {
        let service = PresetDisplays([PresetSample.builtIn(), PresetSample.dell()])
        let preset = Preset(name: "Coding", displays: [
            PresetSample.setting(PresetSample.builtIn(), (1496, 967), pixels: (2992, 1934), hz: 120),
            PresetSample.setting(PresetSample.dell(), (1920, 1080), pixels: (3840, 2160), hz: 60),
        ])
        let result = PresetApplier(service: service).apply(preset)
        #expect(service.events == [.mode(1, 42, .permanent), .mode(2, 12, .permanent)])
        #expect(result.displays.map(\.outcome) == [.switched, .switched])
        #expect(result.displays.map(\.previousMode?.modeID) == [54, 10])
        #expect(result.displays.map(\.mode?.modeID) == [42, 12])
        #expect(result.changedAnything)
        #expect(!result.hasFailures)
        #expect(preset.isActive(on: service.displays()))
    }

    @Test func leavesADisplayAlreadyInItsMode() {
        let service = PresetDisplays([PresetSample.builtIn(), PresetSample.dell()])
        let capture = PresetCapture(displays: service.displays())
        let result = PresetApplier(service: service).apply(Preset(name: "Now", displays: capture.displays, mirroring: capture.mirroring))
        #expect(service.events.isEmpty)
        #expect(result.displays.map(\.outcome) == [.alreadyInUse, .alreadyInUse])
        #expect(result.mirroring == .alreadyInUse(false))
        #expect(!result.changedAnything)
    }

    /// One display that can't switch doesn't stop the others, and says why.
    @Test func reportsAPartialFailure() {
        let service = PresetDisplays([PresetSample.builtIn(), PresetSample.dell()], refusing: [42])
        let result = PresetApplier(service: service).apply(Preset(name: "Coding", displays: [
            PresetSample.setting(PresetSample.builtIn(), (1496, 967), hz: 120),
            PresetSample.setting(PresetSample.dell(), (2560, 1440), hz: 50),
            PresetSample.setting(PresetSample.dell(id: 4, serial: 4, name: "LG UltraFine 5K"), (2560, 1440)),
        ]))
        #expect(service.events == [.mode(2, 11, .permanent)])
        #expect(result.displays.map(\.outcome) == [
            .failed("CoreGraphics could not select the display mode: illegal argument (1001)."), .switched, .skipped(.notConnected),
        ])
        #expect(result.hasFailures)
        #expect(result.changedAnything)
        #expect(!result.appliedNothing)
    }

    @Test func saysWhenNoDisplayCouldBeSet() {
        let service = PresetDisplays([PresetSample.builtIn()])
        let result = PresetApplier(service: service).apply(Preset(name: "Desk", displays: [
            PresetSample.setting(PresetSample.dell(), (2560, 1440), hz: 60),
        ]))
        #expect(result.appliedNothing)
        #expect(!result.changedAnything)
        #expect(service.events.isEmpty)
    }

    /// Mirroring already right is the whole of a mirroring-only preset, but not of one that
    /// names displays.
    @Test func countsMirroringAloneOnlyForAMirroringPreset() {
        let pair = [PresetSample.builtIn(), PresetSample.dell()]
        let apply = { (preset: Preset, displays: [Display]) in PresetApplier(service: PresetDisplays(displays)).apply(preset) }
        #expect(!apply(Preset(name: "Off", displays: [], mirroring: false), pair).appliedNothing)
        #expect(apply(Preset(name: "On", displays: [], mirroring: true), [PresetSample.builtIn()]).appliedNothing)
        let away = DisplaySetting(
            display: DisplayReference(vendorID: 0x1E6D, productID: 0x5B09, serialNumber: 5, name: "LG UltraFine 5K"),
            size: .init(width: 2560, height: 1440)
        )
        #expect(apply(Preset(name: "Desk", displays: [away], mirroring: false), [PresetSample.builtIn()]).appliedNothing)
        #expect(!apply(Preset(name: "Show", displays: [away], mirroring: true), pair).appliedNothing)
    }

    /// Mirroring changes before the modes, since it can change the modes a display offers.
    @Test func turnsMirroringFirst() {
        let service = PresetDisplays([PresetSample.builtIn(), PresetSample.dell()])
        let result = PresetApplier(service: service).apply(Preset(name: "Presenting", displays: [
            PresetSample.setting(PresetSample.dell(), (1920, 1080), hz: 60),
        ], mirroring: true))
        #expect(service.events == [.mirroring(true), .mode(2, 12, .permanent)])
        #expect(result.mirroring == .turned(true))
        #expect(service.displays().allSatisfy { $0.isInMirrorSet })
    }

    @Test func leavesMirroringItCantTurnOn() {
        let service = PresetDisplays([PresetSample.builtIn()])
        let result = PresetApplier(service: service).apply(Preset(name: "Presenting", displays: [
            PresetSample.setting(PresetSample.builtIn(), (1496, 967), hz: 120),
        ], mirroring: true))
        #expect(result.mirroring == .notPossible)
        #expect(service.events == [.mode(1, 42, .permanent)])
        #expect(!result.hasFailures)
    }

    @Test func doubtsASwitchTheDisplayDidNotShow() {
        let service = PresetDisplays([PresetSample.builtIn()], ignoring: [42])
        let result = PresetApplier(service: service).apply(Preset(name: "Coding", displays: [
            PresetSample.setting(PresetSample.builtIn(), (1496, 967), hz: 120),
        ]))
        #expect(result.displays.map(\.outcome) == [.showsOtherMode(PresetSample.builtIn().currentMode)])
        #expect(result.changedAnything)
    }

    @Test func saysWhenADisplayWentAwayAfterItsSwitch() {
        let service = PresetDisplays([PresetSample.builtIn(), PresetSample.dell()], dropping: [12])
        let result = PresetApplier(service: service).apply(Preset(name: "TV", displays: [
            PresetSample.setting(PresetSample.dell(), (1920, 1080), hz: 60),
        ]))
        #expect(result.displays.map(\.outcome) == [.wentAway])
        #expect(result.changedAnything)
        #expect(!result.hasFailures)
    }

    /// Whatever a preset holds, only modes macOS lists reach the display.
    @Test func neverSwitchesToAHiddenMode() {
        let service = PresetDisplays([PresetSample.builtIn(), PresetSample.dell(current: 11)])
        _ = PresetApplier(service: service).apply(Preset(name: "Hidden", displays: [
            PresetSample.setting(PresetSample.builtIn(), (1800, 1169), hz: 120),
            PresetSample.setting(PresetSample.dell(), (2560, 1440), pixels: (5120, 2880), hz: 75),
            PresetSample.setting(PresetSample.dell(), (3008, 1692), hz: 60),
        ]))
        #expect(service.events == [.mode(2, 10, .permanent)])
    }
}
