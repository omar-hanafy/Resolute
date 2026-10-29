import Foundation
import Testing
@testable import ResoluteKit

/// Displays and overrides for the Sharp Scaling tests.
enum SharpFixture {
    static let key = OverrideKey(vendorID: 0x6B3, productID: 0x27C4)
    static let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)

    /// The design's five sizes for a 2560 × 1440 panel.
    static let designSizes = [(1600, 900), (1920, 1080), (2048, 1152), (2304, 1296), (2560, 1440)]
        .map { SharpSize(width: $0.0, height: $0.1) }

    /// A standard monitor like the design's ASUS PA278QV: a panel of `native` pixels at 75,
    /// 60 and 50 Hz with 1× sizes only, and a hidden 4K mode. `sharp` adds the HiDPI modes
    /// macOS lists for those sizes once it has read the override, at 75 and 60 Hz.
    static func monitor(
        _ native: SharpSize = SharpSize(width: 2560, height: 1440), current: Int32 = 1, sharp: [SharpSize] = []
    ) -> Display {
        var modes = [
            TestData.mode(1, native.width, native.height, hz: 75, flags: 0x0200_0007),
            TestData.mode(2, native.width, native.height, hz: 60, flags: 0x0200_0003),
            TestData.mode(3, native.width, native.height, hz: 50, flags: 0x0200_0003),
            TestData.mode(4, 1920, 1080, hz: 60),
            TestData.mode(5, 1280, 720, hz: 60),
            TestData.mode(90, 3840, 2160, hz: 30, flags: 0x1, origin: .hidden),
        ]
        for (index, size) in sharp.enumerated() {
            modes.append(TestData.mode(Int32(100 + index * 2), size.width, size.height, scale: 2, hz: 75))
            modes.append(TestData.mode(Int32(101 + index * 2), size.width, size.height, scale: 2, hz: 60))
        }
        return Display(
            id: 7, name: "ASUS PA278QV", vendorID: key.vendorID, productID: key.productID,
            currentModeID: current, modes: modes, privateModes: .trusted
        )
    }

    /// An override someone made before Sharp Scaling: a name, a custom entry and keys
    /// Resolute doesn't edit.
    static var customOverride: DisplayOverride {
        DisplayOverride(
            key: key,
            productName: "Studio",
            picture: DisplayOverride.Picture(["display-icon": Data([1, 2, 3])]),
            resolutions: [.standard(width: 2048, height: 1080)],
            otherKeys: PropertyListDictionary([
                "IOGFlags": 4, DisplayOverride.targetPPMMKey: 9.5,
            ]),
            isNew: false
        )
    }

    /// A fresh directory for a staged override root.
    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "Resolute Sharp Scaling 'tests' \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writer(at root: URL, runner: any CommandRunning = ShellCommandRunner()) -> SharpScalingWriter {
        let date = fixedDate
        let locations = OverrideLocations.staged(at: root)
        return SharpScalingWriter(
            store: OverrideStore(locations: locations),
            installer: OverrideInstaller(locations: locations, runner: runner, now: { date })
        )
    }

    /// Writes `override` as the installed file, as another tool would, and returns its bytes.
    @discardableResult
    static func install(_ override: DisplayOverride, at root: URL) throws -> Data {
        let file = OverrideLocations.staged(at: root).userFile(for: override.key)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try override.propertyListData()
        try data.write(to: file)
        return data
    }

    /// Writes `override` as the file macOS ships for its display.
    static func ship(_ override: DisplayOverride, at root: URL) throws {
        let file = OverrideLocations.staged(at: root).systemFile(for: override.key)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try override.propertyListData().write(to: file)
    }

    static func installedBytes(at root: URL) -> Data? {
        FileManager.default.contents(atPath: OverrideLocations.staged(at: root).userFile(for: key).path(percentEncoded: false))
    }

    static func hiDPISizes(in override: DisplayOverride?) -> [SharpSize] {
        (override?.resolutions ?? []).compactMap { entry in
            guard case .hiDPI(let width, let height, _)? = entry.describedMode else { return nil }
            return SharpSize(width: width, height: height)
        }
    }
}

/// Counts the scripts an installer asks to run, without running them.
final class CountingRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var runs = 0

    var count: Int { lock.withLock { runs } }

    func run(_ script: String) async throws {
        lock.withLock { runs += 1 }
    }
}

@Suite struct SharpScalingPlanTests {
    struct Ladder: Sendable, CustomTestStringConvertible {
        var native: (Int, Int)
        var sizes: [(Int, Int)]
        var textLarger: [Int]

        var testDescription: String { "\(native.0) × \(native.1)" }
    }

