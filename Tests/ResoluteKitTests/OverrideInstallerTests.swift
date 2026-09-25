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
        let backup = installer.locations.backupRoot
            .appending(path: "DisplayVendorID-db4/DisplayProductID-3401-20260921-141320.plist")
        #expect(!exists(backup))
        try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 2560, height: 1440)]))
        #expect(exists(backup))
        let saved = try DisplayOverride(key: key, propertyList: Data(contentsOf: backup))
        #expect(saved.resolutions == [.standard(width: 1920, height: 1080)])
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

    @Test func keepsEveryBackupWhenInstallsOverlap() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)  // its clock never moves
        let key = key
        try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: 1920, height: 1080)]))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for width in [2000, 2100, 2200, 2300, 2400] {
                group.addTask {
                    try await installer.install(DisplayOverride(key: key, resolutions: [.standard(width: width, height: 1200)]))
                }
            }
            try await group.waitForAll()
        }
        let folder = installer.locations.backupRoot.appending(path: key.vendorDirectoryName)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).count == 5)
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
            backupStem: URL(filePath: "/B/DisplayVendorID-1/DisplayProductID-2-x")
        )
        #expect(script == "set -e; umask 022; "
            + "if [ -f '/L/DisplayVendorID-1/DisplayProductID-2' ]; then mkdir -p '/B/DisplayVendorID-1/'; "
            + "n=1; backup='/B/DisplayVendorID-1/DisplayProductID-2-x'.plist; "
            + "while ! (set -C; : > \"$backup\") 2>/dev/null; do n=$((n + 1)); [ \"$n\" -le 1000 ]; "
            + "backup='/B/DisplayVendorID-1/DisplayProductID-2-x'-$n.plist; done; "
            + "cp -p '/L/DisplayVendorID-1/DisplayProductID-2' \"$backup\"; fi; "
            + "mkdir -p '/L/DisplayVendorID-1/'; "
            + "incoming=$(mktemp '/L/DisplayVendorID-1/.resolute.XXXXXX'); "
            + "trap 'rm -f \"$incoming\"' EXIT; "
            + "printf '%s' 'aGk=' | /usr/bin/base64 -D > \"$incoming\"; "
            + "chmod 644 \"$incoming\"; "
            + "mv -f \"$incoming\" '/L/DisplayVendorID-1/DisplayProductID-2'")
        #expect(OverrideInstaller.timestamp(fixedDate) == "20260921-141320")
    }
}

/// Records the order things happen in.
actor EventLog {
    private(set) var events: [String] = []

    func add(_ event: String) {
        events.append(event)
    }
}

