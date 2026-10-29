import Foundation
import ResoluteKit
import Testing
@testable import resolute

/// The display the design's terminal frame (68:2029) talks to.
enum ScalingSample {
    static let key = OverrideKey(vendorID: 0x6B3, productID: 0x27C4)
    static let sizes = ["1600x900", "1920x1080", "2048x1152", "2304x1296", "2560x1440"].compactMap { SharpSize($0) }

    static func mode(_ id: Int32, _ width: Int, _ height: Int, scale: Int = 1, hz: Double, flags: UInt32 = 0x3) -> DisplayMode {
        DisplayMode(
            modeID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale,
            refreshRate: hz, bitsPerSample: 8, ioFlags: flags
        )
    }

    /// An ASUS PA278QV: a 2560 × 1440 panel at 75, 60 and 50 Hz with 1× sizes only. `sharp`
    /// adds the HiDPI modes macOS lists once it has read the override, at 75 and 60 Hz
    /// (2560 × 1440 is modes 108 and 109).
    static func asus(current: Int32 = 1, sharp: [SharpSize] = []) -> Display {
        monitor(name: "ASUS PA278QV", native: (2560, 1440), current: current, sharp: sharp)
    }

    /// A 34-inch ultrawide with a 3440 × 1440 panel.
    static func ultrawide() -> Display {
        monitor(name: "Dell U3423WE", native: (3440, 1440), current: 1, sharp: [], productID: 0x4214)
    }

    static func monitor(name: String, native: (Int, Int), current: Int32, sharp: [SharpSize], productID: UInt32 = key.productID) -> Display {
        var modes = [
            mode(1, native.0, native.1, hz: 75, flags: 0x0200_0007),
            mode(2, native.0, native.1, hz: 60, flags: 0x0200_0003),
            mode(3, native.0, native.1, hz: 50, flags: 0x0200_0003),
            mode(4, 1920, 1080, hz: 60),
            mode(5, 1280, 720, hz: 60),
        ]
        for (index, size) in sharp.enumerated() {
            modes.append(mode(Int32(100 + index * 2), size.width, size.height, scale: 2, hz: 75))
            modes.append(mode(Int32(101 + index * 2), size.width, size.height, scale: 2, hz: 60))
        }
        return Display(
            id: 2, name: name, vendorID: key.vendorID, productID: productID, currentModeID: current, modes: modes,
            privateModes: .trusted
        )
    }

    static func service(_ display: Display = asus()) -> FakeDisplays {
        FakeDisplays([Sample.builtIn, display])
    }
}

@Suite struct ScalingCommandTests {
    let key = ScalingSample.key
    let sizes = ScalingSample.sizes

    /// A staged override root, and the arguments that point a command at it.
    func staged() throws -> (root: URL, arguments: [String]) {
        let root = try stagedRoot()
        return (root, ["--root", root.path(percentEncoded: false)])
    }

    func store(_ root: URL) -> OverrideStore {
        OverrideStore(locations: .staged(at: root))
    }

    /// Writes `override` as the display's installed file, as another tool would; returns its bytes.
    @discardableResult
    func install(_ override: DisplayOverride, at root: URL) throws -> Data {
        let file = OverrideLocations.staged(at: root).userFile(for: override.key)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try override.propertyListData()
        try data.write(to: file)
        return data
    }

    func installedBytes(_ root: URL) -> Data? {
        FileManager.default.contents(atPath: OverrideLocations.staged(at: root).userFile(for: key).path(percentEncoded: false))
    }

    func hiDPISizes(_ override: DisplayOverride?) -> [SharpSize] {
        (override?.resolutions ?? []).compactMap { entry in
            guard case .hiDPI(let width, let height, _)? = entry.describedMode else { return nil }
            return SharpSize(width: width, height: height)
        }.sorted()
    }

    /// `resolute scaling …` for the ASUS, at the design's drawing limit, against `root`.
    @discardableResult
    func scaling(
        _ arguments: [String], at staged: [String], display: Display = ScalingSample.asus(), service: FakeDisplays? = nil
    ) async throws -> Transcript {
        try await resolute(["scaling"] + arguments + ["-d", "ASUS"] + staged, service: service ?? ScalingSample.service(display))
    }

    // MARK: - plan

