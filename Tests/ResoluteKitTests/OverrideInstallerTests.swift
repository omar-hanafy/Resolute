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
            staging: URL(filePath: "/tmp/a b.plist"),
            destination: URL(filePath: "/L/DisplayVendorID-1/DisplayProductID-2"),
            backup: URL(filePath: "/B/DisplayVendorID-1/DisplayProductID-2-x.plist")
        )
        #expect(script == "set -e; "
            + "if [ -f '/L/DisplayVendorID-1/DisplayProductID-2' ]; then mkdir -p '/B/DisplayVendorID-1/'; "
            + "cp -p '/L/DisplayVendorID-1/DisplayProductID-2' '/B/DisplayVendorID-1/DisplayProductID-2-x.plist'; fi; "
            + "mkdir -p '/L/DisplayVendorID-1/'; "
            + "cp '/tmp/a b.plist' '/L/DisplayVendorID-1/DisplayProductID-2'; "
            + "chmod 644 '/L/DisplayVendorID-1/DisplayProductID-2'")
        #expect(OverrideInstaller.timestamp(fixedDate) == "20260921-141320")
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

    @Test func survivesARealAppleScriptRoundTrip() throws {
        // Runs osascript without administrator rights, so no password prompt appears.
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appending(path: #"it's "done""#)
        let script = "touch \(Shell.quote(marker.path(percentEncoded: false)))"
        try Subprocess.run("/usr/bin/osascript", arguments: ["-e", AppleScript.doShellScript(script, withAdministratorPrivileges: false)])
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

    @Test func removesByOffsets() {
        var draft = OverrideDraft(DisplayOverride(key: key, resolutions: [
            .standard(width: 1920, height: 1080), .standard(width: 2560, height: 1440), .standard(width: 3840, height: 2160),
        ]))
        draft.remove(atOffsets: IndexSet([0, 2, 7]))
        #expect(draft.working.resolutions == [.standard(width: 2560, height: 1440)])
    }
}