    @Test func givesA1440pPanelTheDesignsFiveSizes() {
        let plan = SharpScalingPlan(native: SharpSize(width: 2560, height: 1440), limit: DrawingLimit(width: 6144))
        #expect(plan.steps.map(\.size) == SharpFixture.designSizes)
        #expect(plan.steps.map(\.textLarger) == [60, 33, 25, 11, 0])
        #expect(plan.steps.map(\.size.drawnText) == ["3200 × 1800", "3840 × 2160", "4096 × 2304", "4608 × 2592", "5120 × 2880"])
        #expect(plan.steps.allSatisfy { $0.fits })
        #expect(plan.sizes == SharpFixture.designSizes)
    }

    @Test(arguments: [
        Ladder(native: (1920, 1080), sizes: [(1200, 675), (1440, 810), (1536, 864), (1728, 972), (1920, 1080)], textLarger: [60, 33, 25, 11, 0]),
        Ladder(native: (1920, 1200), sizes: [(1200, 750), (1440, 900), (1536, 960), (1728, 1080), (1920, 1200)], textLarger: [60, 33, 25, 11, 0]),
        Ladder(native: (2560, 1600), sizes: [(1600, 1000), (1920, 1200), (2048, 1280), (2304, 1440), (2560, 1600)], textLarger: [60, 33, 25, 11, 0]),
        Ladder(native: (1680, 1050), sizes: [(1048, 655), (1264, 790), (1344, 840), (1512, 945), (1680, 1050)], textLarger: [60, 33, 25, 11, 0]),
        Ladder(native: (2560, 1080), sizes: [(1600, 675), (1920, 810), (2048, 864), (2304, 972), (2560, 1080)], textLarger: [60, 33, 25, 11, 0]),
        Ladder(native: (3440, 1440), sizes: [(2150, 900), (2580, 1080), (2752, 1152), (3096, 1296), (3440, 1440)], textLarger: [60, 33, 25, 11, 0]),
        Ladder(native: (3840, 1600), sizes: [(2400, 1000), (2880, 1200), (3072, 1280), (3456, 1440), (3840, 1600)], textLarger: [60, 33, 25, 11, 0]),
        // A 4K-class panel starts at half its size, drawn pixel for pixel.
        Ladder(native: (3840, 2160), sizes: [(1920, 1080), (2560, 1440), (3072, 1728), (3456, 1944), (3840, 2160)], textLarger: [100, 50, 25, 11, 0]),
        Ladder(native: (3840, 2400), sizes: [(1920, 1200), (2560, 1600), (3072, 1920), (3456, 2160), (3840, 2400)], textLarger: [100, 50, 25, 11, 0]),
    ])
    func givesCommonPanelsFiveSizesEndingAtTheirOwn(ladder: Ladder) {
        let native = SharpSize(width: ladder.native.0, height: ladder.native.1)
        let plan = SharpScalingPlan(native: native, limit: .unknown)
        #expect(plan.steps.map(\.size) == ladder.sizes.map { SharpSize(width: $0.0, height: $0.1) })
        #expect(plan.steps.map(\.textLarger) == ladder.textLarger)
        #expect(plan.steps.last?.size == native)
        // Each size keeps the panel's shape exactly, so macOS scales it evenly.
        #expect(plan.steps.allSatisfy { $0.size.width * native.height == $0.size.height * native.width })
    }

    /// A panel whose ratio has no small whole-number steps still gets five sizes in order,
    /// within a pixel of its shape.
    @Test func roundsPanelsWithAnAwkwardShape() {
        let native = SharpSize(width: 1366, height: 768)
        let sizes = SharpScalingPlan.ladder(for: native)
        #expect(sizes == [(854, 480), (1024, 576), (1092, 614), (1230, 692), (1366, 768)].map { SharpSize(width: $0.0, height: $0.1) })
        #expect(sizes.allSatisfy { abs(Double($0.width) * 768 / 1366 - Double($0.height)) < 1 })
    }

    @Test func leavesOutSizesWiderThanThisMacDraws() {
        let ultrawide = SharpSize(width: 3440, height: 1440)
        let limited = SharpScalingPlan(native: ultrawide, limit: DrawingLimit(width: 6144))
        #expect(limited.steps.map(\.fits) == [true, true, true, false, false])
        #expect(limited.sizes.map(\.description) == ["2150x900", "2580x1080", "2752x1152"])
        #expect(SharpScalingPlan(native: ultrawide, limit: DrawingLimit(width: 7680, height: 4320)).sizes.count == 5)
        // 3072 × 1728 is drawn exactly 6144 pixels wide, which fits.
        let uhd = SharpScalingPlan(native: SharpSize(width: 3840, height: 2160), limit: DrawingLimit(width: 6144))
        #expect(uhd.steps.map(\.fits) == [true, true, true, false, false])
    }

    @Test func leavesOutSizesTallerThanThisMacDraws() {
        let limit = DrawingLimit(width: 7680, height: 4320)
        let plan = SharpScalingPlan(native: SharpSize(width: 3840, height: 2400), limit: limit)
        #expect(plan.steps.map(\.fits) == [true, true, true, true, false])
        let native = plan.steps[4].size
        #expect(!limit.isTooWide(native))
        #expect(!limit.allows(native))
    }

