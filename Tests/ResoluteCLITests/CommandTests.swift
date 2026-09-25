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
              *  1728 × 1117  3456 × 2234 px  120*, 60 Hz  default, native
                 1496 × 967   2992 × 1934 px  120, 60 Hz
              Low Resolution (1×)
                 3456 × 2234    120, 60 Hz  native
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
    ])
    func rejectsImpossibleOrContradictoryRequestsBeforeChangingAnything(arguments: [String]) async {
        let service = FakeDisplays([Sample.builtIn])
        let result = await failure(["set"] + arguments, service: service)
        #expect(result?.code == 64)
        #expect(result?.message.contains("Usage: resolute set") == true)
        #expect(service.changes.isEmpty)
    }

    @Test func saysWhatAMistakenOptionWas() async {
        #expect(await failure(["set", "-1x5", "--dry-run"])?.message.hasPrefix("Error: Unknown option '-1x5'") == true)
        #expect(await failure(["set", "--refersh", "60"])?.message.hasPrefix("Error: Unknown option '--refersh'") == true)
    }

    @Test func pointsABareRateAtRefresh() async {
        #expect(await failure(["set", "60"])?.message
            == "Error: “60” is not a resolution. To change only the refresh rate, use --refresh 60.")
        #expect(await failure(["set"])?.message
            == "Error: Give a resolution, --refresh, --scale, --mode-id or --default. See 'resolute help set'.")
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
        #expect(removed.contains("2560 × 1440 1× stays in the override. To remove it too: resolute overrides remove 2560x1440@1x"))
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
            == "“frobnicate” is not a resolute command. The commands are displays, modes, set, mirror and overrides.")
    }

    @Test func leavesRealCommandsAndOptionsAlone() {
        for arguments in [[], ["modes", "-d", "x"], ["--json"], ["help"], ["--version"], ["overrides"]] {
            #expect(ResoluteCommand.unknownCommandMessage(for: arguments) == nil)
        }
    }
}