@Suite struct OverrideLockTests {
    @Test func letsOneEditRunAtATime() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lock = OverrideLock(file: root.appending(path: "Resolute/overrides.lock"))
        let log = EventLog()
        async let first: Void = lock.withLock {
            await log.add("first in")
            try? await Task.sleep(for: .milliseconds(300))
            await log.add("first out")
        }
        try await Task.sleep(for: .milliseconds(50))
        async let second: Void = lock.withLock {
            await log.add("second in")
            await log.add("second out")
        }
        _ = await (first, second)
        #expect(await log.events == ["first in", "first out", "second in", "second out"])
    }

    @Test func sitsBesideTheBackups() {
        #expect(OverrideLocations.standard.lockFile.path(percentEncoded: false)
            == "/Library/Application Support/Resolute/overrides.lock")
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

    @Test func namesResoluteInThePasswordPrompt() throws {
        let source = AppleScript.doShellScript("true", withAdministratorPrivileges: true, prompt: #"Resolute wants "this"."#)
        #expect(source == #"do shell script "true" with prompt "Resolute wants \"this\"." with administrator privileges"#)
        #expect(AdminCommandRunner().prompt == "Resolute wants to change a display override in /Library/Displays.")
        // Compiled but not run, so no password prompt appears.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let compiled = root.appending(path: "check.scpt").path(percentEncoded: false)
        let privileged = AppleScript.doShellScript("true", withAdministratorPrivileges: true, prompt: AdminCommandRunner().prompt)
        try Subprocess.runAndWait("/usr/bin/osacompile", arguments: ["-o", compiled, "-e", privileged])
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

    @Test func addsTheOneTimesEntryAHiDPIEntryIsPairedWith() throws {
        var draft = OverrideDraft(DisplayOverride(key: key))
        let alsoAdded = try draft.add(.hiDPI(width: 1280, height: 720, flags: .standard))
        #expect(alsoAdded == [.standard(width: 2560, height: 1440)])
        #expect(draft.working.resolutions == [
            .standard(width: 2560, height: 1440), .hiDPI(width: 1280, height: 720, flags: .standard),
        ])
    }

    @Test func pairsANewHiDPIEntryWithAnExistingOneTimesEntry() throws {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [.standard(width: 2560, height: 1440)]))
        #expect(try draft.add(.hiDPI(width: 1280, height: 720, flags: .standard)).isEmpty)
        #expect(draft.working.resolutions == [
            .standard(width: 2560, height: 1440), .hiDPI(width: 1280, height: 720, flags: .standard),
        ])
    }

    @Test func removesTheOneTimesEntryItAddedWithAHiDPIEntry() throws {
        var draft = OverrideDraft(DisplayOverride(key: key))
        try draft.add(.hiDPI(width: 1280, height: 720, flags: .standard))
        draft.remove([.hiDPI(width: 1280, height: 720, flags: .standard)])
        #expect(draft.working.resolutions.isEmpty)
        #expect(!draft.hasChanges)
    }

    /// Apple's file for the built-in panel lists its native size at 1×. A HiDPI entry added
    /// and removed again must leave that entry alone, in one session or across two.
    @Test func neverRemovesAOneTimesEntryItDidNotAdd() throws {
        let native = ScaleResolution.standard(width: 3456, height: 2234)
        let hiDPI = ScaleResolution.hiDPI(width: 1728, height: 1117, flags: .standard)
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [native]))
        try draft.add(hiDPI)
        draft.remove([hiDPI])
        #expect(draft.working.resolutions == [native])

        try draft.add(hiDPI)
        var reopened = OverrideDraft(try DisplayOverride(key: key, propertyList: draft.working.propertyListData()))
        reopened.remove([hiDPI])
        #expect(reopened.working.resolutions == [native])
    }

    @Test func forgetsAPairingOnceTheOneTimesEntryIsRemovedByHand() throws {
        let hiDPI = ScaleResolution.hiDPI(width: 1280, height: 720, flags: .standard)
        let oneTimes = ScaleResolution.standard(width: 2560, height: 1440)
        var draft = OverrideDraft(DisplayOverride(key: key))
        try draft.add(hiDPI)
        draft.remove([oneTimes])
        try draft.add(oneTimes)  // now the person's own entry
        draft.remove([hiDPI])
        #expect(draft.working.resolutions == [oneTimes])
    }

    @Test func listsWhatReopeningTheFileWouldList() throws {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [.standard(width: 2560, height: 1440)]))
        try draft.add(.hiDPI(width: 1280, height: 720, flags: .standard))
        try draft.add(.hiDPI(width: 1600, height: 900, flags: .standard))
        try draft.add(.standard(width: 1920, height: 1080))
        #expect(throws: ResoluteError.self) { try draft.add(.standard(width: 2560, height: 1440)) }
        let reopened = try DisplayOverride(key: key, propertyList: draft.working.propertyListData())
        #expect(reopened.resolutions == draft.working.resolutions)
    }

    @Test func knowsAModeAppleWroteInItsOwnFormat() throws {
        let apple = ScaleResolution.preserved(.data(hexData("00000a00 00000640 00000001")))
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [apple]))
        #expect(throws: ResoluteError.invalidEntry("1280 × 800 (HiDPI) is already in the list.")) {
            try draft.add(.hiDPI(width: 1280, height: 800, flags: .standard))
        }
        // Its 1× partner size is not listed, so adding the 1× entry by hand still works.
        try draft.add(.standard(width: 2560, height: 1600))
    }

    @Test func removesTheGivenEntries() {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [
            .standard(width: 1920, height: 1080), .standard(width: 2560, height: 1440), .standard(width: 3840, height: 2160),
        ]))
        draft.remove([.standard(width: 1920, height: 1080), .standard(width: 3840, height: 2160), .standard(width: 1, height: 1)])
        #expect(draft.working.resolutions == [.standard(width: 2560, height: 1440)])
    }
}