    @Test func plansEverySizeWhenTheLimitIsUnknown() {
        let plan = SharpScalingPlan(native: SharpSize(width: 5120, height: 1440), limit: .unknown)
        #expect(plan.steps.count == 5)
        #expect(plan.steps.allSatisfy { $0.fits })
    }

    @Test func findsThePanelInTheModesMacOSLists() {
        #expect(SharpScalingPlan.nativeSize(of: SharpFixture.monitor()) == SharpSize(width: 2560, height: 1440))
        // Without a native mode, the 1× default; without one either, the largest 1× mode.
        var display = SharpFixture.monitor()
        display.modes = display.modes.map { mode in
            var mode = mode
            mode.ioFlags &= ~DisplayMode.Flag.native
            return mode
        }
        display.modes.append(TestData.mode(60, 3200, 1800, hz: 60))
        #expect(SharpScalingPlan.nativeSize(of: display) == SharpSize(width: 2560, height: 1440))
        display.modes = display.modes.map { mode in
            var mode = mode
            mode.ioFlags &= ~DisplayMode.Flag.defaultMode
            return mode
        }
        #expect(SharpScalingPlan.nativeSize(of: display) == SharpSize(width: 3200, height: 1800))
        // Hidden modes don't count, nor do the 1× entries Sharp Scaling paired with its sizes.
        let record = SharpScalingRecord(
            saved: SharpFixture.fixedDate, sizes: [SharpSize(width: 1600, height: 900)], added: [SharpSize(width: 1600, height: 900)],
            partners: [.standard(width: 3200, height: 1800)], offered: [], switchTo: nil,
            original: .init(source: .missing, backupDigest: nil, fingerprint: "")
        )
        #expect(SharpScalingPlan.nativeSize(of: display, record: record) == SharpSize(width: 2560, height: 1440))
    }

    @Test func offersSharpScalingOnlyToStandardDisplays() throws {
        #expect(SharpScalingPlan.unavailability(for: SharpFixture.monitor(), installed: nil) == nil)
        var builtIn = SharpFixture.monitor()
        builtIn.isBuiltin = true
        #expect(SharpScalingPlan.unavailability(for: builtIn, installed: nil) == .builtIn)
        #expect(SharpScalingPlan.unavailability(for: TestData.uhd(), installed: nil) == .alreadyHiDPI)
        // HiDPI modes that come from the installed override don't make it a Retina display.
        let sharp = SharpFixture.monitor(sharp: SharpFixture.designSizes)
        #expect(SharpScalingPlan.unavailability(for: sharp, installed: nil) == .alreadyHiDPI)
        let installed = DisplayOverride(key: SharpFixture.key, resolutions: SharpFixture.designSizes.map(\.entry), isNew: false)
        #expect(SharpScalingPlan.unavailability(for: sharp, installed: installed) == nil)
        var noPanel = SharpFixture.monitor()
        noPanel.modes = noPanel.modes.filter { $0.origin == .hidden }
        #expect(SharpScalingPlan.unavailability(for: noPanel, installed: nil) == .unknownPanel)
    }

    @Test func switchesToTheSameSizeSharpElseTheNearest() {
        let sizes = SharpFixture.designSizes
        let native = SharpSize(width: 2560, height: 1440)
        let monitor = SharpFixture.monitor()
        #expect(SharpScalingPlan.switchTarget(from: monitor.currentMode, among: sizes, native: native) == native)
        let stretched = TestData.mode(9, 1680, 1050)
        #expect(SharpScalingPlan.switchTarget(from: stretched, among: sizes, native: native) == SharpSize(width: 1600, height: 900))
        #expect(SharpScalingPlan.switchTarget(from: nil, among: sizes, native: native) == native)
        #expect(SharpScalingPlan.switchTarget(from: nil, among: Array(sizes.prefix(2)), native: native) == sizes[1])
    }
}

@Suite struct DrawingLimitTests {
    typealias Framebuffer = DrawingLimit.Framebuffer

    static func pixels(width: [Int], height: [Int]) -> [String: Any] {
        ["MaxSrcRectWidthForPipe": width, "MaxSrcRectHeightForPipe": height, "MaxSrcBufferWidth": 16384]
    }

    /// As an M2 Pro publishes it: the built-in display's pipe takes 5120 pixels, each
    /// external pipe 7680 × 4320.
    @Test func readsTheExternalDisplayPipesLimit() {
        let limit = DrawingLimit.limit(from: [
            Framebuffer(isExternal: false, maxSourcePixels: Self.pixels(width: [5120, 0, 0, 0], height: [4320, 4320, 4320, 4320])),
            Framebuffer(isExternal: true, maxSourcePixels: Self.pixels(width: [7680, 7680, 7680, 7680], height: [4320, 4320, 4320, 4320])),
            Framebuffer(isExternal: true, maxSourcePixels: Self.pixels(width: [7680, 7680, 7680, 7680], height: [4320, 4320, 4320, 4320])),
        ])
        #expect(limit == DrawingLimit(width: 7680, height: 4320))
    }

