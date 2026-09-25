import Foundation
import Testing
@testable import ResoluteKit

@Suite struct OverrideInstallerTests {
    let key = OverrideKey(vendorID: 0xDB4, productID: 0x3401)
    let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

    func installer(at root: URL) -> OverrideInstaller {
        let date = fixedDate
        return OverrideInstaller(locations: .staged(at: root), runner: ShellCommandRunner(), now: { date })
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func neverAsksRootToReadAFileTheUserCanSwap() async throws {
        let recorder = ScriptRecorder()
        let installer = OverrideInstaller(runner: RecordingRunner(recorder: recorder))
        let override = DisplayOverride(key: key, resolutions: [.hiDPI(width: 2560, height: 1080, flags: .standard)])
        try await installer.install(override)
        let script = try #require(await recorder.scripts.first)
        let userTemporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path(percentEncoded: false)
        #expect(!script.contains(FileManager.default.temporaryDirectory.path(percentEncoded: false)))
        #expect(!script.contains(userTemporary))
        #expect(script.contains(try override.propertyListData().base64EncodedString()))
    }

    @Test func writesReadableFilesUnderAStrictUmask() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = fixedDate
        let installer = OverrideInstaller(locations: .staged(at: root), runner: StrictUmaskRunner(), now: { date })
        let url = try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)]))
        let folder = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path(percentEncoded: false))
        let file = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o755)
        #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o644)
    }

    @Test func handlesPathsWithQuotesAndSpaces() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let override = DisplayOverride(key: key, resolutions: [.hiDPI(width: 2560, height: 1080, flags: .standard)])
        let url = try await installer.install(override)
        #expect(url == installer.locations.userFile(for: key))
        let stored = try OverrideStore(locations: installer.locations).installedOverride(for: key)
        #expect(stored?.resolutions == override.resolutions)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)
    }

    @Test func installsThroughAppleScript() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = fixedDate
        let installer = OverrideInstaller(locations: .staged(at: root), runner: UnprivilegedAppleScriptRunner(), now: { date })
        let override = DisplayOverride(key: key, productName: "Studio \"27\"", resolutions: [.hiDPI(width: 2560, height: 1080, flags: .standard)])
        try await installer.install(override)
        try await installer.install(override)  // replaces the file and backs it up
        let stored = try #require(try OverrideStore(locations: installer.locations).installedOverride(for: key))
        #expect(stored.productName == "Studio \"27\"")
        #expect(stored.resolutions == override.resolutions)
        #expect(stored.otherKeys.keys == ["target-default-ppmm"])
        let backups = installer.locations.backupRoot.appending(path: key.vendorDirectoryName)
        #expect(try FileManager.default.contentsOfDirectory(atPath: backups.path(percentEncoded: false)).count == 1)
        try await installer.remove(key)
        #expect(try OverrideStore(locations: installer.locations).installedOverride(for: key) == nil)
    }

    @Test func backsUpTheFileItReplaces() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)]))
        let backup = installer.backupFile(for: key)
        #expect(!exists(backup))
        try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 2560, height: 1440)]))
        #expect(exists(backup))
        let saved = try DisplayOverride(key: key, propertyList: Data(contentsOf: backup))
        #expect(saved.resolutions == [.standard(width: 1920, height: 1080)])
        #expect(backup.lastPathComponent == "DisplayProductID-3401-20260921-141320.plist")
    }

    @Test func keepsEveryBackupMadeWithinOneSecond() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)  // its clock never moves
        let original = DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)])
        try await installer.install(original)
        try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 2560, height: 1440)]))
        try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 3840, height: 2160)]))
        let folder = installer.locations.backupRoot.appending(path: key.vendorDirectoryName)
        let backups = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
        #expect(backups == ["DisplayProductID-3401-20260921-141320-2.plist", "DisplayProductID-3401-20260921-141320.plist"])
        let first = try DisplayOverride(key: key, propertyList: Data(contentsOf: folder.appending(path: backups[1])))
        #expect(first.resolutions == original.resolutions)
    }

    @Test func removesTheOverrideAndItsEmptyFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let url = try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)]))
        try await installer.remove(key)
        #expect(!exists(url))
        #expect(!exists(url.deletingLastPathComponent()))
        let folder = installer.locations.backupRoot.appending(path: key.vendorDirectoryName)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
            == ["DisplayProductID-3401-20260921-141320.plist"])
    }

    @Test func removingAMissingOverrideSucceeds() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await installer(at: root).remove(key)
    }

    @Test func reportsFailuresFromTheScript() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        // A file where the vendor folder belongs makes the script fail.
        try FileManager.default.createDirectory(at: installer.locations.userRoot, withIntermediateDirectories: true)
        try Data().write(to: installer.locations.userRoot.appending(path: key.vendorDirectoryName))
        await #expect(throws: ResoluteError.self) {
            try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)]))
        }
    }

    @Test func buildsTheScriptItDescribes() {
        let script = OverrideInstaller.installScript(
            contents: Data("hi".utf8),
            destination: URL(filePath: "/L/DisplayVendorID-1/DisplayProductID-2"),
            backup: URL(filePath: "/B/DisplayVendorID-1/DisplayProductID-2-x.plist")
        )
        #expect(script == "set -e; umask 022; "
            + "if [ -f '/L/DisplayVendorID-1/DisplayProductID-2' ]; then mkdir -p '/B/DisplayVendorID-1/'; "
            + "cp -p '/L/DisplayVendorID-1/DisplayProductID-2' '/B/DisplayVendorID-1/DisplayProductID-2-x.plist'; fi; "
            + "mkdir -p '/L/DisplayVendorID-1/'; "
            + "incoming=$(mktemp '/L/DisplayVendorID-1/.resolute.XXXXXX'); "
            + "trap 'rm -f \"$incoming\"' EXIT; "
            + "printf '%s' 'aGk=' | /usr/bin/base64 -D > \"$incoming\"; "
            + "chmod 644 \"$incoming\"; "
            + "mv -f \"$incoming\" '/L/DisplayVendorID-1/DisplayProductID-2'")
        #expect(OverrideInstaller.timestamp(fixedDate) == "20260921-141320")
    }
}

