import Foundation
import Testing
@testable import ResoluteKit

@Suite struct ScaleResolutionCodecTests {
    let rdmKey = OverrideKey(vendorID: 0xDB4, productID: 0x3401)

    @Test func decodesTheRDMOverride() throws {
        let override = try DisplayOverride(key: rdmKey, propertyList: Data(rdmOverrideXML.utf8))
        #expect(override.productName == nil)
        #expect(override.resolutions == [
            .standard(width: 5120, height: 2160),
            .hiDPI(width: 2560, height: 1080, flags: HiDPIFlags(primary: 0xB, secondary: 0x00A0_0000)),
        ])
        #expect(override.otherKeys.keys == ["target-default-ppmm"])
    }

    @Test func writesTheRDMOverrideBackUnchanged() throws {
        let original = try #require(
            try PropertyListSerialization.propertyList(from: Data(rdmOverrideXML.utf8), format: nil) as? [String: Any]
        )
        let override = try DisplayOverride(key: rdmKey, propertyList: Data(rdmOverrideXML.utf8))
        let written = try #require(
            try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? [String: Any]
        )
        #expect(written["scale-resolutions"] as? [Data] == original["scale-resolutions"] as? [Data])
        #expect(written["target-default-ppmm"] as? Double == 10.01)
        // RDM wrote an empty name, which blanks the display's name in macOS; Resolute omits it.
        #expect(written["DisplayProductName"] == nil)
    }

    @Test func keepsEntriesItDoesNotModel() throws {
        let nineBytes = hexData("00000f00 00000960 00")
        let twelveBytes = hexData("00000673 0000041a 00000001")  // odd pixels: no HiDPI mode
        let plainSixteen = hexData("00000780 00000438 00000000 00200000")
        let entries = ScaleResolutionCodec.decode([nineBytes, twelveBytes, plainSixteen, 32_768_800])
        #expect(Array(entries.prefix(3)) == [
            .preserved(.data(nineBytes)), .preserved(.data(twelveBytes)), .preserved(.data(plainSixteen)),
        ])
        guard case .preserved(.value) = entries[3] else {
            Issue.record("expected the number to be preserved")
            return
        }
        #expect(entries.allSatisfy { !$0.isEditable })
        let encoded = ScaleResolutionCodec.encode(entries)
        #expect(encoded.count == 4)
        #expect(encoded[0] as? Data == nineBytes)
        #expect(encoded[1] as? Data == twelveBytes)
        #expect(encoded[2] as? Data == plainSixteen)
        #expect(encoded[3] as? Int == 32_768_800)
    }

    /// A 1× entry at a HiDPI entry's pixel size is listed too: the file cannot say whether
    /// someone added it or it was written to go with the HiDPI entry.
    @Test func listsEveryEntryOneTimesFirst() {
        let hiDPI = hexData("00000a00 00000640 00000001 00200000")
        let pairedOneTimes = hexData("00000a00 00000640")
        let other = hexData("00000780 00000438")
        #expect(ScaleResolutionCodec.decode([hiDPI, other, pairedOneTimes]) == [
            .standard(width: 2560, height: 1600),
            .standard(width: 1920, height: 1080),
            .hiDPI(width: 1280, height: 800, flags: HiDPIFlags(primary: 1, secondary: 0x0020_0000)),
        ])
    }

    /// Apple writes HiDPI modes as 12-byte entries (pixel width, pixel height, flags with
    /// bit 0 for HiDPI). They are kept byte for byte but count as the modes they describe.
    @Test func readsApplesTwelveByteEntriesAsTheModesTheyDescribe() {
        let hiDPI = hexData("00000a00 00000640 00000001")
        let oneTimes = hexData("00000780 000004b0 00000000")
        let entries = ScaleResolutionCodec.decode([hiDPI, oneTimes])
        #expect(entries.map(\.sizeText) == ["1920 × 1200", "1280 × 800"])
        #expect(entries.map(\.kindText) == ["1×", "HiDPI"])
        #expect(entries[1].pixelSize?.width == 2560)
        #expect(entries[1].summary == "1280 × 800 HiDPI (2560 × 1600 px, a 12-byte entry kept as is)")
        #expect(entries.allSatisfy { !$0.isEditable })
        #expect(entries[1].sameMode(as: .hiDPI(width: 1280, height: 800, flags: .standard)))
        #expect(ScaleResolution.standard(width: 1920, height: 1200).sameMode(as: entries[0]))
        #expect(ScaleResolutionCodec.encode(entries).compactMap { $0 as? Data } == [oneTimes, hiDPI])
    }

    @Test func writesExactlyTheListedEntriesOneTimesFirstLargestFirst() {
        let encoded = ScaleResolutionCodec.encode([
            .hiDPI(width: 1280, height: 720, flags: .standard),
            .standard(width: 1920, height: 1080),
            .hiDPI(width: 1920, height: 1080, flags: .standard),
            .standard(width: 2560, height: 1440),
        ]).compactMap { ($0 as? Data).map { $0.map { String(format: "%02x", $0) }.joined() } }
        #expect(encoded == [
            "00000a00000005a0",                  // 2560×1440 at 1×
            "0000078000000438",                  // 1920×1080 at 1×
            "00000f00000008700000000900a00000",  // 1920×1080 HiDPI
            "00000a00000005a00000000900a00000",  // 1280×720 HiDPI
        ])
    }

    @Test(arguments: ["00000009 00a00000", "0x9 0xa00000", "0000000900a00000", "9,a00000"])
    func parsesFlags(text: String) throws {
        #expect(try HiDPIFlags(parsing: text) == .standard)
    }

    @Test(arguments: ["", "zz 00", "1 2 3", "123456789 0"])
    func rejectsBadFlags(text: String) {
        #expect(throws: ResoluteError.invalidFlags(text)) {
            try HiDPIFlags(parsing: text)
        }
    }

    @Test func describesEntries() {
        let entry = ScaleResolution.hiDPI(width: 2560, height: 1080, flags: .standard)
        #expect(entry.sizeText == "2560 × 1080")
        #expect(entry.kindText == "HiDPI")
        #expect(entry.pixelSize?.width == 5120)
        #expect(entry.summary == "2560 × 1080 HiDPI (5120 × 2160 px, flags 00000009 00a00000)")
        #expect(ScaleResolution.standard(width: 1920, height: 1080).summary == "1920 × 1080 1×")
        #expect(entry.sameMode(as: .hiDPI(width: 2560, height: 1080, flags: HiDPIFlags(primary: 1, secondary: 0))))
        #expect(!entry.sameMode(as: .standard(width: 2560, height: 1080)))
    }
}