    @Test func takesTheSmallestExternalFramebuffer() {
        let limit = DrawingLimit.limit(from: [
            Framebuffer(isExternal: true, maxSourcePixels: Self.pixels(width: [7680, 0], height: [4320, 0])),
            Framebuffer(isExternal: true, maxSourcePixels: Self.pixels(width: [6144], height: [3456])),
        ])
        #expect(limit == DrawingLimit(width: 6144, height: 3456))
    }

    @Test func isUnknownWhenNothingIsPublished() {
        #expect(DrawingLimit.limit(from: []) == .unknown)
        #expect(DrawingLimit.limit(from: [Framebuffer(isExternal: false, maxSourcePixels: Self.pixels(width: [5120], height: [4320]))]) == .unknown)
        #expect(DrawingLimit.limit(from: [Framebuffer(isExternal: true, maxSourcePixels: nil)]) == .unknown)
        #expect(DrawingLimit.limit(from: [Framebuffer(isExternal: true, maxSourcePixels: Self.pixels(width: [0, 0], height: []))]) == .unknown)
        #expect(!DrawingLimit.unknown.isKnown)
    }

    @Test func allowsSizesDrawnWithinIt() {
        let limit = DrawingLimit(width: 6144, height: 3456)
        #expect(limit.allows(SharpSize(width: 2560, height: 1440)))
        #expect(limit.allows(SharpSize(width: 3072, height: 1728)))
        #expect(!limit.allows(SharpSize(width: 3096, height: 1296)))
        #expect(limit.isTooWide(SharpSize(width: 3096, height: 1296)))
        #expect(DrawingLimit.unknown.allows(SharpSize(width: 8192, height: 4320)))
    }

    /// Reads this Mac's IORegistry without changing anything. A Mac that publishes no limit,
    /// such as a virtual machine, gets an unknown one.
    @Test func readsThisMacWithoutFailing() {
        let limit = DrawingLimit.current()
        if let width = limit.width { #expect(width >= 1024) }
        if let height = limit.height { #expect(height >= 768) }
    }
}

@Suite struct SharpScalingSetupTests {
    func file(_ override: DisplayOverride, source: OverrideStore.Source = .installed) throws -> OverrideStore.EditableOverride {
        OverrideStore.EditableOverride(
            override: override, source: source,
            installedState: source == .installed ? .contents(try override.propertyListData()) : .absent
        )
    }

    @Test func mergesIntoAnExistingOverrideKeepingItsEntriesAndKeys() throws {
        let original = SharpFixture.customOverride
        let setup = try SharpScalingSetup(
            file: file(original), sizes: SharpFixture.designSizes, offered: [], switchTo: SharpSize(width: 2560, height: 1440),
            now: SharpFixture.fixedDate
        )
        #expect(setup.hasChanges)
        #expect(setup.replacesFile)
        #expect(setup.added == SharpFixture.designSizes)
        #expect(setup.removed.isEmpty)
        let written = setup.override
        #expect(written.productName == "Studio")
        #expect(written.resolutions.contains(.standard(width: 2048, height: 1080)))
        #expect(SharpFixture.hiDPISizes(in: written) == SharpFixture.designSizes.reversed())
        // Each size comes with the 1× entry at its drawn size, as the editor adds them.
        let partners = SharpFixture.designSizes.map(\.partner)
        #expect(partners.allSatisfy { written.resolutions.contains($0) })
        #expect(written.resolutions.count == 11)
        var keys = written.otherKeys.dictionary
        #expect(keys.removeValue(forKey: SharpScalingRecord.key) != nil)
        #expect(PropertyListDictionary(keys) == original.otherKeys)
        let record = try #require(try SharpScalingRecord(in: written))
        #expect(record == setup.record)
        #expect(record.sizes == SharpFixture.designSizes)
        #expect(record.added == SharpFixture.designSizes)
        #expect(Set(record.partners) == Set(partners))
        #expect(record.switchTo == SharpSize(width: 2560, height: 1440))
        #expect(record.original.source == .installed)
        #expect(record.original.backupDigest == SharpScalingRecord.digest(try original.propertyListData()))
        #expect(record.original.fingerprint == (try SharpScalingRecord.fingerprint(of: original)))
    }

    @Test func leavesSizesAndOneTimesEntriesTheFileHadAsItsOwn() throws {
        var original = SharpFixture.customOverride
        original.resolutions += [.hiDPI(width: 1920, height: 1080, flags: .standard), .standard(width: 3200, height: 1800)]
        let setup = try SharpScalingSetup(file: file(original), sizes: SharpFixture.designSizes, offered: [], switchTo: nil, now: SharpFixture.fixedDate)
        #expect(setup.record.sizes == SharpFixture.designSizes)
        #expect(setup.added.map(\.description) == ["1600x900", "2048x1152", "2304x1296", "2560x1440"])
        #expect(setup.record.added == setup.added)
        // 1600 × 900 found its 1× entry in the file; 1920 × 1080 was the file's own.
        #expect(Set(setup.record.partners) == [
            .standard(width: 4096, height: 2304), .standard(width: 4608, height: 2592), .standard(width: 5120, height: 2880),
        ])
        #expect(setup.override.resolutions.filter { $0.sameMode(as: .standard(width: 3200, height: 1800)) }.count == 1)
    }

