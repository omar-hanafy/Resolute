import Foundation
import OSLog
import Testing
@testable import ResoluteKit

/// Every change to an override is logged, so a bug report can say what Resolute wrote:
/// `log show --predicate 'subsystem == "com.omarhanafy.Resolute"' --info --last 1h`.
@Suite struct OverrideLoggingTests {
    let key = OverrideKey(vendorID: 0xDB4, productID: 0x3401)

    func override(_ width: Int) -> DisplayOverride {
        DisplayOverride(key: key, resolutions: [.standard(width: width, height: 1200)])
    }

    /// What this process logged about overrides since `start`. Other tests log too, so
    /// callers look for their own paths.
    func overrideLog(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@", ResoluteLog.subsystem, "overrides")
        return try store.getEntries(at: store.position(date: start), matching: predicate)
            .compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
    }

    @Test func logsWhatEachChangeWroteOrWhyItDidNot() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let installer = OverrideInstaller(locations: .staged(at: root), runner: ShellCommandRunner())
        let start = Date().addingTimeInterval(-1)

        let url = try await installer.install(override(1920))
        let path = url.path(percentEncoded: false)
        let size = try override(1920).propertyListData().count
        await #expect(throws: ResoluteError.overrideChanged(path: path)) {
            try await installer.install(override(2560), expecting: .absent)
        }
        try await installer.remove(key)
        let backups = OverrideStore(locations: installer.locations).backups(for: key)
        try await installer.removeBackups(backups)

        let log = try overrideLog(since: start)
        #expect(log.contains("Wrote \(path), \(size) bytes"))
        #expect(log.contains("Did not write \(path): \(ResoluteError.overrideChanged(path: path).localizedDescription)"))
        #expect(log.contains("Removed \(path)"))
        #expect(backups.count == 1)
        let folder = installer.locations.backupFolder(for: key).path(percentEncoded: false)
        #expect(log.contains("Removed 1 backup from \(folder.hasSuffix("/") ? String(folder.dropLast()) : folder)"))
    }
}
