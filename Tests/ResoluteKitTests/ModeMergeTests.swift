import Testing
@testable import ResoluteKit

/// On the development Mac every mode ID equals its private index, so these tests use
/// synthetic records whose IDs differ from their positions, as on other hardware.
@Suite struct ModeMergeTests {
    func record(index: Int32, modeID: Int32, width: Int = 1920, hz: Double = 60) -> PrivateModeRecord {
        PrivateModeRecord(
            index: index, width: width, height: 1080, pixelWidth: width, pixelHeight: 1080,
            refreshRate: hz, bitsPerSample: 10, ioFlags: 0x3, modeID: modeID, scale: 1
        )
    }

    var systemModes: [DisplayMode] {
        [
            TestData.mode(0x1000, 1920, 1080, hz: 60),
            TestData.mode(0x1001, 1920, 1080, hz: 50),
            TestData.mode(0x1002, 1280, 720, hz: 60),
        ]
    }

    var records: [PrivateModeRecord] {
        [
            record(index: 0, modeID: 0x1000),
            record(index: 1, modeID: 0x1001, hz: 50),
            record(index: 2, modeID: 0x1002, width: 1280),
            record(index: 3, modeID: 0x2000, width: 2560, hz: 30),
        ]
    }

    @Test func givesSystemModesTheirPrivateIndexNotTheirID() {
        let merged = ModeMerge.merge(
            systemModes: systemModes, records: records, hidden: [records[3]],
            currentModeID: 0x1000, currentPrivateIndex: 0
        )
        #expect(merged.modes.prefix(3).map(\.privateIndex) == [0, 1, 2])
        #expect(merged.modes.prefix(3).allSatisfy { $0.bitsPerSample == 10 && $0.origin == .system })
    }

    @Test func appendsEachHiddenModeOnce() {
        let merged = ModeMerge.merge(
            systemModes: systemModes, records: records, hidden: [records[3], records[3]],
            currentModeID: 0x1000, currentPrivateIndex: 0
        )
        let hidden = merged.modes.filter { $0.origin == .hidden }
        #expect(hidden.map(\.modeID) == [0x2000])
        #expect(hidden.first?.privateIndex == 3)
    }

    @Test func findsACurrentModeThatOnlyThePrivateListHas() {
        let merged = ModeMerge.merge(
            systemModes: systemModes, records: records, hidden: [records[3]],
            currentModeID: 0x7777, currentPrivateIndex: 3
        )
        #expect(merged.currentModeID == 0x2000)
    }

    @Test func keepsTheCurrentModeCoreGraphicsReportsWhenItIsListed() {
        let merged = ModeMerge.merge(
            systemModes: systemModes, records: records, hidden: [records[3]],
            currentModeID: 0x1001, currentPrivateIndex: 3
        )
        #expect(merged.currentModeID == 0x1001)
    }

    @Test func switchesHiddenModesByPrivateIndex() {
        #expect(ModeMerge.privateIndex(ofHiddenMode: 0x2000, in: [records[3]]) == 3)
        #expect(ModeMerge.privateIndex(ofHiddenMode: 0x1000, in: [records[3]]) == nil)
    }
}
