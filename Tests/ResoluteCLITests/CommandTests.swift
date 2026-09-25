import Foundation
import ResoluteKit
import Testing
@testable import resolute

@Suite struct DisplaysCommandTests {
    @Test func listsEachDisplayWithItsCurrentMode() async throws {
        let transcript = try await resolute([], service: FakeDisplays([Sample.builtIn, Sample.monitor]))
        #expect(transcript.output == """
            0  Built-in Retina Display  (id 1, vendor 610, product a050, main, built-in)
               1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54
            1  DELL P2419H  (id 2, vendor 10ac, product a0c4)
               1920 × 1080 @ 60 Hz, mode 1
            """)
    }
}

@Suite struct DisplaysJSONTests {
    @Test func givesVendorAndProductIDsInHexLikeEveryOtherCommand() async throws {
        let output = try await resolute(["displays", "--json"]).output
        let displays = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]]
        #expect(displays?.first?["vendorID"] as? String == "610")
        #expect(displays?.first?["productID"] as? String == "a050")
    }
}

@Suite struct ModesCommandTests {
    @Test func marksTheCurrentModeInJSON() async throws {
        let output = try await resolute(["modes", "--json"]).output
        let list = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        #expect(list?["display"] as? String == "Built-in Retina Display")
        #expect(list?["currentModeID"] as? Int == 54)
        #expect((list?["modes"] as? [Any])?.count == 6)
    }

    @Test func groupsResolutionsWithTheirRefreshRates() async throws {
        let transcript = try await resolute(["modes"])
        #expect(transcript.output == """
            Built-in Retina Display: 6 modes
              HiDPI
              *  1728 × 1117  3456 × 2234 px  120*, 60 Hz  Default
                 1496 × 967   2992 × 1934 px  120, 60 Hz
              Low Resolution (1×)
                 3456 × 2234    120, 60 Hz  Native
            """)
    }

    @Test func mentionsHiddenModesUntilAskedForThem() async throws {
        let service = FakeDisplays([Sample.builtIn, Sample.monitor])
        #expect(try await resolute(["modes", "-d", "dell"], service: service).output.hasPrefix("DELL P2419H: 3 modes (+2 hidden; add --all)"))
        let all = try await resolute(["modes", "-d", "dell", "--all"], service: service).output
        #expect(all.contains("  Hidden"))
        #expect(all.contains("2560 × 1440"))
    }
}

@Suite struct SetCommandTests {
    @Test func savesAListedMode() async throws {
        let service = FakeDisplays([Sample.builtIn])
        let transcript = try await resolute(["set", "1496x967"], service: service)
        #expect(service.changes == [.init(displayID: 1, modeID: 42, scope: .permanent)])
        #expect(transcript.output == "Built-in Retina Display: 1496 × 967 HiDPI (2992 × 1934 px) @ 120 Hz, mode 42")
    }

    @Test func changesNothingOnADryRun() async throws {
        let service = FakeDisplays([Sample.builtIn])
        let transcript = try await resolute(["set", "--refresh", "60", "--dry-run"], service: service)
        #expect(service.changes.isEmpty)
        #expect(transcript.output == "Would switch Built-in Retina Display to 1728 × 1117 HiDPI (3456 × 2234 px) @ 60 Hz, mode 55.")
    }

    @Test func keepsASessionChangeUntilLogout() async throws {
        let service = FakeDisplays([Sample.builtIn])
        let transcript = try await resolute(["set", "--refresh", "60", "--session"], service: service)
        #expect(service.changes == [.init(displayID: 1, modeID: 55, scope: .session)])
        #expect(transcript.output.hasSuffix("(until you log out)"))
    }

    @Test func triesAHiddenModeAndSavesItWhenConfirmed() async throws {
        let service = FakeDisplays([Sample.monitor])
        try await resolute(["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"], service: service, decision: .keep)
        #expect(service.changes == [
            .init(displayID: 2, modeID: 90, scope: .session), .init(displayID: 2, modeID: 90, scope: .permanent),
        ])
    }

    @Test func revertsAHiddenModeThatIsNotConfirmed() async throws {
        let service = FakeDisplays([Sample.monitor])
        let transcript = try await resolute(["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"], service: service)
        #expect(service.changes.last == .init(displayID: 2, modeID: 1, scope: .session))
        #expect(transcript.output == "Kept the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
    }

    @Test(arguments: [
        ["--refresh", "0"], ["--refresh=-1"], ["--refresh", "nan"], ["--refresh", "1e309"], ["--refresh", "0.004"],
        ["--scale", "0"], ["--scale", "nan"], ["--scale", "inf"],
        ["960x600", "--mode-id", "55"], ["--mode-id", "55", "--refresh", "60"], ["--mode-id", "55", "--scale", "1"],
        ["--mode-id", "55", "--default"], ["960x600", "--default"], ["--default", "--refresh", "60"],
        ["1496x967@50", "--refresh", "60"], ["1728x1117@1x", "--scale", "2"], ["1496x967@60@50"],
        ["--refresh", "0x3c"], ["--refresh", "6e1"], ["--scale", "0x2"], ["--scale", "2e0"], ["1728x1117@0x3c"],
    ])
    func rejectsImpossibleOrContradictoryRequestsBeforeChangingAnything(arguments: [String]) async {
        let service = FakeDisplays([Sample.builtIn])
        let result = await failure(["set"] + arguments, service: service)
        #expect(result?.code == 64)
        #expect(result?.message.contains("Usage: resolute set") == true)
        #expect(service.changes.isEmpty)
    }

    @Test func takesRatesAndScalesAsPlainNumbers() async {
        #expect(await failure(["set", "--refresh", "0x3c"])?.message
            .hasPrefix("Error: --refresh takes a rate in hertz, for example 60 or 59.94.") == true)
        #expect(await failure(["set", "--scale", "2e0"])?.message
            .hasPrefix("Error: --scale takes 2 for HiDPI or 1 for low resolution.") == true)
        let service = FakeDisplays([Sample.builtIn])
        _ = try? await resolute(["set", "--refresh", "60.00", "--scale", "2"], service: service)
        #expect(service.changes == [.init(displayID: 1, modeID: 55, scope: .permanent)])
    }

    @Test func saysWhatAMistakenOptionWas() async {
        #expect(await failure(["set", "-1x5", "--dry-run"])?.message.hasPrefix("Error: Unknown option '-1x5'") == true)
        #expect(await failure(["set", "--refersh", "60"])?.message.hasPrefix("Error: Unknown option '--refersh'") == true)
    }

    @Test func pointsABareRateAtRefresh() async {
        let result = await failure(["set", "60"])
        #expect(result?.message.hasPrefix("Error: “60” is not a resolution. To change only the refresh rate, use --refresh 60.\nUsage: resolute set ") == true)
        #expect(result?.code == 64)
        // Numbers that cannot be a rate, or a rate that is already given, get no such hint.
        for arguments in [["set", "1496"], ["set", "0"], ["set", "60", "--refresh", "60"]] {
            #expect(await failure(arguments)?.message.contains("--refresh \(arguments[1])") == false)
        }
    }

    @Test func reportsMistakesFoundWhileRunningAsUsageErrors() async {
        for arguments in [["set"], ["set", "abc"], ["set", "x1080"]] {
            let result = await failure(arguments)
            #expect(result?.code == 64, "\(arguments)")
            #expect(result?.message.contains("Usage: resolute set") == true, "\(arguments)")
        }
        #expect(await failure(["set"])?.message.hasPrefix(
            "Error: Give a resolution, --refresh, --scale, --mode-id or --default.\nUsage: resolute set "
        ) == true)
    }

    /// A value containing an x is not a size unless it starts with a number.
    @Test func namesAMistypedOptionWhoseValueHasAnX() async {
        let result = await failure(["set", "--dry-run", "--dsplay", "Pro Display XDR", "1496x967"])
        #expect(result?.message.hasPrefix("Error: Unknown option '--dsplay'") == true)
    }

    @Test func saysHowBigASizeMayBe() async {
        #expect(await failure(["set", "70000x1080"])?.message.hasPrefix(
            "Error: “70000x1080” is larger than any display: sizes go up to 65535."
        ) == true)
    }

    @Test func explainsAMissingRateWithTheRatesOnOffer() async {
        let result = await failure(["set", "--refresh", "55"])
        #expect(result?.message == "Error: 1728 × 1117 HiDPI has no 55 Hz mode. It offers 120 Hz and 60 Hz.")
        #expect(result?.code == 1)
    }

    @Test func trustsTheFullSnapshotForAHiddenModeCoreGraphicsCannotName() async throws {
        let service = FakeDisplays([Sample.monitor], hidesHiddenCurrentMode: true)
        let transcript = try await resolute(
            ["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"], service: service, decision: .keep
        )
        #expect(transcript.errors.isEmpty)
        #expect(transcript.output == "DELL P2419H: 1920 × 1080 @ 75 Hz, mode 90, hidden")
    }

    @Test func reportsAHiddenModeTheDisplayIgnored() async {
        let result = await failure(
            ["set", "--mode-id", "90", "--allow-hidden", "-d", "dell"], service: FakeDisplays([Sample.monitor], ignoring: [90])
        )
        #expect(result?.message
            == "Error: DELL P2419H did not switch to that mode, so it was left as it was. The display may not support the mode.")
    }

    /// --session says how long a confirmed mode lasts; it must not skip the confirmation
    /// that brings back a picture when the display cannot show a hidden mode.
    @Test func stillAsksAboutAHiddenModeForTheSession() async throws {
        let reverted = FakeDisplays([Sample.monitor])
        try await resolute(["set", "--mode-id", "90", "--allow-hidden", "--session", "-d", "dell"], service: reverted)
        #expect(reverted.changes.last == .init(displayID: 2, modeID: 1, scope: .session))

        let kept = FakeDisplays([Sample.monitor])
        let transcript = try await resolute(
            ["set", "--mode-id", "90", "--allow-hidden", "--session", "-d", "dell"], service: kept, decision: .keep
        )
        #expect(kept.changes == [.init(displayID: 2, modeID: 90, scope: .session)])
        #expect(transcript.output.hasSuffix("(until you log out)"))
    }

    @Test func asksBeforeUsingAHiddenMode() async throws {
        let result = await failure(["set", "2560x1440", "-d", "dell"], service: FakeDisplays([Sample.monitor]))
        #expect(result?.message == "Error: 2560 × 1440 is a hidden mode that macOS does not list. Pass --allow-hidden to use it.")
        #expect(result?.code == 1)
    }
}

@Suite struct MirrorCommandTests {
    @Test func reportsAndChangesMirroring() async throws {
        let service = FakeDisplays([Sample.builtIn, Sample.monitor])
        #expect(try await resolute(["mirror"], service: service).output == "Mirroring is off.")
        #expect(try await resolute(["mirror", "toggle"], service: service).output == "Mirroring is on.")
        #expect(service.mirroringCalls == [true])
    }
}

@Suite struct OverridesCommandTests {
    @Test func addsListsAndRemovesEntries() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        try await resolute(["overrides", "add", "2560x1440@1x"] + staged)
        try await resolute(["overrides", "add", "1920x1080@1x"] + staged)
        try await resolute(["overrides", "remove", "1920x1080@1x"] + staged)
        let listed = try await resolute(["overrides", "list"] + staged).output
        #expect(listed.contains("vendor 610, product a050, connected: Built-in Retina Display, installed"))
        #expect(listed.contains("• 2560 × 1440 1×"))
        #expect(!listed.contains("1920 × 1080"))
    }

    @Test func pairsAHiDPIEntryAndSaysWhatStaysWhenItGoes() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        let added = try await resolute(["overrides", "add", "1280x720"] + staged).output
        #expect(added.hasPrefix(
            "Added 1280 × 720 HiDPI (2560 × 1440 px, flags 00000009 00a00000) for Built-in Retina Display (vendor 610, product a050)."
        ))
        #expect(added.contains("Also added 2560 × 1440 1×, the 1× entry HiDPI entries are paired with."))
        let removed = try await resolute(["overrides", "remove", "1280x720"] + staged).output
        #expect(removed.hasPrefix("Removed 1280 × 720 HiDPI for Built-in Retina Display (vendor 610, product a050)."))
        #expect(removed.contains(
            "2560 × 1440 1× stays in the override. If it was there only for 1280 × 720 HiDPI, remove it too: "
                + "resolute overrides remove 2560x1440@1x --root "
        ))
        #expect(removed.hasSuffix("The change applies after you reconnect the display or restart the Mac."))
    }

    @Test func saysWhenThereIsNothingToReset() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let transcript = try await resolute(["overrides", "reset", "--root", root.path(percentEncoded: false)])
        #expect(transcript.output
            == "There is no custom override for Built-in Retina Display (vendor 610, product a050), so there is nothing to remove.")
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Backups").path(percentEncoded: false)))
        // Nothing to remove needs no administrator rights either.
        let absent = try await resolute(["overrides", "reset", "--vendor", "fff0", "--product", "fff1"])
        #expect(absent.output.hasPrefix("There is no custom override for vendor fff0, product fff1"))
    }

    @Test func namesTheDisplayItResets() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        try await resolute(["overrides", "add", "2560x1440@1x"] + staged)
        let output = try await resolute(["overrides", "reset"] + staged).output
        #expect(output.hasPrefix("Removed the override for Built-in Retina Display (vendor 610, product a050)."))
        #expect(output.hasSuffix("The change applies after you reconnect the display or restart the Mac."))
    }

    @Test func explainsABadHexIDWithTheSubcommandsUsage() async {
        let result = await failure(["overrides", "show", "--vendor", "zz", "--product", "1"])
        #expect(result?.message.hasPrefix("Error: --vendor takes a hexadecimal ID, for example db4.") == true)
        #expect(result?.message.contains("Usage: resolute overrides show") == true)
        #expect(result?.code == 64)
    }

    @Test func describesOverridesInJSONWithTheSameWordsAsTheCode() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await resolute(["overrides", "show", "--json", "--root", root.path(percentEncoded: false)]).output
        let summary = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        #expect(summary?["vendorID"] as? String == "610")
        #expect(summary?["source"] as? String == "missing")
        #expect(summary?["connectedDisplay"] as? String == "Built-in Retina Display")
        #expect(summary?["connectedDisplayID"] as? Int == 1)
    }

    @Test func keepsEveryEntryWhenAddsOverlap() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for width in [1300, 1320, 1340, 1360, 1380, 1400] {
                group.addTask { try await resolute(["overrides", "add", "\(width)x800@1x"] + staged) }
            }
            try await group.waitForAll()
        }
        let installed = try OverrideStore(locations: .staged(at: root)).installedOverride(for: OverrideKey(vendorID: 0x610, productID: 0xA050))
        #expect(installed?.resolutions.count == 6)
    }

    @Test func knowsTheHiDPIModesApplesFileAlreadyLists() async throws {
        let root = try stagedRootWithApplesFile()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = await failure(["overrides", "add", "1280x800", "--root", root.path(percentEncoded: false)])
        #expect(result?.message == "Error: 1280 × 800 (HiDPI) is already in the list.")
        let output = try await resolute(["overrides", "show", "--json", "--root", root.path(percentEncoded: false)]).output
        let summary = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any]
        let entries = summary?["entries"] as? [[String: Any]] ?? []
        #expect(entries.count == 7)
        let apples = try #require(entries.first { $0["width"] as? Int == 1280 })
        #expect(apples["kind"] as? String == "hidpi")
        #expect(apples["pixelWidth"] as? Int == 2560)
        #expect(apples["keptAsIs"] as? Bool == true)
        #expect(apples["flags"] is NSNull)
    }

    @Test(arguments: [["overrides", "add", "100x100"], ["overrides", "add", "1600x1000", "--flags", "8,a00000"], ["overrides", "add", "abc"], ["overrides", "remove", "abc"]])
    func reportsBadEntriesAsUsageErrors(arguments: [String]) async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = await failure(arguments + ["--root", root.path(percentEncoded: false)])
        #expect(result?.code == 64)
        #expect(result?.message.contains("Usage: resolute overrides \(arguments[1])") == true)
    }

    @Test func givesExamplesThatWorkWhenCopied() async throws {
        let entry = await failure(["overrides", "add", "abc", "--root", "/tmp/unused"])
        #expect(entry?.message.hasPrefix("Error: “abc” is not a resolution. Use WIDTHxHEIGHT, optionally followed by @2x or @1x, for example 2560x1080.") == true)
        let flags = await failure(["overrides", "add", "1600x1000", "--flags", "junk", "--root", "/tmp/unused"])
        #expect(flags?.message.hasPrefix("Error: “junk” is not a flags value. Use two 32-bit hex words, for example 00000009,00a00000.") == true)
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try await resolute(["overrides", "add", "1600x1000", "--flags", "00000009,00a00000", "--root", root.path(percentEncoded: false)])
    }

    /// The hint after removing a HiDPI entry must never talk someone into deleting the
    /// panel's native entry from Apple's file.
    @Test func removesFromApplesFileWithoutSuggestingToDeleteItsEntries() async throws {
        let root = try stagedRootWithApplesFile()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        try await resolute(["overrides", "add", "1728x1117"] + staged)
        let removed = try await resolute(["overrides", "remove", "1728x1117"] + staged).output
        #expect(removed.contains("3456 × 2234 1× stays in the override: the file macOS ships lists it too."))
        #expect(!removed.contains("resolute overrides remove 3456x2234"))
        // An entry that only Apple's file lists can be removed from a copy of it.
        try await resolute(["overrides", "reset"] + staged)
        let apples = try await resolute(["overrides", "remove", "1280x800"] + staged).output
        #expect(apples.hasPrefix("Removed 1280 × 800 HiDPI for Built-in Retina Display (vendor 610, product a050)."))
        let installed = try #require(try OverrideStore(locations: .staged(at: root)).installedOverride(for: OverrideKey(vendorID: 0x610, productID: 0xA050)))
        #expect(installed.resolutions.count == 6)
        #expect(installed.productName == "Color LCD")
    }

    /// Entries outside the sizes `add` writes (old RDM or hand-made ones) can still be removed.
    @Test func removesAnEntryAddWouldRefuse() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = OverrideLocations.staged(at: root)
        let key = OverrideKey(vendorID: 0x610, productID: 0xA050)
        let file = locations.userFile(for: key)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DisplayOverride(key: key, resolutions: [.hiDPI(width: 300, height: 180, flags: .standard)]).propertyListData().write(to: file)
        try await resolute(["overrides", "remove", "300x180", "--root", root.path(percentEncoded: false)])
        #expect(try OverrideStore(locations: locations).installedOverride(for: key)?.resolutions.isEmpty == true)
    }

    @Test func pointsAtTheOneTimesEntryWhenTheHiDPIOneIsMissing() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        try await resolute(["overrides", "add", "3200x2000@1x"] + staged)
        #expect(await failure(["overrides", "remove", "3200x2000"] + staged)?.message
            == "Error: 3200 × 2000 HiDPI is not in the override for Built-in Retina Display (vendor 610, product a050), but 3200 × 2000 1× is: add @1x.")
    }

    @Test func tellsOnlyOneOfSeveralOverlappingResetsThatItRemovedTheOverride() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        try await resolute(["overrides", "add", "2560x1440@1x"] + staged)
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 { group.addTask { try await resolute(["overrides", "reset"] + staged).output } }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }
        #expect(outputs.filter { $0.hasPrefix("Removed the override") }.count == 1)
        #expect(outputs.filter { $0.hasPrefix("There is no custom override") }.count == 4)
    }

    @Test func needsRootForTheRealFolder() async {
        let result = await failure(["overrides", "add", "2560x1440"])
        #expect(result?.message == "Error: " + (ResoluteError.needsRoot.errorDescription ?? ""))
    }
}

@Suite struct UnknownCommandTests {
    @Test func suggestsTheCommandThatWasMeant() {
        #expect(ResoluteCommand.unknownCommandMessage(for: ["mode"]) == "“mode” is not a resolute command. Did you mean “resolute modes”?")
        #expect(ResoluteCommand.unknownCommandMessage(for: ["version"])
            == "“version” is not a resolute command. Did you mean “resolute --version”?")
        #expect(ResoluteCommand.unknownCommandMessage(for: ["1496x967"])
            == "“1496x967” is not a resolute command. To switch to that resolution, run “resolute set 1496x967”.")
        #expect(ResoluteCommand.unknownCommandMessage(for: ["frobnicate"])
            == "“frobnicate” is not a resolute command. The commands are displays, modes, set, mirror, overrides and doctor.")
    }

    @Test func pointsOverridesCommandsAtOverrides() {
        #expect(ResoluteCommand.unknownCommandMessage(for: ["reset"])
            == "“reset” is not a resolute command. Did you mean “resolute overrides reset”?")
        #expect(ResoluteCommand.unknownCommandMessage(for: ["list"])
            == "“list” is not a resolute command. Did you mean “resolute overrides list”?")
        #expect(ResoluteCommand.unknownCommandMessage(for: ["overrides", "ad", "1600x1000"])
            == "“ad” is not an overrides command. Did you mean “resolute overrides add”?")
        #expect(ResoluteCommand.unknownCommandMessage(for: ["overrides", "frobnicate"])
            == "“frobnicate” is not an overrides command. The overrides commands are list, show, add, remove, reset, backups, restore and prune.")
        #expect(ResoluteCommand.unknownCommandMessage(for: ["help", "mode"])
            == "“mode” is not a resolute command. Did you mean “resolute help modes”?")
        #expect(ResoluteCommand.unknownCommandMessage(for: ["overrides", "help"])
            == "“help” is not an overrides command. Did you mean “resolute help overrides”?")
    }

    @Test func leavesRealCommandsAndOptionsAlone() {
        for arguments in [
            [], ["modes", "-d", "x"], ["--json"], ["help"], ["--version"], ["overrides"], ["overrides", "--json"],
            ["overrides", "list"], ["help", "set"], ["help", "overrides", "add"],
        ] {
            #expect(ResoluteCommand.unknownCommandMessage(for: arguments) == nil, "\(arguments)")
        }
    }
}

/// Every documented key is always present, null when there is no value, so scripts and
/// typed decoders can rely on the shape documented in docs/json.md.
@Suite struct JSONShapeTests {
    func object(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    let modeKeys: Set<String> = [
        "modeID", "privateIndex", "width", "height", "pixelWidth", "pixelHeight", "refreshRate", "bitsPerSample", "ioFlags", "origin",
    ]

    @Test func givesEveryDisplayKey() async throws {
        var unknown = Sample.monitor
        unknown.currentModeID = nil
        let output = try await resolute(["displays", "--json"], service: FakeDisplays([Sample.builtIn, unknown])).output
        let displays = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
        let keys: Set<String> = [
            "index", "id", "name", "vendorID", "productID", "serialNumber", "isMain", "isBuiltin", "isInMirrorSet",
            "currentMode", "modeCount", "hiddenModeCount", "hiddenModes",
        ]
        #expect(displays.allSatisfy { Set($0.keys) == keys })
        #expect(displays[1]["currentMode"] is NSNull)
        let current = try #require(displays[0]["currentMode"] as? [String: Any])
        #expect(Set(current.keys) == modeKeys)
        #expect(current["privateIndex"] is NSNull)
    }

    @Test func givesEveryModeKey() async throws {
        var unknown = Sample.monitor
        unknown.currentModeID = nil
        let list = try object(try await resolute(["modes", "--json", "-d", "dell"], service: FakeDisplays([unknown])).output)
        #expect(Set(list.keys) == ["display", "displayID", "currentModeID", "hiddenModes", "modes"])
        #expect(list["currentModeID"] is NSNull)
        let modes = try #require(list["modes"] as? [[String: Any]])
        #expect(modes.allSatisfy { Set($0.keys) == modeKeys })
    }

    @Test func givesEveryOverrideKey() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        let empty = try object(try await resolute(["overrides", "show", "--json", "--vendor", "fff0", "--product", "fff1"] + staged).output)
        #expect(Set(empty.keys) == [
            "vendorID", "productID", "path", "source", "connectedDisplay", "connectedDisplayID", "productName", "entries", "problem",
        ])
        for key in ["connectedDisplay", "connectedDisplayID", "productName", "problem"] {
            #expect(empty[key] is NSNull, "\(key)")
        }
        try await resolute(["overrides", "add", "2560x1440@1x"] + staged)
        let added = try object(try await resolute(["overrides", "show", "--json"] + staged).output)
        let entry = try #require((added["entries"] as? [[String: Any]])?.first)
        #expect(Set(entry.keys) == ["kind", "width", "height", "pixelWidth", "pixelHeight", "flags", "keptAsIs", "summary"])
        #expect(entry["flags"] is NSNull)
    }
}

@Suite struct OverrideBackupCommandTests {
    let key = OverrideKey(vendorID: 0x610, productID: 0xA050)

    /// Three adds: the first creates the file, the next two each back up the one before.
    func stagedWithBackups() async throws -> (root: URL, staged: [String]) {
        let root = try stagedRoot()
        let staged = ["--root", root.path(percentEncoded: false)]
        for size in ["2560x1440@1x", "1920x1080@1x", "3840x2160@1x"] {
            try await resolute(["overrides", "add", size] + staged)
        }
        return (root, staged)
    }

    @Test func listsBackupsNewestFirst() async throws {
        let (root, staged) = try await stagedWithBackups()
        defer { try? FileManager.default.removeItem(at: root) }
        let backups = OverrideStore(locations: .staged(at: root)).backups(for: key)
        let output = try await resolute(["overrides", "backups"] + staged).output
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines.first?.hasPrefix("Backups of Built-in Retina Display (vendor 610, product a050), newest first, in ") == true)
        #expect(lines[1] == "  1  \(Output.localTime(backups[0].date))  2 entries  \(backups[0].fileName)")
        #expect(lines[2] == "  2  \(Output.localTime(backups[1].date))  1 entry    \(backups[1].fileName)")
        #expect(lines.last == "To restore one: resolute overrides restore <number> --root \(Output.shellWord(root.path(percentEncoded: false)))")
    }

    @Test func listsBackupsAsJSON() async throws {
        let (root, staged) = try await stagedWithBackups()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await resolute(["overrides", "backups", "--json"] + staged).output
        let list = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
        #expect(list.count == 2)
        #expect(list.allSatisfy { Set($0.keys) == ["number", "date", "fileName", "path", "entries", "productName", "problem"] })
        #expect(list[0]["number"] as? Int == 1)
        #expect(list[0]["entries"] as? Int == 2)
        #expect(list[0]["problem"] is NSNull)
        #expect((list[0]["date"] as? String)?.hasSuffix("Z") == true)
    }

    @Test func restoresABackupByNumberOrName() async throws {
        let (root, staged) = try await stagedWithBackups()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        let oldest = try #require(store.backups(for: key).last)
        let output = try await resolute(["overrides", "restore", "2"] + staged).output
        #expect(output.hasPrefix("Restored \(oldest.fileName), from \(Output.localTime(oldest.date)), for Built-in Retina Display (vendor 610, product a050)."))
        #expect(output.hasSuffix("The change applies after you reconnect the display or restart the Mac."))
        #expect(try store.installedOverride(for: key)?.resolutions == [.standard(width: 2560, height: 1440)])
        // What it replaced was backed up, and can be restored by name.
        let replaced = try #require(store.backups(for: key).first)
        #expect(try store.contents(of: replaced).override.resolutions.count == 3)
        try await resolute(["overrides", "restore", replaced.fileName] + staged)
        #expect(try store.installedOverride(for: key)?.resolutions.count == 3)
    }

    @Test func changesNothingWhenTheBackupMatchesTheOverride() async throws {
        let (root, staged) = try await stagedWithBackups()
        defer { try? FileManager.default.removeItem(at: root) }
        try await resolute(["overrides", "restore", "1"] + staged)
        let count = OverrideStore(locations: .staged(at: root)).backups(for: key).count
        let output = try await resolute(["overrides", "restore", "2"] + staged).output
        #expect(output.hasPrefix("The override for Built-in Retina Display (vendor 610, product a050) already matches"))
        #expect(OverrideStore(locations: .staged(at: root)).backups(for: key).count == count)
    }

    @Test func explainsABackupThatDoesNotExist() async throws {
        let (root, staged) = try await stagedWithBackups()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await failure(["overrides", "restore", "7"] + staged)?.message
            == "Error: There is no backup 7 of Built-in Retina Display (vendor 610, product a050): there are 2. List them with `resolute overrides backups`.")
        #expect(await failure(["overrides", "restore", "nope.plist"] + staged)?.message
            == "Error: There is no backup named “nope.plist” of Built-in Retina Display (vendor 610, product a050). List them with `resolute overrides backups`.")
    }

    @Test func saysWhenThereAreNoBackups() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        #expect(try await resolute(["overrides", "backups"] + staged).output.hasPrefix(
            "There are no backups of Built-in Retina Display (vendor 610, product a050) in "
        ))
        #expect(await failure(["overrides", "restore", "1"] + staged)?.message.hasPrefix(
            "Error: There are no backups of Built-in Retina Display (vendor 610, product a050)"
        ) == true)
        // Nothing to prune needs no administrator rights.
        #expect(try await resolute(["overrides", "prune", "--vendor", "fff0", "--product", "fff1"]).output
            == "Nothing to remove: vendor fff0, product fff1 has no backups.")
    }

    @Test func prunesAllButTheNewest() async throws {
        let (root, staged) = try await stagedWithBackups()
        defer { try? FileManager.default.removeItem(at: root) }
        try await resolute(["overrides", "add", "5120x2880@1x"] + staged)
        let store = OverrideStore(locations: .staged(at: root))
        let newest = Array(store.backups(for: key).prefix(1))
        #expect(try await resolute(["overrides", "prune", "--keep", "1"] + staged).output
            == "Removed 2 backups of Built-in Retina Display (vendor 610, product a050), and kept the newest 1.")
        #expect(store.backups(for: key) == newest)
        #expect(try await resolute(["overrides", "prune", "--keep", "1"] + staged).output
            == "Nothing to remove: Built-in Retina Display (vendor 610, product a050) has 1 backup.")
    }

    @Test func prunesEveryDisplayWithAll() async throws {
        let (root, staged) = try await stagedWithBackups()
        defer { try? FileManager.default.removeItem(at: root) }
        for size in ["1600x1000@1x", "1680x1050@1x"] {
            try await resolute(["overrides", "add", size, "--vendor", "10ac", "--product", "a0c4"] + staged)
        }
        let output = try await resolute(["overrides", "prune", "--keep", "0", "--all"] + staged).output
        #expect(output == """
            Removed 2 backups of Built-in Retina Display (vendor 610, product a050), and kept none.
            Removed 1 backup of vendor 10ac, product a0c4, and kept none.
            """)
        #expect(OverrideStore(locations: .staged(at: root)).backupKeys().isEmpty)
        #expect(await failure(["overrides", "prune", "--all", "-d", "main"] + staged)?.code == 64)
        #expect(await failure(["overrides", "prune", "--keep", "-1"] + staged)?.code == 64)
    }

    @Test func pointsAResetAtRestore() async throws {
        let (root, staged) = try await stagedWithBackups()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await resolute(["overrides", "reset"] + staged).output
        #expect(output.contains("To undo it: resolute overrides restore 1 --root "))
    }

    /// Hints after a change repeat the command the way it was run: with sudo, or --root.
    @Test func writesFollowUpCommandsTheWayTheChangeWasRun() throws {
        let real = try LocationOptions.parse([])
        #expect(real.command("overrides restore 1 -d DELL", isRoot: true) == "sudo resolute overrides restore 1 -d DELL")
        let staged = try LocationOptions.parse(["--root", "/tmp/a b"])
        #expect(staged.command("overrides restore 1", isRoot: false) == "resolute overrides restore 1 --root '/tmp/a b'")
    }
}

@Suite struct UnpairedEntryWarningTests {
    /// Removing the 1× entry a HiDPI entry renders at is allowed, with a word about it.
    @Test func warnsWhenAHiDPIEntryLosesItsOneTimesEntry() async throws {
        let root = try stagedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = ["--root", root.path(percentEncoded: false)]
        try await resolute(["overrides", "add", "1280x720"] + staged)
        let output = try await resolute(["overrides", "remove", "2560x1440@1x"] + staged).output
        #expect(output.contains(
            "1280 × 720 HiDPI no longer has its 1× entry at 2560 × 1440, which Resolute and RDM add with each HiDPI entry. "
                + "To put it back: resolute overrides add 2560x1440@1x --root "
        ))
        let quiet = try await resolute(["overrides", "remove", "1280x720"] + staged).output
        #expect(!quiet.contains("no longer has"))
    }
}

@Suite struct DoctorCommandTests {
    /// A staged root with Apple's file for the built-in panel and an RDM-style override for a
    /// monitor that is not connected.
    func stagedRootForDoctor() async throws -> URL {
        let root = try stagedRootWithApplesFile()
        let staged = ["--root", root.path(percentEncoded: false)]
        try await resolute(["overrides", "add", "5120x2160@1x", "--vendor", "db4", "--product", "3401"] + staged)
        try await resolute(["overrides", "add", "2560x1080", "--vendor", "db4", "--product", "3401"] + staged)
        return root
    }

    @Test func reportsWhatABugReportNeeds() async throws {
        let root = try await stagedRootForDoctor()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await resolute(
            ["doctor", "--root", root.path(percentEncoded: false)], service: FakeDisplays([Sample.builtIn, Sample.monitor])
        ).output
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "Resolute \(ResoluteVersion.string)")
        #expect(lines[1].hasPrefix("macOS "))
        #expect(lines.contains("Hidden modes: the private SkyLight functions are \(SkyLight.shared == nil ? "unavailable" : "available")."))
        #expect(lines.contains("0  Built-in Retina Display (id 1, vendor 610, product a050, serial 0, main, built-in)"))
        #expect(lines.contains("   1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54"))
        #expect(lines.contains("   6 modes, none hidden; hidden modes available"))
        #expect(lines.contains("   Override: none installed; macOS ships one with 7 entries, named “Color LCD”"))
        #expect(lines.contains("1  DELL P2419H (id 2, vendor 10ac, product a0c4, serial 0)"))
        #expect(lines.contains("   5 modes, 2 hidden; hidden modes available"))
        #expect(lines.contains("   Override: none"))
        #expect(lines.contains("Overrides for displays that are not connected:"))
        #expect(lines.contains("  vendor db4, product 3401: 2 entries, 1 backup"))
        #expect(lines.last?.hasPrefix("Recent activity: log show --last 1h --predicate") == true)
    }

    @Test func reportsAsJSON() async throws {
        let root = try await stagedRootForDoctor()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try await resolute(["doctor", "--json", "--root", root.path(percentEncoded: false)]).output
        let report = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect(Set(report.keys) == [
            "version", "macOS", "model", "architecture", "translated", "privateModeFunctions", "displays", "otherOverrides",
        ])
        #expect(report["version"] as? String == ResoluteVersion.string)
        let display = try #require((report["displays"] as? [[String: Any]])?.first)
        #expect(Set(display.keys) == ["display", "override", "backups"])
        let override = try #require(display["override"] as? [String: Any])
        #expect(Set(override.keys) == ["source", "path", "entries", "problem"])
        #expect(override["source"] as? String == "system")
        #expect(override["entries"] as? Int == 7)
        let other = try #require((report["otherOverrides"] as? [[String: Any]])?.first)
        #expect(other["vendorID"] as? String == "db4")
        #expect(other["backups"] as? Int == 1)
    }
}