@Suite struct DisplayOverrideTests {
    let key = OverrideKey(vendorID: 0x10AC, productID: 0xA0C4)

    @Test func preservesKeysItDoesNotEdit() throws {
        let source: [String: Any] = [
            "DisplayProductName": "DELL U2720Q",
            "DisplayVendorID": 4268,
            "IODisplayEDID": Data([0, 255, 255]),
            "scale-resolutions": [hexData("00000780 00000438")],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: source, format: .binary, options: 0)
        var override = try DisplayOverride(key: key, propertyList: data)
        #expect(override.productName == "DELL U2720Q")
        override.resolutions.append(.hiDPI(width: 1600, height: 900, flags: .standard))
        let written = try #require(
            try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? [String: Any]
        )
        #expect(written["DisplayVendorID"] as? Int == 4268)
        #expect(written["IODisplayEDID"] as? Data == Data([0, 255, 255]))
        #expect(written["DisplayProductName"] as? String == "DELL U2720Q")
        #expect((written["scale-resolutions"] as? [Data])?.count == 2)
        // The file had no target density, and a copy must not gain one (see below).
        #expect(written["target-default-ppmm"] == nil)
    }

    /// RDM gave the files it created a target density of 10.01. A file that exists keeps
    /// its own keys: Apple's file for the built-in panel has none, and a density steers
    /// which mode macOS makes the default.
    @Test func addsTheTargetDensityOnlyToNewOverrides() throws {
        func written(_ override: DisplayOverride) throws -> [String: Any] {
            try #require(try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? [String: Any])
        }
        var fresh = DisplayOverride(key: key)
        fresh.resolutions = [.standard(width: 1920, height: 1080)]
        #expect(try written(fresh)["target-default-ppmm"] as? Double == 10.01)

        let apples = try PropertyListSerialization.data(fromPropertyList: [
            "DisplayProductName": "Color LCD", "scale-resolutions": [hexData("00000d80 000008ba")],
        ], format: .xml, options: 0)
        var copy = try DisplayOverride(key: key, propertyList: apples)
        copy.resolutions.append(.hiDPI(width: 1600, height: 900, flags: .standard))
        #expect(try written(copy)["target-default-ppmm"] == nil)
    }

    @Test func writesNothingForAnEmptyOverride() throws {
        let written = try #require(
            try PropertyListSerialization.propertyList(from: DisplayOverride(key: key).propertyListData(), format: nil) as? [String: Any]
        )
        #expect(written.isEmpty)
    }

    @Test func keepsAWrongTypedResolutionsKey() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["scale-resolutions": "garbage"], format: .xml, options: 0)
        let override = try DisplayOverride(key: key, propertyList: data)
        #expect(override.resolutions.isEmpty)
        let written = try #require(
            try PropertyListSerialization.propertyList(from: override.propertyListData(), format: nil) as? [String: Any]
        )
        #expect(written["scale-resolutions"] as? String == "garbage")
    }

    @Test func rejectsFilesThatAreNotDictionaries() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [1, 2], format: .xml, options: 0)
        let expected = ResoluteError.overrideUnreadable(
            path: "DisplayVendorID-10ac/DisplayProductID-a0c4", reason: "the file is not a dictionary"
        )
        #expect(throws: expected) {
            try DisplayOverride(key: key, propertyList: data)
        }
    }

    @Test func namesFilesInLowercaseHex() {
        #expect(key.relativePath == "DisplayVendorID-10ac/DisplayProductID-a0c4")
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-DB4", productFile: "DisplayProductID-3401")
            == OverrideKey(vendorID: 0xDB4, productID: 0x3401))
        #expect(OverrideKey(vendorDirectory: "Icons.plist", productFile: "x") == nil)
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-610", productFile: "DisplayProductID-zz") == nil)
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-610", productFile: "DisplayProductID-a050.plist") == nil)
    }

    /// macOS looks for "DisplayVendorID-ccc", never "DisplayVendorID-0ccc", so a padded name
    /// is a file it does not read, and listing it would point at a path that does not exist.
    @Test func ignoresNamesMacOSDoesNotLookFor() {
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-0ccc", productFile: "DisplayProductID-1") == nil)
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-ccc", productFile: "DisplayProductID-01") == nil)
        #expect(OverrideKey(vendorDirectory: "DisplayVendorID-0", productFile: "DisplayProductID-0")
            == OverrideKey(vendorID: 0, productID: 0))
    }
}

