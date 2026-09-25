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

@Suite struct ModesCommandTests {
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

    @Test func needsRootForTheRealFolder() async {
        let result = await failure(["overrides", "add", "2560x1440"])
        #expect(result?.message == "Error: " + (ResoluteError.needsRoot.errorDescription ?? ""))
    }
}