@Suite struct CommandRunnerTests {
    /// Twice as many waiting commands as the Mac has cores: if each held one of the Swift
    /// concurrency pool's threads, as a pending password prompt would, no other task could
    /// run until they finished.
    @Test func waitsWithoutHoldingTheConcurrencyPool() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let release = root.appending(path: "release").path(percentEncoded: false)
        // Released after two seconds whatever happens, so a failure cannot hang the run. A
        // thread of its own: with the pool's threads blocked, GCD's queues starve too.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 2)
            FileManager.default.createFile(atPath: release, contents: nil)
        }
        let started = ContinuousClock.now
        let script = "while [ ! -e \(Shell.quote(release)) ]; do sleep 0.05; done"
        let commands = (0..<(ProcessInfo.processInfo.activeProcessorCount * 2)).map { _ in
            Task { try await ShellCommandRunner().run(script) }
        }
        try await Task.sleep(for: .milliseconds(300))
        let probed = await Task { ContinuousClock.now }.value
        for command in commands { try await command.value }
        #expect(probed - started < .seconds(1.5))
    }
}

@Suite struct QuotingTests {
    @Test func quotesForTheShell() {
        #expect(Shell.quote("it's here") == #"'it'\''s here'"#)
    }

    @Test func escapesForAppleScript() {
        #expect(AppleScript.doShellScript(#"echo "hi" \ there"#, withAdministratorPrivileges: true)
            == #"do shell script "echo \"hi\" \\ there" with administrator privileges"#)
        #expect(AppleScript.doShellScript("ls", withAdministratorPrivileges: false) == #"do shell script "ls""#)
    }

    @Test func recognisesOnlyTheCancelledPrompt() {
        #expect(AdminCommandRunner.isCancellation("0:25: execution error: User canceled. (-128)"))
        #expect(AdminCommandRunner.isCancellation("execution error: User canceled. (-128)\n"))
        #expect(!AdminCommandRunner.isCancellation("mv: /L/x: No space left (-1280 bytes)"))
        #expect(!AdminCommandRunner.isCancellation("execution error: rm failed with -128 files (-2700)"))
        #expect(!AdminCommandRunner.isCancellation("execution error: The command exited with a non-zero status. (-12800)"))
    }

    @Test func survivesARealAppleScriptRoundTrip() throws {
        // Runs osascript without administrator rights, so no password prompt appears.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appending(path: #"it's "done""#)
        let script = "touch \(Shell.quote(marker.path(percentEncoded: false)))"
        try Subprocess.runAndWait("/usr/bin/osascript", arguments: ["-e", AppleScript.doShellScript(script, withAdministratorPrivileges: false)])
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }
}