@Suite struct OverrideStoreTests {
    let key = OverrideKey(vendorID: 0xDB4, productID: 0x3401)

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func findsInstalledOverridesAndIgnoresOtherFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        try write(rdmOverrideXML, to: store.locations.userFile(for: key))
        try write("", to: store.locations.userRoot.appending(path: "Icons.plist"))
        try write("", to: store.locations.userRoot.appending(path: "DisplayVendorID-610/DisplayProductID-zz"))
        try write("", to: store.locations.userRoot.appending(path: "DisplayVendorID-610/.DS_Store"))
        #expect(store.installedKeys() == [key])
    }

    @Test func prefersTheInstalledOverride() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        try write(rdmOverrideXML, to: store.locations.userFile(for: key))
        let systemData = try PropertyListSerialization.data(fromPropertyList: ["DisplayProductName": "Apple's"], format: .xml, options: 0)
        try write(String(decoding: systemData, as: UTF8.self), to: store.locations.systemFile(for: key))
        let (override, source) = try store.editableOverride(for: key)
        #expect(source == .installed)
        #expect(override.resolutions.count == 2)  // RDM's 5120 × 2160 1× entry and its HiDPI entry
    }

    @Test func fallsBackToTheSystemOverrideThenToNothing() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        let builtIn = OverrideKey(vendorID: 0x610, productID: 0xA050)
        #expect(try store.editableOverride(for: builtIn).source == .missing)
        let data = try PropertyListSerialization.data(fromPropertyList: ["DisplayProductName": "Color LCD"], format: .xml, options: 0)
        try write(String(decoding: data, as: UTF8.self), to: store.locations.systemFile(for: builtIn))
        let (override, source) = try store.editableOverride(for: builtIn)
        #expect(source == .system)
        #expect(override.productName == "Color LCD")
    }

    @Test func reportsUnreadableFiles() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        let url = store.locations.userFile(for: key)
        try write("<plist><dict><key>broken", to: url)
        let expected = ResoluteError.overrideUnreadable(
            path: url.path(percentEncoded: false), reason: "it is not a valid property list"
        )
        #expect(throws: expected) {
            try store.installedOverride(for: key)
        }
    }

    @Test(.enabled(if: geteuid() != 0, "root can read any file"))
    func saysWhenAFileCannotBeOpened() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        let url = store.locations.userFile(for: key)
        try write(rdmOverrideXML, to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path(percentEncoded: false))
        let expected = ResoluteError.overrideUnreadable(
            path: url.path(percentEncoded: false), reason: "you don’t have permission to read it"
        )
        #expect(throws: expected) {
            try store.installedOverride(for: key)
        }
    }

    @Test func saysWhenAFolderIsInTheWay() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = OverrideStore(locations: .staged(at: root))
        let url = store.locations.userFile(for: key)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let expected = ResoluteError.overrideUnreadable(path: url.path(percentEncoded: false), reason: "it is a folder, not a file")
        #expect(throws: expected) {
            try store.installedOverride(for: key)
        }
    }

    @Test func pointsAtTheStandardLocations() {
        #expect(OverrideLocations.standard.userFile(for: key).path(percentEncoded: false)
            == "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-db4/DisplayProductID-3401")
        #expect(OverrideLocations.standard.backupRoot.path(percentEncoded: false)
            == "/Library/Application Support/Resolute/Backups/")
    }
}

