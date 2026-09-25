import Foundation
import Testing
@testable import ResoluteKit

/// Edits that start from a file read earlier: the app reads an override, someone edits
/// it for a while, and meanwhile `resolute` or another tool may change the same file.
@Suite struct OverrideConflictTests {
    let key = OverrideKey(vendorID: 0xDB4, productID: 0x3401)
    let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

    func installer(at root: URL) -> OverrideInstaller {
        let date = fixedDate
        return OverrideInstaller(locations: .staged(at: root), runner: ShellCommandRunner(), now: { date })
    }

    func override(_ width: Int) -> DisplayOverride {
        DisplayOverride(key: key, resolutions: [.standard(width: width, height: 1200)])
    }

    func backupCount(_ installer: OverrideInstaller) -> Int {
        let folder = installer.locations.backupRoot.appending(path: key.vendorDirectoryName)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).count
    }

    @Test func remembersWhatTheInstalledFileHeldWhenItWasRead() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        #expect(try store.editableFile(for: key).installedState == .absent)
        #expect(try store.installedState(for: key) == .absent)

        let url = store.locations.userFile(for: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(rdmOverrideXML.utf8).write(to: url)
        let file = try store.editableFile(for: key)
        #expect(file.source == .installed)
        #expect(file.installedState == .contents(Data(rdmOverrideXML.utf8)))
        #expect(file.override.resolutions.count == 2)
        #expect(try store.installedState(for: key) == file.installedState)
    }

    @Test func replacesAFileThatDidNotChange() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let store = OverrideStore(locations: installer.locations)
        try await installer.install(override(1920), expecting: .absent)
        try await installer.install(override(2560), expecting: try store.installedState(for: key))
        #expect(try store.installedOverride(for: key) == override(2560).readBack())
    }

    @Test func refusesToReplaceAFileThatChangedSinceItWasRead() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let store = OverrideStore(locations: installer.locations)
        let url = try await installer.install(override(1920))
        let read = try store.installedState(for: key)
        try override(2560).propertyListData().write(to: url)  // another tool's edit
        let backups = backupCount(installer)

        await #expect(throws: ResoluteError.overrideChanged(path: url.path(percentEncoded: false))) {
            try await installer.install(override(3840), expecting: read)
        }
        #expect(try store.installedOverride(for: key)?.resolutions == override(2560).resolutions)
        #expect(backupCount(installer) == backups)
    }

    @Test func refusesToCreateAFileThatAppearedSinceItWasRead() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        try await installer.install(override(1920))
        await #expect(throws: ResoluteError.self) {
            try await installer.install(override(3840), expecting: .absent)
        }
        #expect(try OverrideStore(locations: installer.locations).installedOverride(for: key)?.resolutions == override(1920).resolutions)
    }

    @Test func refusesToRemoveAFileThatChangedSinceItWasRead() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let store = OverrideStore(locations: installer.locations)
        let url = try await installer.install(override(1920))
        let read = try store.installedState(for: key)
        try override(2560).propertyListData().write(to: url)
        await #expect(throws: ResoluteError.overrideChanged(path: url.path(percentEncoded: false))) {
            try await installer.remove(key, expecting: read)
        }
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        try await installer.remove(key, expecting: try store.installedState(for: key))
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    /// An override kept elsewhere and linked into place reads through the link, and so
    /// does the check; the link is replaced by the new file, as before.
    @Test func replacesALinkedOverrideThatDidNotChange() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let store = OverrideStore(locations: installer.locations)
        let kept = root.appending(path: "dotfiles-override.plist")
        try override(1920).propertyListData().write(to: kept)
        let url = installer.locations.userFile(for: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: kept)
        try await installer.install(override(2560), expecting: try store.installedState(for: key))
        #expect(try store.installedOverride(for: key)?.resolutions == override(2560).resolutions)
    }

    /// A link to a file that is gone is no override, to macOS and to Resolute: an edit that
    /// read it as absent replaces the link itself, and never creates the file it points to.
    @Test func replacesALinkToAFileThatIsGone() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let store = OverrideStore(locations: installer.locations)
        let gone = root.appending(path: "gone.plist")
        let url = installer.locations.userFile(for: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: gone)
        let read = try store.installedState(for: key)
        #expect(read == .absent)

        try await installer.install(override(2560), expecting: read)
        #expect(try store.installedOverride(for: key)?.resolutions == override(2560).resolutions)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: url.path(percentEncoded: false))) == nil)
        #expect(!FileManager.default.fileExists(atPath: gone.path(percentEncoded: false)))
        #expect(backupCount(installer) == 0)
    }

    /// The app cannot hold the lock itself (the lock file lives where only root may create
    /// it), so its scripts take the same lock the command line holds.
    @Test func takesTheCommandLinesLockInsideTheScript() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var installer = installer(at: root)
        let lockFile = installer.locations.lockFile
        installer.scriptLock = lockFile
        let log = EventLog()
        async let holder: Void = OverrideLock(file: lockFile).withLock {
            await log.add("held")
            try? await Task.sleep(for: .milliseconds(600))
            await log.add("released")
        }
        await log.waitFor("held")
        try await installer.install(override(1920))
        await log.add("installed")
        try await holder
        #expect(await log.events == ["held", "released", "installed"])
    }

    @Test func givesUpWhenAnotherEditHoldsTheLockTooLong() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var installer = installer(at: root)
        let lockFile = installer.locations.lockFile
        installer.scriptLock = lockFile
        installer.scriptLockTimeout = 1
        let log = EventLog()
        async let holder: Void = OverrideLock(file: lockFile).withLock {
            await log.add("held")
            try? await Task.sleep(for: .seconds(3))
        }
        await log.waitFor("held")
        await #expect(throws: ResoluteError.overridesBusy) {
            try await installer.install(override(1920))
        }
        try await holder
        #expect(try OverrideStore(locations: installer.locations).installedOverride(for: key) == nil)
    }

    /// The app's path: osascript runs lockf, which runs the quoted script. Without
    /// administrator rights here, so no password prompt appears.
    @Test func installsThroughAppleScriptUnderTheScriptLock() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = fixedDate
        var installer = OverrideInstaller(
            locations: .staged(at: root), runner: AdminCommandRunner(prompt: "unused", withAdministratorPrivileges: false),
            now: { date }
        )
        installer.scriptLock = installer.locations.lockFile
        let named = DisplayOverride(key: key, productName: "Studio's \"27\"", resolutions: [.standard(width: 1920, height: 1200)])
        try await installer.install(named, expecting: .absent)
        let store = OverrideStore(locations: installer.locations)
        #expect(try store.installedOverride(for: key)?.productName == "Studio's \"27\"")
        try await installer.remove(key, expecting: try store.installedState(for: key))
        #expect(try store.installedOverride(for: key) == nil)
        #expect(FileManager.default.fileExists(atPath: installer.locations.lockFile.path(percentEncoded: false)))
    }

    /// osascript reports a failed script as "0:47: execution error: <message> (<status>)"
    /// and exits with 1, which would hide the status the installer acts on.
    @Test func readsTheStatusAndMessageOsascriptReports() {
        #expect(AppleScript.executionError(in: "0:47: execution error: it broke (3)")
            == AppleScript.ExecutionError(message: "it broke", status: 3))
        #expect(AppleScript.executionError(in: "12:345: execution error: lockf: /x: already locked (75)\n")
            == AppleScript.ExecutionError(message: "lockf: /x: already locked", status: 75))
        #expect(AppleScript.executionError(in: "0:24: execution error: User canceled. (-128)")
            == AppleScript.ExecutionError(message: "User canceled.", status: -128))
        #expect(AppleScript.executionError(in: "something else entirely") == nil)
    }

    @Test func reportsAScriptFailureWithItsOwnStatusAndMessage() async {
        // Without administrator rights, so no password prompt appears.
        let runner = AdminCommandRunner(prompt: "unused", withAdministratorPrivileges: false)
        await #expect(throws: ResoluteError.commandFailed(status: 3, message: "it broke")) {
            try await runner.run("echo 'it broke' >&2; exit 3")
        }
    }

    @Test func detectsAChangedFileThroughAppleScript() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = fixedDate
        let installer = OverrideInstaller(
            locations: .staged(at: root), runner: AdminCommandRunner(prompt: "unused", withAdministratorPrivileges: false),
            now: { date }
        )
        let url = try await installer.install(override(1920))
        await #expect(throws: ResoluteError.overrideChanged(path: url.path(percentEncoded: false))) {
            try await installer.install(override(2560), expecting: .absent)
        }
    }
}