    @Test func plansTheDesignsFiveSizes() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await scaling(["plan", "--drawing-limit", "6144"], at: staged).output
        #expect(output == """
            ASUS PA278QV · 2560 × 1440 panel · this Mac draws up to 6144 px wide on it
              1600 × 900    drawn at 3200 × 1800    text 60% larger
              1920 × 1080   drawn at 3840 × 2160    text 33% larger
              2048 × 1152   drawn at 4096 × 2304    text 25% larger
              2304 × 1296   drawn at 4608 × 2592    text 11% larger
              2560 × 1440   drawn at 5120 × 2880    same size as now
            """)
    }

    @Test func marksTheSizesThisMacCantDraw() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ScalingSample.service(ScalingSample.ultrawide())
        let output = try await resolute(["scaling", "plan", "-d", "Dell", "--drawing-limit", "6144"] + staged, service: service).output
        #expect(output == """
            Dell U3423WE · 3440 × 1440 panel · this Mac draws up to 6144 px wide on it
              2150 × 900    drawn at 4300 × 1800    text 60% larger
              2580 × 1080   drawn at 5160 × 2160    text 33% larger
              2752 × 1152   drawn at 5504 × 2304    text 25% larger
              3096 × 1296   drawn at 6192 × 2592    left out: wider than this Mac draws
              3440 × 1440   drawn at 6880 × 2880    left out: wider than this Mac draws
            """)
        let unknown = try await resolute(["scaling", "plan", "-d", "Dell", "--drawing-limit", "99999"] + staged, service: service).output
        #expect(!unknown.contains("left out"))
    }

    @Test func plansInJSONOnOneLine() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await scaling(["plan", "--json", "--drawing-limit", "7680x4320"], at: staged).output
        #expect(output == #"{"display":"ASUS PA278QV","panel":"2560x1440","limit":{"width":7680,"height":4320},"sizes":["#
            + #"{"size":"1600x900","drawn":"3200x1800","textLarger":60,"fits":true},"#
            + #"{"size":"1920x1080","drawn":"3840x2160","textLarger":33,"fits":true},"#
            + #"{"size":"2048x1152","drawn":"4096x2304","textLarger":25,"fits":true},"#
            + #"{"size":"2304x1296","drawn":"4608x2592","textLarger":11,"fits":true},"#
            + #"{"size":"2560x1440","drawn":"5120x2880","textLarger":0,"fits":true}]}"#)
        #expect(try JSONSerialization.jsonObject(with: Data(output.utf8)) is [String: Any])
    }

    @Test func refusesDisplaysWhoseSizesAreSharpAlready() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let builtIn = await failure(["scaling", "plan"] + staged)
        #expect(builtIn?.message
            == "Error: Built-in Retina Display doesn’t need Sharp Scaling: built-in displays are Retina displays, so their sizes are sharp already.")
        #expect(builtIn?.code == 1)
        let retina = await failure(["scaling", "on", "-d", "ASUS"] + staged, service: ScalingSample.service(ScalingSample.asus(sharp: sizes)))
        #expect(retina?.message == "Error: ASUS PA278QV doesn’t need Sharp Scaling: it has HiDPI sizes already, which resolute modes lists.")
    }

    @Test func explainsADrawingLimitItCantRead() async {
        let result = await failure(["scaling", "plan", "--drawing-limit", "wide"])
        #expect(result?.code == 64)
        #expect(result?.message.hasPrefix("Error: --drawing-limit takes WIDTH or WIDTHxHEIGHT in pixels, for example 6144.") == true)
    }

    // MARK: - on

    @Test func turnsOnAsTheDesignShows() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        // The display had an override already, so there is a file to back up.
        try install(DisplayOverride(key: key, resolutions: [.standard(width: 2048, height: 1080)], isNew: false), at: root)
        let service = ScalingSample.service()
        let output = try await scaling(["on", "--switch", "--drawing-limit", "6144"], at: staged, service: service).output
        #expect(output == "Backed up the override file for ASUS PA278QV.\nAdded 5 sharp sizes. Reconnect the display or restart to use them.")
        let installed = try store(root).installedOverride(for: key)
        #expect(hiDPISizes(installed) == sizes)
        #expect(installed?.resolutions.contains(.standard(width: 2048, height: 1080)) == true)
        let record = try #require(try installed.flatMap { try SharpScalingRecord(in: $0) })
        // The app switches to the sharp 2560 × 1440 once macOS offers it.
        #expect(record.switchTo == SharpSize(width: 2560, height: 1440))
        #expect(store(root).backups(for: key).count == 1)
        // Nothing to switch to until the display reconnects.
        #expect(service.changes.isEmpty)
    }

    @Test func turnsOnWithoutABackupWhenThereWasNoFile() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await scaling(["on", "--drawing-limit", "6144"], at: staged).output
        #expect(output == "Added 5 sharp sizes. Reconnect the display or restart to use them.")
        #expect(store(root).backups(for: key).isEmpty)
        let installed = try #require(try store(root).installedOverride(for: key))
        #expect(try SharpScalingRecord(in: installed)?.switchTo == nil)
    }

    @Test(arguments: [["--sizes", "1600x900,2560x1440"], ["--sizes", "2560x1440", "1600x900"], ["--sizes", "1600 × 900, 2560x1440"]])
    func turnsOnOnlyTheSizesAsked(sizeArguments: [String]) async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await scaling(["on"] + sizeArguments, at: staged).output
        #expect(output == "Added 2 sharp sizes. Reconnect the display or restart to use them.")
        #expect(hiDPISizes(try store(root).installedOverride(for: key)) == [sizes[0], sizes[4]])
    }

    @Test func refusesSizesThePlanDoesntHave() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = await failure(["scaling", "on", "-d", "ASUS", "--sizes", "2000x1000"] + staged, service: ScalingSample.service())
        #expect(other?.code == 64)
        #expect(other?.message.hasPrefix(
            "Error: 2000 × 1000 is not one of the sharp sizes for ASUS PA278QV: 1600x900, 1920x1080, 2048x1152, 2304x1296 and 2560x1440.\n"
                + "Usage: resolute scaling on"
        ) == true)
        let tooWide = await failure(
            ["scaling", "on", "-d", "Dell", "--sizes", "3440x1440", "--drawing-limit", "6144"] + staged,
            service: ScalingSample.service(ScalingSample.ultrawide())
        )
        #expect(tooWide?.message.hasPrefix(
            "Error: 3440 × 1440 is drawn at 6880 × 2880, and this Mac draws up to 6144 px wide on it, so it can’t be added."
        ) == true)
        let notASize = await failure(["scaling", "on", "--sizes", "big"] + staged)
        #expect(notASize?.code == 64)
        #expect(notASize?.message.hasPrefix("Error: “big” is not a size. Use WIDTHxHEIGHT from resolute scaling plan, for example 1920x1080.") == true)
        #expect(installedBytes(root) == nil)
    }

    @Test func needsRootForTheRealFolder() async {
        let result = await failure(["scaling", "on", "-d", "ASUS", "--drawing-limit", "6144"], service: ScalingSample.service())
        #expect(result?.message == "Error: " + (ResoluteError.needsRoot.errorDescription ?? ""))
    }

    @Test func changesNothingWhenTheSizesAreSavedAlready() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        let before = installedBytes(root)
        let again = try await scaling(["on"], at: staged).output
        #expect(again == "Sharp Scaling is already on for ASUS PA278QV with these sizes. Reconnect the display or restart to use them.")
        #expect(installedBytes(root) == before)
        #expect(store(root).backups(for: key).isEmpty)
    }

    /// 68:2089's Remove Skipped Size, from the command line: on again without the skipped size.
    @Test func takesOutASizeMacOSSkipped() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        let skipping = ScalingSample.asus(sharp: Array(sizes.prefix(4)))
        let output = try await scaling(["on", "--sizes", "1600x900,1920x1080,2048x1152,2304x1296"], at: staged, display: skipping).output
        #expect(output == "Backed up the override file for ASUS PA278QV.\nRemoved 1 sharp size. Reconnect the display or restart to apply the change.")
        #expect(hiDPISizes(try store(root).installedOverride(for: key)) == Array(sizes.prefix(4)))
        let status = try await scaling(["status", "--json"], at: staged, display: skipping).output
        #expect(status.contains(#""scaling":"on","saved":4,"available":4,"skipped":[]"#))
    }

    @Test func switchesOnceMacOSOffersTheSharpSize() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        // Back from the reconnect at 2560 × 1440, 60 Hz: the sharp one keeps the 60 Hz.
        let service = ScalingSample.service(ScalingSample.asus(current: 2, sharp: sizes))
        let transcript = try await scaling(["on", "--switch"], at: staged, service: service)
        #expect(transcript.output == "Sharp Scaling is already on for ASUS PA278QV with these sizes.\nASUS PA278QV: 2560 × 1440 HiDPI (5120 × 2880 px) @ 60 Hz, mode 109")
        #expect(service.changes == [FakeDisplays.Change(displayID: 2, modeID: 109, scope: .permanent)])
        // The switch is in History, to undo like any other.
        #expect(try HistoryStore(locations: transcript.support).entries().map(\.outcome) == [.applied])
        let again = try await scaling(["on", "--switch"], at: staged, service: service).output
        #expect(again.hasSuffix("ASUS PA278QV is already at 2560 × 1440 HiDPI (5120 × 2880 px) @ 60 Hz, mode 109."))
        #expect(service.changes.count == 1)
    }

    @Test func saysToRunAgainWhenTheSharpSizeIsNotThereYet() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        let service = ScalingSample.service()
        let output = try await scaling(["on", "--switch"], at: staged, service: service).output
        #expect(output == "Sharp Scaling is already on for ASUS PA278QV with these sizes. Reconnect the display or restart to use them.\n"
            + "Run this again after the reconnect to switch to the sharp 2560 × 1440.")
        #expect(service.changes.isEmpty)
    }

    // MARK: - status

    @Test func reportsStatusAsTheDesignShows() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on", "--switch"], at: staged)
        // After the reconnect, the app has moved the display to the sharp 2560 × 1440.
        let ready = ScalingSample.asus(current: 108, sharp: sizes)
        let json = try await scaling(["status", "--json"], at: staged, display: ready).output
        #expect(json == #"{"display":"ASUS PA278QV","scaling":"on","saved":5,"available":5,"skipped":[],"current":"2560x1440","hidpi":true}"#)
        let text = try await scaling(["status"], at: staged, display: ready).output
        #expect(text == "Sharp Scaling is ready on ASUS PA278QV.\nmacOS accepted all 5 sizes, and ASUS PA278QV now uses the sharp 2560 × 1440.")
    }

    @Test func pointsAtTheSharpVersionWhileTheDisplayStaysAtOneTimes() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        let text = try await scaling(["status"], at: staged, display: ScalingSample.asus(current: 1, sharp: sizes)).output
        #expect(text == """
            Sharp Scaling is ready on ASUS PA278QV.
            macOS accepted all 5 sizes. ASUS PA278QV still uses 2560 × 1440 at 1×.
            To switch to the sharp one: resolute set 2560x1440@2x -d ASUS
            """)
    }

    @Test func saysItIsWaitingForTheReconnect() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        let json = try await scaling(["status", "--json"], at: staged).output
        // Nothing is skipped yet: macOS reads the file when the display connects.
        #expect(json == #"{"display":"ASUS PA278QV","scaling":"waiting","saved":5,"available":0,"skipped":[],"current":"2560x1440","hidpi":false}"#)
        let lines = try await scaling(["status"], at: staged).output.components(separatedBy: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "Sharp Scaling for ASUS PA278QV is saved and waits for a reconnect.")
        #expect(lines[1].hasPrefix("Saved on "))
        #expect(lines[1].hasSuffix(": 1600 × 900, 1920 × 1080, 2048 × 1152, 2304 × 1296 and 2560 × 1440. macOS reads the override file when the display connects."))
        #expect(lines[2] == "Reconnect the display or restart to use them.")
    }

    /// 68:2089: macOS added four of the five sizes.
    @Test func namesTheSizeMacOSSkipped() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        let skipping = ScalingSample.asus(sharp: Array(sizes.prefix(4)))
        let json = try await scaling(["status", "--json"], at: staged, display: skipping).output
        #expect(json == #"{"display":"ASUS PA278QV","scaling":"partial","saved":5,"available":4,"skipped":["2560x1440"],"current":"2560x1440","hidpi":false}"#)
        let text = try await scaling(["status"], at: staged, display: skipping).output
        let rootArgument = Output.shellWord(root.path(percentEncoded: false))
        #expect(text == """
            macOS added 4 of 5 sizes for ASUS PA278QV.
            It skipped 2560 × 1440 on this Mac. Keep the other four, or remove the skipped size so the list matches what you can use.
            To remove it: resolute scaling on -d ASUS --root \(rootArgument) --sizes 1600x900,1920x1080,2048x1152,2304x1296
            """)
    }

    /// A Mac started since the save means the display read the file: sizes still missing were skipped.
    @Test func knowsMacOSSkippedEverySizeAfterARestart() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = OverrideLocations.staged(at: root)
        let longAgo = OverrideInstaller(locations: locations, runner: ShellCommandRunner(), now: { Date(timeIntervalSince1970: 1_000_000_000) })
        try await SharpScalingWriter(store: OverrideStore(locations: locations), installer: longAgo)
            .turnOn(for: ScalingSample.asus(), sizes: sizes, switchTo: nil)
        let json = try await scaling(["status", "--json"], at: staged).output
        #expect(json.hasPrefix(#"{"display":"ASUS PA278QV","scaling":"partial","saved":5,"available":0,"#))
        let text = try await scaling(["status"], at: staged).output
        #expect(text == """
            macOS added none of the 5 sharp sizes for ASUS PA278QV.
            It skipped all of them on this Mac.
            To remove them: resolute scaling off -d ASUS --root \(Output.shellWord(root.path(percentEncoded: false)))
            """)
    }

    @Test func saysItIsOffAndHowToSeeThePlan() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let json = try await scaling(["status", "--json"], at: staged).output
        #expect(json == #"{"display":"ASUS PA278QV","scaling":"off","saved":0,"available":0,"skipped":[],"current":"2560x1440","hidpi":false}"#)
        // status is what `resolute scaling` runs.
        let text = try await scaling([], at: staged).output
        #expect(text == "Sharp Scaling is off for ASUS PA278QV.\n"
            + "To see the sizes it would add: resolute scaling plan -d ASUS --root \(Output.shellWord(root.path(percentEncoded: false)))")
        let builtIn = try await resolute(["scaling", "status"] + staged).output
        #expect(builtIn == "Sharp Scaling is off for Built-in Retina Display.")
    }

    // MARK: - off

    @Test func turnsOffByPuttingBackTheFileFromBefore() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try install(
            DisplayOverride(key: key, productName: "Studio", resolutions: [.standard(width: 2048, height: 1080)], isNew: false), at: root
        )
        try await scaling(["on"], at: staged)
        let output = try await scaling(["off"], at: staged).output
        #expect(output == "Backed up the override file for ASUS PA278QV.\n"
            + "Put back the file from before Sharp Scaling. The sharp sizes go away after you reconnect the display or restart.")
        #expect(installedBytes(root) == before)
        #expect(store(root).backups(for: key).count == 2)
        let status = try await scaling(["status", "--json"], at: staged).output
        #expect(status.contains(#""scaling":"off""#))
    }

    @Test func turnsOffByRemovingAFileItCreated() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        let output = try await scaling(["off"], at: staged).output
        #expect(output == "Backed up the override file for ASUS PA278QV.\n"
            + "Removed the override file Sharp Scaling created. The sharp sizes go away after you reconnect the display or restart.")
        #expect(installedBytes(root) == nil)
    }

    @Test func turnsOffKeepingChangesMadeSince() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        try await scaling(["on"], at: staged)
        try await resolute(["overrides", "add", "1280x800@1x", "-d", "ASUS"] + staged, service: ScalingSample.service())
        let output = try await scaling(["off"], at: staged).output
        #expect(output == "Backed up the override file for ASUS PA278QV.\n"
            + "Took out the sharp sizes and kept the rest of the file, which changed after Sharp Scaling was set up. "
            + "The sharp sizes go away after you reconnect the display or restart.")
        let installed = try #require(try store(root).installedOverride(for: key))
        #expect(installed.resolutions == [.standard(width: 1280, height: 800)])
        #expect(try SharpScalingRecord(in: installed) == nil)
    }

    /// Nothing to remove needs no administrator rights, so this works without sudo, even for
    /// the real folder.
    @Test func saysWhenThereIsNothingToTurnOff() async throws {
        let (root, staged) = try staged()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await scaling(["off"], at: staged).output
        #expect(output == "Sharp Scaling is off for ASUS PA278QV, so there is nothing to remove.")
        let real = try await resolute(["scaling", "off", "-d", "ASUS"], service: ScalingSample.service()).output
        #expect(real == "Sharp Scaling is off for ASUS PA278QV, so there is nothing to remove.")
    }
}

@Suite struct OrderedJSONTests {
    @Test func escapesTextAndKeepsTheKeyOrder() throws {
        let json = OrderedJSON.object([
            ("z", .string("Studio \"27\" / 5K")), ("a", .array([.number(1), .bool(false), .null])),
        ]).text
        #expect(json == #"{"z":"Studio \"27\" / 5K","a":[1,false,null]}"#)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        #expect(parsed?["z"] as? String == "Studio \"27\" / 5K")
    }
}