@Suite struct AspectRatioTests {
    @Test(arguments: [
        (1920, 1080, "16:9"), (2560, 1600, "16:10"), (5120, 2160, "64:27"), (3440, 1440, "43:18"),
        (2520, 1080, "21:9"), (1728, 1117, "1.55:1"), (1024, 768, "4:3"), (0, 1080, "—"),
    ])
    func describesRatios(width: Int, height: Int, expected: String) {
        #expect(AspectRatio(width: width, height: height).description == expected)
    }

    @Test func computesHeightsFromWidths() {
        #expect(AspectRatio(width: 16, height: 9).height(forWidth: 2560) == 1440)
        #expect(AspectRatio(width: 64, height: 27).height(forWidth: 3840) == 1620)
        #expect(AspectRatio.presets.map(\.description) == ["16:9", "16:10", "21:9", "32:9", "64:27", "4:3", "3:2"])
    }
}

@Suite struct ScaleResolutionParsingTests {
    @Test func readsTheScaleSuffix() throws {
        #expect(try ScaleResolution(parsing: "1680x1050@1x") == .standard(width: 1680, height: 1050))
        #expect(try ScaleResolution(parsing: "1680x1050@2x") == .hiDPI(width: 1680, height: 1050, flags: .standard))
        #expect(try ScaleResolution(parsing: "1680x1050") == .hiDPI(width: 1680, height: 1050, flags: .standard))
        #expect(try ScaleResolution(parsing: "1680x1050", standard: true) == .standard(width: 1680, height: 1050))
        #expect(try ScaleResolution(parsing: "1280x720", flags: HiDPIFlags(primary: 1, secondary: 0x20_0000))
            == .hiDPI(width: 1280, height: 720, flags: HiDPIFlags(primary: 1, secondary: 0x20_0000)))
    }

    @Test func rejectsWhatAnEntryCannotHold() {
        #expect(throws: ResoluteError.invalidEntry("Override entries have no refresh rate; remove the @60 Hz part.")) {
            try ScaleResolution(parsing: "1680x1050@60")
        }
        #expect(throws: ResoluteError.invalidEntry("1680x1050@2x asks for HiDPI, but --standard asks for 1×.")) {
            try ScaleResolution(parsing: "1680x1050@2x", standard: true)
        }
        #expect(throws: ResoluteError.invalidEntry("Use @1x or @2x.")) {
            try ScaleResolution(parsing: "1680x1050@3x")
        }
        #expect(throws: ResoluteError.invalidEntry("Flags apply only to HiDPI entries.")) {
            try ScaleResolution(parsing: "1680x1050@1x", flags: .standard)
        }
        #expect(throws: ResoluteError.invalidEntry("“big” is not a resolution. Use WIDTHxHEIGHT, optionally followed by @2x or @1x, for example 2560x1080.")) {
            try ScaleResolution(parsing: "big")
        }
        #expect(throws: ResoluteError.sizeTooLarge("4611686018427387904x1080")) {
            try ScaleResolution(parsing: "4611686018427387904x1080")
        }
        #expect(ResoluteError.invalidFlags("junk").errorDescription
            == "“junk” is not a flags value. Use two 32-bit hex words, for example 00000009,00a00000.")
    }
}