@Suite struct OverrideBackupTests {
    let key = OverrideKey(vendorID: 0xDB4, productID: 0x3401)

    /// An installer whose clock moves one minute per install, starting at `start`.
    func installer(at root: URL, start: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> OverrideInstaller {
        let clock = Clock(start)
        return OverrideInstaller(locations: .staged(at: root), runner: ShellCommandRunner(), now: { clock.tick() })
    }

    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var next: Date
        init(_ start: Date) { next = start }
        func tick() -> Date {
            lock.withLock {
                defer { next += 60 }
                return next
            }
        }
    }

    func override(_ width: Int) -> DisplayOverride {
        DisplayOverride(key: key, resolutions: [.standard(width: width, height: 1200)])
    }

    @Test func listsBackupsNewestFirst() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        for width in [1600, 1920, 2560, 3840] {
            try await installer.install(override(width))
        }
        let store = OverrideStore(locations: installer.locations)
        let backups = store.backups(for: key)
        // The first install replaced nothing; each later one backed up the one before it.
        #expect(backups.map(\.fileName) == [
            "DisplayProductID-3401-20260921-141620.plist",
            "DisplayProductID-3401-20260921-141520.plist",
            "DisplayProductID-3401-20260921-141420.plist",
        ])
        #expect(backups.first?.date == Date(timeIntervalSince1970: 1_790_000_180))
        #expect(try store.contents(of: backups[0]).override.resolutions == override(2560).resolutions)
        #expect(try store.contents(of: backups[2]).override.resolutions == override(1600).resolutions)
        #expect(store.backupKeys() == [key])
    }

    @Test func ordersBackupsMadeInTheSameSecond() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let installer = OverrideInstaller(locations: .staged(at: root), runner: ShellCommandRunner(), now: { date })
        for width in [1600, 1920, 2560, 3840] {
            try await installer.install(override(width))
        }
        let backups = OverrideStore(locations: installer.locations).backups(for: key)
        #expect(backups.map(\.sequence) == [3, 2, 1])
        #expect(backups.map(\.fileName).last == "DisplayProductID-3401-20260921-141320.plist")
    }

    @Test func ignoresFilesThatAreNotBackups() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = OverrideLocations.staged(at: root)
        let folder = locations.backupRoot.appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in [
            ".DS_Store", "DisplayProductID-3401-garbage.plist", "DisplayProductID-34010-20260921-141320.plist",
            "DisplayProductID-3401-20260921-141320.txt", "DisplayProductID-3401-20261321-141320.plist",
            "DisplayProductID-3401-20260921-141320-0.plist", "DisplayProductID-3401-20260921-141320-x.plist",
        ] {
            try Data().write(to: folder.appending(path: name))
        }
        try Data().write(to: folder.appending(path: "DisplayProductID-3401-20260921-141320-2.plist"))
        let store = OverrideStore(locations: locations)
        #expect(store.backups(for: key).map(\.fileName) == ["DisplayProductID-3401-20260921-141320-2.plist"])
        #expect(store.backups(for: OverrideKey(vendorID: 0x610, productID: 0xA050)).isEmpty)
    }

    @Test func saysWhyABackupCannotBeRead() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = OverrideLocations.staged(at: root)
        let folder = locations.backupRoot.appending(path: key.vendorDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "DisplayProductID-3401-20260921-141320.plist")
        try Data("not a plist".utf8).write(to: file)
        let store = OverrideStore(locations: locations)
        let backup = try #require(store.backups(for: key).first)
        #expect(throws: ResoluteError.overrideUnreadable(path: file.path(percentEncoded: false), reason: "it is not a valid property list")) {
            try store.contents(of: backup)
        }
    }

    /// A restore writes the backup's bytes as they are, and backs up what it replaces.
    @Test func restoresABackupByteForByte() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let store = OverrideStore(locations: installer.locations)
        let url = installer.locations.userFile(for: key)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(rdmOverrideXML.utf8).write(to: url)
        try await installer.install(override(1920))
        let backup = try #require(store.backups(for: key).first)
        let (_, data) = try store.contents(of: backup)

        try await installer.install(contents: data, for: key, expecting: try store.installedState(for: key))
        #expect(try Data(contentsOf: url) == Data(rdmOverrideXML.utf8))
        #expect(store.backups(for: key).count == 2)
        #expect(try store.contents(of: store.backups(for: key)[0]).override.resolutions == override(1920).resolutions)
    }

    @Test func prunesTheBackupsItIsGiven() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        for width in [1600, 1920, 2560, 3840, 4096] {
            try await installer.install(override(width))
        }
        let store = OverrideStore(locations: installer.locations)
        let backups = store.backups(for: key)
        try await installer.removeBackups(Array(backups.dropFirst(2)))
        #expect(store.backups(for: key) == Array(backups.prefix(2)))

        try await installer.removeBackups(store.backups(for: key))
        let folder = installer.locations.backupRoot.appending(path: key.vendorDirectoryName)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        #expect(store.backupKeys().isEmpty)
    }

    @Test func removesOnlyFilesInsideTheBackupFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = installer(at: root)
        let outside = root.appending(path: "DisplayProductID-3401-20260921-141320.plist")
        try Data().write(to: outside)
        let stray = OverrideBackup(key: key, file: outside, date: Date(timeIntervalSince1970: 1_790_000_000), sequence: 1)
        await #expect(throws: ResoluteError.self) { try await installer.removeBackups([stray]) }
        #expect(FileManager.default.fileExists(atPath: outside.path(percentEncoded: false)))
    }
}

extension DisplayOverride {
    /// This override as reading its file back gives it.
    func readBack() throws -> DisplayOverride {
        try DisplayOverride(key: key, propertyList: propertyListData())
    }
}
