import Foundation
import Testing
@testable import ResoluteKit

/// Every override file macOS ships, read and written back: the ground truth for the
/// override format, checked again on each new macOS release.
@Suite struct ShippedOverrideTests {
    static let root = OverrideLocations.standard.systemRoot

    /// The files macOS ships, with the keys their names give.
    static func shippedFiles() -> [(key: OverrideKey, url: URL)] {
        let fileManager = FileManager.default
        let vendors = (try? fileManager.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        return vendors.flatMap { vendor -> [(key: OverrideKey, url: URL)] in
            let folder = root.appending(path: vendor, directoryHint: .isDirectory)
            let products = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            return products.compactMap { product in
                OverrideKey(vendorDirectory: vendor, productFile: product).map { ($0, folder.appending(path: product)) }
            }
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: root.path(percentEncoded: false)), "no override files on this system"))
    func writesBackEveryFileMacOSShipsUnchanged() throws {
        var checked = 0, withResolutions = 0, lists = 0
        for (key, url) in Self.shippedFiles() {
            let data = try Data(contentsOf: url)
            let override: DisplayOverride
            do {
                override = try DisplayOverride(key: key, propertyList: data)
            } catch ResoluteError.overrideUnreadable(_, let reason) where reason.hasPrefix("it holds several overrides") {
                lists += 1
                continue
            }
            let original = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary)
            let written = try #require(
                try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? NSDictionary
            )
            var expected = original as? [String: Any] ?? [:]
            // An empty name blanks the display's name in macOS, so Resolute leaves it out.
            if expected[DisplayOverride.productNameKey] as? String == "" { expected[DisplayOverride.productNameKey] = nil }
            #expect(written.isEqual(to: expected), "\(key.relativePath)")
            checked += 1
            if original[DisplayOverride.resolutionsKey] != nil { withResolutions += 1 }
        }
        // macOS 27 ships 451 files: 449 dictionaries, 251 of them with resolutions, and 2 lists.
        #expect(checked > 100)
        #expect(withResolutions > 50)
        #expect(lists <= 5)
    }
}