@Suite struct OverrideRoundTripTests {
    /// SplitMix64, so a failing case can be reproduced from the seed.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    func randomEntry(_ random: inout SeededGenerator) -> ScaleResolution {
        switch Int.random(in: 0..<5, using: &random) {
        case 0, 1:
            return .standard(width: .random(in: 1...16_384, using: &random), height: .random(in: 1...16_384, using: &random))
        case 2, 3:
            let flags = HiDPIFlags(primary: UInt32.random(in: 0...UInt32.max, using: &random) | 1, secondary: .random(in: 0...UInt32.max, using: &random))
            return .hiDPI(width: .random(in: 1...8_191, using: &random), height: .random(in: 1...8_191, using: &random), flags: flags)
        default:
            // Lengths Resolute never interprets, so the bytes must come back untouched.
            let length = [9, 12, 20].randomElement(using: &random)!
            return .preserved(.data(Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &random) })))
        }
    }

    @Test func readsBackExactlyWhatItWrites() throws {
        let key = OverrideKey(vendorID: 0x10AC, productID: 0xA0C4)
        var random = SeededGenerator(state: 0x5EED)
        for _ in 0..<500 {
            var entries: [ScaleResolution] = []
            for _ in 0..<Int.random(in: 0...8, using: &random) {
                let entry = randomEntry(&random)
                if !entries.contains(entry) { entries.append(entry) }
            }
            let data = try DisplayOverride(key: key, resolutions: entries).propertyListData()
            let reread = try DisplayOverride(key: key, propertyList: data)
            #expect(reread.resolutions == ScaleResolutionCodec.canonicalOrder(entries))
        }
    }
}