@Suite struct OverrideDraftTests {
    let key = OverrideKey(vendorID: 1, productID: 2)

    @Test func tracksChangesAndReverts() throws {
        var draft = OverrideDraft(DisplayOverride(key: key))
        #expect(!draft.hasChanges)
        try draft.add(.hiDPI(width: 1600, height: 900, flags: .standard))
        #expect(draft.hasChanges)
        draft.revert()
        #expect(!draft.hasChanges)
        #expect(draft.working.resolutions.isEmpty)
        try draft.add(.standard(width: 2560, height: 1080))
        draft.markSaved()
        #expect(!draft.hasChanges)
        #expect(draft.saved.resolutions.count == 1)
    }

    @Test func rejectsDuplicatesAndNonsense() throws {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [.hiDPI(width: 1600, height: 900, flags: .standard)]))
        #expect(throws: ResoluteError.invalidEntry("1600 × 900 (HiDPI) is already in the list.")) {
            try draft.add(.hiDPI(width: 1600, height: 900, flags: HiDPIFlags(primary: 1, secondary: 0)))
        }
        #expect(throws: ResoluteError.self) { try draft.add(.hiDPI(width: 9_000, height: 900, flags: .standard)) }
        #expect(throws: ResoluteError.self) { try draft.add(.standard(width: 100, height: 100)) }
        #expect(throws: ResoluteError.invalidEntry("HiDPI flags need bit 0 of the first word set.")) {
            try draft.add(.hiDPI(width: 1280, height: 720, flags: HiDPIFlags(primary: 8, secondary: 0)))
        }
        try draft.add(.standard(width: 1600, height: 900))  // same size at 1× is a different mode
        #expect(draft.working.resolutions.count == 2)
    }

    @Test func rejectsSizesTooLargeToDouble() {
        var draft = OverrideDraft(DisplayOverride(key: key))
        #expect(throws: ResoluteError.invalidEntry("HiDPI resolutions must be between 320 × 200 and 8192 × 8192.")) {
            try draft.add(.hiDPI(width: Int.max / 2 + 1, height: 1080, flags: .standard))
        }
        #expect(throws: ResoluteError.invalidEntry("HiDPI resolutions must be between 320 × 200 and 8192 × 8192.")) {
            try draft.add(.hiDPI(width: 1920, height: Int.max, flags: .standard))
        }
    }

    @Test func refusesA1xEntryThatAHiDPIEntryAlreadyWrites() {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [.hiDPI(width: 1280, height: 720, flags: .standard)]))
        let expected = ResoluteError.invalidEntry(
            "2560 × 1440 (1×) is already there: it is written with the HiDPI entry 1280 × 720."
        )
        #expect(throws: expected) {
            try draft.add(.standard(width: 2560, height: 1440))
        }
    }

    @Test func foldsA1xEntryIntoTheHiDPIEntryThatNowWritesIt() throws {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [
            .standard(width: 2560, height: 1440), .standard(width: 1920, height: 1080),
        ]))
        let folded = try draft.add(.hiDPI(width: 1280, height: 720, flags: .standard))
        #expect(folded == [.standard(width: 2560, height: 1440)])
        #expect(draft.working.resolutions == [
            .standard(width: 1920, height: 1080), .hiDPI(width: 1280, height: 720, flags: .standard),
        ])
    }

    @Test func listsWhatAReloadWouldList() throws {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [.standard(width: 2560, height: 1440)]))
        try draft.add(.hiDPI(width: 1280, height: 720, flags: .standard))
        try draft.add(.standard(width: 1920, height: 1080))
        #expect(throws: ResoluteError.self) { try draft.add(.standard(width: 2560, height: 1440)) }
        let reloaded = try DisplayOverride(key: key, propertyList: draft.working.propertyListData())
        #expect(Set(reloaded.resolutions) == Set(draft.working.resolutions))
    }

    @Test func removesByOffsets() {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [
            .standard(width: 1920, height: 1080), .standard(width: 2560, height: 1440), .standard(width: 3840, height: 2160),
        ]))
        draft.remove(atOffsets: IndexSet([0, 2, 7]))
        #expect(draft.working.resolutions == [.standard(width: 2560, height: 1440)])
    }
}