    @Test func writesNothingWhenTheSizesAreSavedAlready() throws {
        let first = try SharpScalingSetup(
            file: file(SharpFixture.customOverride), sizes: SharpFixture.designSizes, offered: [], switchTo: nil, now: SharpFixture.fixedDate
        )
        let again = try SharpScalingSetup(
            file: file(first.override.readFromFile()), sizes: SharpFixture.designSizes.reversed(), offered: [],
            switchTo: SharpSize(width: 2560, height: 1440), now: SharpFixture.fixedDate.addingTimeInterval(60)
        )
        #expect(!again.hasChanges)
        #expect(again.added.isEmpty)
        #expect(again.removed.isEmpty)
    }

    @Test func takesOutOnlyTheSizesItWroteWhenTheSelectionShrinks() throws {
        var original = SharpFixture.customOverride
        original.resolutions.append(.hiDPI(width: 1920, height: 1080, flags: .standard))
        let first = try SharpScalingSetup(file: file(original), sizes: SharpFixture.designSizes, offered: [], switchTo: nil, now: SharpFixture.fixedDate)
        let fewer = [SharpSize(width: 1600, height: 900), SharpSize(width: 2560, height: 1440)]
        let second = try SharpScalingSetup(
            file: file(first.override.readFromFile()), sizes: fewer, offered: fewer, switchTo: nil, now: SharpFixture.fixedDate
        )
        #expect(second.hasChanges)
        #expect(second.added.isEmpty)
        #expect(second.removed.map(\.description) == ["2048x1152", "2304x1296"])
        // 1920 × 1080 was the file's own, so it stays even though Sharp Scaling no longer lists it.
        #expect(SharpFixture.hiDPISizes(in: second.override) == [SharpSize(width: 2560, height: 1440), SharpSize(width: 1920, height: 1080), SharpSize(width: 1600, height: 900)])
        #expect(!second.override.resolutions.contains(.standard(width: 4096, height: 2304)))
        #expect(!second.override.resolutions.contains(.standard(width: 4608, height: 2592)))
        #expect(second.override.resolutions.contains(.standard(width: 2048, height: 1080)))
        #expect(second.record.sizes == fewer)
        #expect(second.record.offered == fewer)
        // What the file was before Sharp Scaling stays on record from the first setup.
        #expect(second.record.original == first.record.original)
    }

    @Test func remembersWhereANewFileCameFrom() throws {
        let missing = try SharpScalingSetup(
            file: file(DisplayOverride(key: SharpFixture.key), source: .missing), sizes: SharpFixture.designSizes, offered: [],
            switchTo: nil, now: SharpFixture.fixedDate
        )
        #expect(!missing.replacesFile)
        #expect(missing.record.original.source == .missing)
        #expect(missing.record.original.backupDigest == nil)
        #expect(missing.override.isNew)
        let shipped = try SharpScalingSetup(
            file: file(SharpFixture.customOverride, source: .system), sizes: SharpFixture.designSizes, offered: [],
            switchTo: nil, now: SharpFixture.fixedDate
        )
        #expect(shipped.record.original.source == .system)
        #expect(shipped.record.original.backupDigest == nil)
    }

    @Test func refusesAnEmptySelection() throws {
        #expect(throws: ResoluteError.self) {
            try SharpScalingSetup(file: file(SharpFixture.customOverride), sizes: [], offered: [], switchTo: nil, now: SharpFixture.fixedDate)
        }
    }
}

@Suite struct SharpScalingRecordTests {
    let record = SharpScalingRecord(
        saved: SharpFixture.fixedDate,
        sizes: SharpFixture.designSizes,
        added: Array(SharpFixture.designSizes.dropFirst()),
        partners: [.standard(width: 3840, height: 2160)],
        offered: [SharpSize(width: 1600, height: 900)],
        switchTo: SharpSize(width: 2560, height: 1440),
        original: .init(source: .installed, backupDigest: "ab12", fingerprint: "cd34")
    )

    @Test func readsBackWhatItWritesThroughTheFile() throws {
        let written = record.written(into: SharpFixture.customOverride)
        let read = try DisplayOverride(key: SharpFixture.key, propertyList: written.propertyListData())
        #expect(try SharpScalingRecord(in: read) == record)
        #expect(read.productName == "Studio")
        #expect(try SharpScalingRecord(in: SharpScalingRecord.removed(from: read)) == nil)
        #expect(SharpScalingRecord.removed(from: read).otherKeys == SharpFixture.customOverride.otherKeys)
    }

