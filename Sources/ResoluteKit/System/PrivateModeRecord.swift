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
    public var bitsPerSample: Int
    public var ioFlags: UInt32
    public var modeID: Int32
    public var scale: Double

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
        guard scale.isFinite, scale > 0, width > 0, height > 0, pixelWidth > 0, pixelHeight > 0 else {
            return nil
        }
        self.index = Int32(bitPattern: word(0x00))
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        // 16.16 fixed point, rounded to the millihertz CoreGraphics reports.
        self.refreshRate = (Double(word(0xBC)) / 65_536 * 1_000).rounded() / 1_000
        self.bitsPerSample = Int(word(0x1C))
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
            bitsPerSample: bitsPerSample > 0 ? bitsPerSample : nil,
            ioFlags: ioFlags,
            origin: origin
        )
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
        for (position, record) in records.enumerated() {
            guard let record else {
                return .untrusted(reason: "record \(position) has an unrecognised layout")
            }
            guard record.index == Int32(position) else {
                return .untrusted(reason: "record \(position) reports index \(record.index)")
            }
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
    }
}
