import Foundation

/// One record from `CGSGetDisplayModeDescriptionOfLength`, decoded with the layout
/// macOS uses today (verified on macOS 27; offsets are listed in docs/design).
public struct PrivateModeRecord: Hashable, Sendable {
    /// The record size Resolute asks for and understands.
    public static let length = 0xD4

    /// Position in the private mode list; the argument `CGSConfigureDisplayMode` takes.
    public var index: Int32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double
    /// Bits per colour component, when the record's pixel encoding confirms it.
    public var bitsPerSample: Int?
    public var ioFlags: UInt32
    public var modeID: Int32
    public var scale: Double

    init(
        index: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double,
        bitsPerSample: Int?, ioFlags: UInt32, modeID: Int32, scale: Double
    ) {
        self.index = index
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.bitsPerSample = bitsPerSample
        self.ioFlags = ioFlags
        self.modeID = modeID
        self.scale = scale
    }

    /// Decodes a record, or returns nil when the bytes do not have the expected layout.
    public init?(bytes: [UInt8]) {
        guard bytes.count >= Self.length else { return nil }
        func word(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset])
                | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16
                | UInt32(bytes[offset + 3]) << 24
        }
        // The record carries its own size; anything else is a layout we do not know.
        guard word(0xB8) == UInt32(Self.length) else { return nil }
        let scale = Double(Float(bitPattern: word(0xD0)))
        let width = Int(word(0x08))
        let height = Int(word(0x0C))
        let pixelWidth = Int(word(0xC8))
        let pixelHeight = Int(word(0xCC))
        // Hidden records have no public counterpart to cross-check. Bound every size
        // before catalog arithmetic and require the backing dimensions to agree with
        // the record's scale; a readable layout marker alone is not enough.
        guard ModeQuery.isPlausible(scale: scale),
              [width, height, pixelWidth, pixelHeight].allSatisfy({ (1...ModeQuery.maximumDimension).contains($0) }),
              abs(Double(pixelWidth) / Double(width) - scale) < 0.01,
              abs(Double(pixelHeight) / Double(height) - scale) < 0.01 else {
            return nil
        }
        self.index = Int32(bitPattern: word(0x00))
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        // 16.16 fixed point, rounded to the millihertz CoreGraphics reports.
        self.refreshRate = (Double(word(0xBC)) / 65_536 * 1_000).rounded() / 1_000
        self.bitsPerSample = Self.confirmedBitsPerSample(
            bitsPerSample: Int(word(0x1C)),
            samplesPerPixel: Int(word(0x20)),
            bitsPerPixel: Int(word(0x18)),
            encoding: bytes[0x30..<0x70]
        )
        self.ioFlags = word(0xC0)
        self.modeID = Int32(bitPattern: word(0xC4))
        self.scale = scale
    }

    /// The record as a `DisplayMode`.
    public func mode(origin: DisplayMode.Origin) -> DisplayMode {
        DisplayMode(
            modeID: modeID,
            privateIndex: index,
            width: width,
            height: height,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            refreshRate: refreshRate,
            bitsPerSample: bitsPerSample,
            ioFlags: ioFlags,
            origin: origin
        )
    }

    /// The bit depth, or nil unless it matches the pixel encoding string (such as
    /// "--RRRRRRRRRRGGGGGGGGGGBBBBBBBBBB" for 10 bits) and fits in a pixel.
    static func confirmedBitsPerSample(
        bitsPerSample: Int,
        samplesPerPixel: Int,
        bitsPerPixel: Int,
        encoding: ArraySlice<UInt8>
    ) -> Int? {
        let characters = encoding.prefix { $0 != 0 }
        let redBits = characters.filter { $0 == UInt8(ascii: "R") }.count
        guard bitsPerSample > 0, redBits == bitsPerSample,
              samplesPerPixel > 0, bitsPerSample * samplesPerPixel <= bitsPerPixel
        else { return nil }
        return bitsPerSample
    }
}

/// The result of checking private records against CoreGraphics.
public enum PrivateModeValidation: Equatable, Sendable {
    /// Every record CoreGraphics also lists agrees with it; `hidden` are the extras.
    case trusted(records: [PrivateModeRecord], hidden: [PrivateModeRecord])
    /// The records cannot be relied on.
    case untrusted(reason: String)
}

/// Decides whether the private mode list can be used.
public enum PrivateModeValidator {
    /// Compares decoded private records (in list order) with the public modes.
    public static func validate(
        records: [PrivateModeRecord?],
        against systemModes: [DisplayMode]
    ) -> PrivateModeValidation {
        guard !records.isEmpty else { return .untrusted(reason: "SkyLight reported no modes") }
        var decoded: [PrivateModeRecord] = []
        var recordsByID: [Int32: PrivateModeRecord] = [:]
        for (position, record) in records.enumerated() {
            guard let record else {
                return .untrusted(reason: "record \(position) has an unrecognised layout")
            }
            guard record.index == Int32(position) else {
                return .untrusted(reason: "record \(position) reports index \(record.index)")
            }
            if let previous = recordsByID[record.modeID],
               (!agrees(record, previous.mode(origin: .hidden)) || record.bitsPerSample != previous.bitsPerSample) {
                return .untrusted(reason: "mode ID \(record.modeID) has conflicting SkyLight records")
            }
            recordsByID[record.modeID] = record
            decoded.append(record)
        }
        let systemByID = Dictionary(systemModes.map { ($0.modeID, $0) }, uniquingKeysWith: { first, _ in first })
        var matched = 0
        var mismatched = 0
        var hidden: [PrivateModeRecord] = []
        for record in decoded {
            guard let mode = systemByID[record.modeID] else {
                hidden.append(record)
                continue
            }
            matched += 1
            if !agrees(record, mode) { mismatched += 1 }
        }
        guard matched > 0 else {
            return .untrusted(reason: "no SkyLight record matches a CoreGraphics mode")
        }
        guard mismatched == 0 else {
            return .untrusted(reason: "\(mismatched) of \(matched) SkyLight records disagree with CoreGraphics")
        }
        return .trusted(records: decoded, hidden: hidden)
    }

    static func agrees(_ record: PrivateModeRecord, _ mode: DisplayMode) -> Bool {
        record.width == mode.width
            && record.height == mode.height
            && record.pixelWidth == mode.pixelWidth
            && record.pixelHeight == mode.pixelHeight
            && abs(record.refreshRate - mode.refreshRate) < 0.01
            && abs(record.scale - mode.scale) < 0.01
            && record.ioFlags == mode.ioFlags
    }
}