    @Test func treatsAnOverrideWithoutOneAsOff() throws {
        #expect(try SharpScalingRecord(in: SharpFixture.customOverride) == nil)
    }

    @Test func refusesADamagedRecordRatherThanCallingItOff() {
        let damagedRecords: [Any] = ["junk", ["version": 1], ["version": 1, "saved": SharpFixture.fixedDate, "sizes": ["big"]]]
        for damaged in damagedRecords {
            var override = SharpFixture.customOverride
            override.otherKeys = PropertyListDictionary([SharpScalingRecord.key: damaged])
            #expect(throws: ResoluteError.self) { try SharpScalingRecord(in: override) }
        }
    }

    @Test func refusesARecordFromANewerResolute() throws {
        var list = record.propertyList
        list["version"] = SharpScalingRecord.version + 1
        var override = SharpFixture.customOverride
        override.otherKeys = PropertyListDictionary([SharpScalingRecord.key: list])
        do {
            _ = try SharpScalingRecord(in: override)
            Issue.record("expected a record from a newer Resolute to be refused")
        } catch {
            #expect(error.localizedDescription.contains("newer version of Resolute"))
        }
    }

    /// Equal contents read in any order give the same fingerprint, and any change gives another.
    @Test func fingerprintsContentsWhateverTheirKeyOrder() throws {
        let original = SharpFixture.customOverride
        let reread = try original.readFromFile()
        #expect(try SharpScalingRecord.fingerprint(of: original) == SharpScalingRecord.fingerprint(of: reread))
        #expect(try SharpScalingRecord.fingerprint(of: record.written(into: original)) == SharpScalingRecord.fingerprint(of: original))
        var renamed = original
        renamed.productName = "Desk"
        #expect(try SharpScalingRecord.fingerprint(of: renamed) != SharpScalingRecord.fingerprint(of: original))
        // A picture chosen after setup is a later edit too, so turning off keeps it.
        var repictured = original
        repictured.displayIcon = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/com.apple.studio-display.icns"
        #expect(try SharpScalingRecord.fingerprint(of: repictured) != SharpScalingRecord.fingerprint(of: original))
    }
}

/// Turning Sharp Scaling on and off through a staged installer, with real scripts writing
/// into a temporary folder.
@Suite struct SharpScalingWriterTests {
    let display = SharpFixture.monitor()

    @Test func putsBackTheFileFromBeforeByteForByte() async throws {
        let root = try SharpFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = SharpFixture.writer(at: root)
        let before = try SharpFixture.install(SharpFixture.customOverride, at: root)
        let setup = try await writer.turnOn(for: display, sizes: SharpFixture.designSizes, switchTo: nil)
        #expect(setup.hasChanges)
        let installed = try #require(try writer.store.installedOverride(for: SharpFixture.key))
        #expect(SharpFixture.hiDPISizes(in: installed).count == 5)
        #expect(writer.store.backups(for: SharpFixture.key).count == 1)

        guard case .restore(let backup, let contents)? = try writer.removal(for: SharpFixture.key) else {
            Issue.record("expected the backup from before Sharp Scaling to go back")
            return
        }
        #expect(contents == before)
        #expect(backup == writer.store.backups(for: SharpFixture.key).first)
        try await writer.turnOff(for: SharpFixture.key)
        #expect(SharpFixture.installedBytes(at: root) == before)
        // The file Sharp Scaling wrote is in the backups too.
        #expect(writer.store.backups(for: SharpFixture.key).count == 2)
    }

    @Test func removesAFileItCreated() async throws {
        let root = try SharpFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = SharpFixture.writer(at: root)
        let setup = try await writer.turnOn(for: display, sizes: SharpFixture.designSizes, switchTo: nil)
        #expect(!setup.replacesFile)
        // A new file gets the target density, as the Custom Resolutions editor gives one.
        #expect(try writer.store.installedOverride(for: SharpFixture.key)?.otherKeys.keys.contains(DisplayOverride.targetPPMMKey) == true)
        guard case .remove? = try writer.removal(for: SharpFixture.key) else {
            Issue.record("expected the file Sharp Scaling created to go")
            return
        }
        try await writer.turnOff(for: SharpFixture.key)
        #expect(SharpFixture.installedBytes(at: root) == nil)
        #expect(try writer.store.editableFile(for: SharpFixture.key).source == .missing)
    }

    /// Over the file macOS ships, turning off removes the copy, so macOS's own file counts again.
    @Test func removesItsCopyOfTheFileMacOSShips() async throws {
        let root = try SharpFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = SharpFixture.writer(at: root)
        try SharpFixture.ship(SharpFixture.customOverride, at: root)
        try await writer.turnOn(for: display, sizes: SharpFixture.designSizes, switchTo: nil)
        #expect(try writer.store.installedOverride(for: SharpFixture.key)?.productName == "Studio")
        try await writer.turnOff(for: SharpFixture.key)
        #expect(SharpFixture.installedBytes(at: root) == nil)
        #expect(try writer.store.editableFile(for: SharpFixture.key).source == .system)
    }

