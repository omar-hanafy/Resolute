import Testing
@testable import ResoluteKit

@Suite struct PrivateModeRecordTests {
    let capture: CapturedDisplay

    init() throws {
        capture = try CapturedDisplay.load()
    }

    @Test func decodesEveryCapturedRecordLikeCoreGraphics() throws {
        let modesByID = Dictionary(uniqueKeysWithValues: capture.modes.map { ($0.modeID, $0) })
        for (position, bytes) in capture.records.enumerated() {
            let record = try #require(PrivateModeRecord(bytes: bytes))
            let mode = try #require(modesByID[record.modeID])
            #expect(record.index == Int32(position))
            #expect(record.width == mode.width)
            #expect(record.height == mode.height)
            #expect(record.pixelWidth == mode.pixelWidth)
            #expect(record.pixelHeight == mode.pixelHeight)
            #expect(record.refreshRate == mode.refreshRate)
            #expect(record.ioFlags == mode.ioFlags)
            #expect(record.scale == mode.scale)
        }
    }

    @Test func decodesTheCurrentModeRecord() throws {
        let record = try #require(PrivateModeRecord(bytes: capture.records[54]))
        #expect(record.index == 54)
        #expect(record.modeID == 54)
        #expect(record.width == 1728)
        #expect(record.height == 1117)
        #expect(record.pixelWidth == 3456)
        #expect(record.pixelHeight == 2234)
        #expect(record.refreshRate == 120)
        #expect(record.bitsPerSample == 10)
        #expect(record.ioFlags == 0x0200_0007)
        #expect(record.scale == 2)
        #expect(record.mode(origin: .hidden).privateIndex == 54)
    }

    @Test func decodesFractionalRefreshRates() throws {
        #expect(try #require(PrivateModeRecord(bytes: capture.records[2])).refreshRate == 59.94)
        #expect(try #require(PrivateModeRecord(bytes: capture.records[5])).refreshRate == 47.95)
    }

    @Test func rejectsRecordsWithoutTheLayoutMarker() {
        var bytes = capture.records[0]
        bytes[0xB8] = 0
        #expect(PrivateModeRecord(bytes: bytes) == nil)
    }

    @Test func rejectsShortRecords() {
        #expect(PrivateModeRecord(bytes: Array(capture.records[0].prefix(0x80))) == nil)
    }

    @Test func dropsABitDepthThatContradictsThePixelEncoding() throws {
        var bytes = capture.records[0]
        #expect(try #require(PrivateModeRecord(bytes: bytes)).bitsPerSample == 10)
        bytes[0x1C] = 8  // the encoding string still has ten R's
        #expect(try #require(PrivateModeRecord(bytes: bytes)).bitsPerSample == nil)
    }

    @Test func rejectsRecordsWithoutAScale() {
        var bytes = capture.records[0]
        for offset in 0xD0..<0xD4 { bytes[offset] = 0 }
        #expect(PrivateModeRecord(bytes: bytes) == nil)
    }
}

@Suite struct PrivateModeValidatorTests {
    let capture: CapturedDisplay
    let records: [PrivateModeRecord?]

    init() throws {
        capture = try CapturedDisplay.load()
        records = capture.records.map(PrivateModeRecord.init(bytes:))
    }

    @Test func trustsRecordsThatMatchCoreGraphics() {
        guard case .trusted(let all, let hidden) = PrivateModeValidator.validate(records: records, against: capture.modes) else {
            Issue.record("expected the captured records to be trusted")
            return
        }
        #expect(all.count == 132)
        #expect(hidden.isEmpty)
    }

    @Test func reportsRecordsMissingFromCoreGraphicsAsHidden() {
        let visible = capture.modes.filter { $0.modeID < 126 }
        guard case .trusted(_, let hidden) = PrivateModeValidator.validate(records: records, against: visible) else {
            Issue.record("expected the captured records to be trusted")
            return
        }
        #expect(hidden.map(\.modeID) == Array(Int32(126)...131))
    }

    @Test func distrustsRecordsThatDisagree() {
        var modes = capture.modes
        modes[55].refreshRate = 75
        guard case .untrusted(let reason) = PrivateModeValidator.validate(records: records, against: modes) else {
            Issue.record("expected a disagreement to be reported")
            return
        }
        #expect(reason.contains("1 of 132"))
    }

    @Test func distrustsRecordsWhoseFlagsDisagree() {
        var modes = capture.modes
        modes[10].ioFlags ^= DisplayMode.Flag.defaultMode
        guard case .untrusted(let reason) = PrivateModeValidator.validate(records: records, against: modes) else {
            Issue.record("expected a flags disagreement to be reported")
            return
        }
        #expect(reason.contains("1 of 132"))
    }

    @Test func distrustsUnreadableRecords() {
        var damaged = records
        damaged[3] = nil
        #expect(PrivateModeValidator.validate(records: damaged, against: capture.modes)
            == .untrusted(reason: "record 3 has an unrecognised layout"))
    }

    @Test func distrustsRecordsOutOfOrder() {
        var shuffled = records
        shuffled.swapAt(0, 1)
        #expect(PrivateModeValidator.validate(records: shuffled, against: capture.modes)
            == .untrusted(reason: "record 0 reports index 1"))
    }

    @Test func distrustsEmptyOrUnmatchedLists() {
        #expect(PrivateModeValidator.validate(records: [], against: capture.modes)
            == .untrusted(reason: "SkyLight reported no modes"))
        #expect(PrivateModeValidator.validate(records: records, against: [])
            == .untrusted(reason: "no SkyLight record matches a CoreGraphics mode"))
    }
}