    @Test func keepsChangesMadeAfterSetup() async throws {
        let root = try SharpFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = SharpFixture.writer(at: root)
        try SharpFixture.install(SharpFixture.customOverride, at: root)
        try await writer.turnOn(for: display, sizes: SharpFixture.designSizes, switchTo: nil)
        // Someone adds a size in Custom Resolutions afterwards.
        var edited = try #require(try writer.store.installedOverride(for: SharpFixture.key))
        edited.resolutions.append(.standard(width: 1280, height: 800))
        try SharpFixture.install(edited, at: root)

        guard case .strip(_, .changedSince)? = try writer.removal(for: SharpFixture.key) else {
            Issue.record("expected only Sharp Scaling's sizes to come out")
            return
        }
        try await writer.turnOff(for: SharpFixture.key)
        let after = try #require(try writer.store.installedOverride(for: SharpFixture.key))
        #expect(after.resolutions == [.standard(width: 2048, height: 1080), .standard(width: 1280, height: 800)])
        #expect(after.productName == "Studio")
        #expect(after.otherKeys == SharpFixture.customOverride.otherKeys)
    }

    @Test func takesOutItsSizesWhenTheBackupIsGone() async throws {
        let root = try SharpFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = SharpFixture.writer(at: root)
        try SharpFixture.install(SharpFixture.customOverride, at: root)
        try await writer.turnOn(for: display, sizes: SharpFixture.designSizes, switchTo: nil)
        try FileManager.default.removeItem(at: writer.store.locations.backupRoot)
        guard case .strip(let override, .backupMissing)? = try writer.removal(for: SharpFixture.key) else {
            Issue.record("expected only Sharp Scaling's sizes to come out")
            return
        }
        #expect(try SharpScalingRecord.fingerprint(of: override) == SharpScalingRecord.fingerprint(of: SharpFixture.customOverride))
    }

    @Test func runsNoScriptWhenNothingChanges() async throws {
        let root = try SharpFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try await SharpFixture.writer(at: root).turnOn(for: display, sizes: SharpFixture.designSizes, switchTo: nil)
        let runner = CountingRunner()
        let counting = SharpFixture.writer(at: root, runner: runner)
        let again = try await counting.turnOn(for: display, sizes: SharpFixture.designSizes, switchTo: nil)
        #expect(!again.hasChanges)
        try await SharpFixture.writer(at: root).turnOff(for: SharpFixture.key)
        #expect(try await counting.turnOff(for: SharpFixture.key) == nil)
        #expect(runner.count == 0)
    }

    @Test func refusesToOverwriteAFileThatChangedAfterItWasRead() async throws {
        let root = try SharpFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = SharpFixture.writer(at: root, runner: EditingRunner(root: root))
        await #expect(throws: ResoluteError.self) {
            try await writer.turnOn(for: display, sizes: SharpFixture.designSizes, switchTo: nil)
        }
        #expect(try writer.store.installedOverride(for: SharpFixture.key)?.resolutions == [.standard(width: 1024, height: 640)])
    }
}

/// Writes another override just before running each script, as another tool editing the
/// file between the read and the install would.
struct EditingRunner: CommandRunning {
    let root: URL

    func run(_ script: String) async throws {
        try SharpFixture.install(DisplayOverride(key: SharpFixture.key, resolutions: [.standard(width: 1024, height: 640)], isNew: false), at: root)
        try await ShellCommandRunner().run(script)
    }
}

@Suite struct SharpScalingStatusTests {
    let sizes = SharpFixture.designSizes

    /// The installed override after setup, saved at `saved`, with `offered` the sizes macOS
    /// offered then.
    func installed(saved: Date = SharpFixture.fixedDate, offered: [SharpSize] = []) throws -> DisplayOverride {
        let file = OverrideStore.EditableOverride(override: DisplayOverride(key: SharpFixture.key), source: .missing, installedState: .absent)
        return try SharpScalingSetup(file: file, sizes: sizes, offered: offered, switchTo: nil, now: saved).override.readFromFile()
    }

    @Test func isOffWithoutARecord() throws {
        let status = try SharpScalingStatus(display: SharpFixture.monitor(), installed: SharpFixture.customOverride)
        #expect(status.state == .off)
        #expect(status.saved.isEmpty)
        #expect(status.current?.modeID == 1)
        #expect(!status.isCurrentHiDPI)
        #expect(status.sharpVersionOfCurrent == nil)
        #expect(try SharpScalingStatus(display: SharpFixture.monitor(), installed: nil).state == .off)
    }

    @Test func waitsForTheReconnect() throws {
        let status = try SharpScalingStatus(
            display: SharpFixture.monitor(), installed: installed(), systemStart: SharpFixture.fixedDate.addingTimeInterval(-3600)
        )
        #expect(status.state == .waiting)
        #expect(status.saved == sizes)
        #expect(status.available.isEmpty)
        // Not skipped: macOS hasn't read the file yet.
        #expect(status.pending == sizes)
        #expect(status.skipped.isEmpty)
    }

    @Test func isReadyWhenMacOSOffersEverySize() throws {
        let display = SharpFixture.monitor(current: 109, sharp: sizes)
        let status = try SharpScalingStatus(display: display, installed: installed())
        #expect(status.state == .ready)
        #expect(status.available == sizes)
        #expect(status.skipped.isEmpty)
        #expect(status.isCurrentHiDPI)
        #expect(status.current.map { SharpSize($0) } == SharpSize(width: 2560, height: 1440))
        #expect(status.sharpVersionOfCurrent?.modeID == 109)
    }

    /// 68:2089: after the reconnect macOS added four of the five sizes.
    @Test func namesTheSizeMacOSSkipped() throws {
        let display = SharpFixture.monitor(sharp: Array(sizes.prefix(4)))
        let status = try SharpScalingStatus(display: display, installed: installed())
        #expect(status.state == .partial)
        #expect(status.available == Array(sizes.prefix(4)))
        #expect(status.skipped == [SharpSize(width: 2560, height: 1440)])
        #expect(status.pending.isEmpty)
    }

    /// Sizes macOS offered already when they were saved prove nothing about a reconnect.
    @Test func keepsWaitingWhileOnlySizesOfferedBeforeShow() throws {
        let display = SharpFixture.monitor(sharp: Array(sizes.prefix(4)))
        let status = try SharpScalingStatus(display: display, installed: installed(offered: Array(sizes.prefix(4))))
        #expect(status.state == .waiting)
        #expect(status.pending == [SharpSize(width: 2560, height: 1440)])
        #expect(status.skipped.isEmpty)
    }

    @Test func knowsEverySizeWasSkippedOnceTheDisplayReadTheFile() throws {
        let afterRestart = try SharpScalingStatus(
            display: SharpFixture.monitor(), installed: installed(), systemStart: SharpFixture.fixedDate.addingTimeInterval(3600)
        )
        #expect(afterRestart.state == .partial)
        #expect(afterRestart.available.isEmpty)
        #expect(afterRestart.skipped == sizes)
        let afterReconnect = try SharpScalingStatus(display: SharpFixture.monitor(), installed: installed(), reconnectedSinceSave: true)
        #expect(afterReconnect.state == .partial)
    }

    @Test func countsOnlyModesMacOSLists() throws {
        var display = SharpFixture.monitor(sharp: sizes)
        display.modes = display.modes.map { mode in
            var mode = mode
            if mode.isHiDPI, mode.width == 2560 { mode.origin = .hidden }
            return mode
        }
        let status = try SharpScalingStatus(display: display, installed: installed())
        #expect(status.skipped == [SharpSize(width: 2560, height: 1440)])
    }

    @Test func leavesOutSizesTakenOutOfTheFile() throws {
        var edited = try installed()
        edited.resolutions.removeAll { $0.sameMode(as: sizes[0].entry) }
        let status = try SharpScalingStatus(display: SharpFixture.monitor(sharp: Array(sizes.dropFirst())), installed: edited)
        #expect(status.saved == Array(sizes.dropFirst()))
        #expect(status.state == .ready)
    }

    /// The sharp version keeps the refresh rate: 2560 × 1440 at 60 Hz becomes the sharp
    /// 2560 × 1440 at 60 Hz, not the fastest one.
    @Test func findsTheSharpVersionOfTheCurrentSizeAtItsRefreshRate() throws {
        let display = SharpFixture.monitor(current: 2, sharp: sizes)
        let status = try SharpScalingStatus(display: display, installed: installed())
        #expect(status.sharpVersionOfCurrent?.modeID == 109)
        #expect(status.sharpVersionOfCurrent?.refreshRate == 60)
        let fullHD = try #require(display.modes.first { $0.modeID == 4 })
        #expect(SharpScalingStatus.sharpVersion(of: fullHD, on: display)?.modeID == 103)
        let sharp = try #require(display.modes.first { $0.modeID == 108 })
        #expect(SharpScalingStatus.sharpVersion(of: sharp, on: display) == sharp)
        #expect(SharpScalingStatus.sharpVersion(of: TestData.mode(9, 1680, 1050), on: display) == nil)
    }

    @Test func knowsWhenThisMacStarted() throws {
        let start = try #require(SharpScalingStatus.systemStart())
        #expect(start < Date())
        #expect(start > Date(timeIntervalSince1970: 1_000_000_000))
    }
}

extension DisplayOverride {
    /// The override as a file holding it reads back.
    func readFromFile() throws -> DisplayOverride {
        try DisplayOverride(key: key, propertyList: propertyListData())
    }
}
