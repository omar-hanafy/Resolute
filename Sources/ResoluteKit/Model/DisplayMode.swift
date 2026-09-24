import Foundation

/// A display mode: its size in points and pixels, refresh rate, and where it was found.
public struct DisplayMode: Hashable, Sendable, Codable, Identifiable {
    /// Where a mode came from.
    public enum Origin: String, Hashable, Sendable, Codable {
        /// Listed by the public CoreGraphics API.
        case system
        /// Listed only by the private SkyLight API; macOS normally hides it.
        case hidden
    }

    /// Bits of `ioFlags` that Resolute reads (see IOGraphicsTypes.h).
    public enum Flag {
        public static let valid: UInt32 = 0x0000_0001
        public static let safe: UInt32 = 0x0000_0002
        public static let defaultMode: UInt32 = 0x0000_0004
        public static let native: UInt32 = 0x0200_0000
    }

    /// The IO display mode ID (`CGDisplayModeGetIODisplayModeID`).
    public var modeID: Int32
    /// Position in the private SkyLight mode list, when known.
    public var privateIndex: Int32?
    /// Width in points.
    public var width: Int
    /// Height in points.
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Refresh rate in hertz, or 0 when the display does not report one.
    public var refreshRate: Double
    /// Bits per colour component (8, 10, …), when known.
    public var bitsPerSample: Int?
    public var ioFlags: UInt32
    public var origin: Origin

    public var id: Int32 { modeID }

    public init(
        modeID: Int32,
        privateIndex: Int32? = nil,
        width: Int,
        height: Int,
        pixelWidth: Int,
        pixelHeight: Int,
        refreshRate: Double,
        bitsPerSample: Int? = nil,
        ioFlags: UInt32 = 0,
        origin: Origin = .system
    ) {
        self.modeID = modeID
        self.privateIndex = privateIndex
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.bitsPerSample = bitsPerSample
        self.ioFlags = ioFlags
        self.origin = origin
    }

    /// Pixels per point along the horizontal axis (2 for HiDPI modes).
    public var scale: Double {
        width > 0 ? Double(pixelWidth) / Double(width) : 1
    }

    /// True when the mode renders more pixels than points (a Retina/HiDPI mode).
    public var isHiDPI: Bool { pixelWidth > width }

    /// True when macOS marks the mode as the display's default.
    public var isDefault: Bool { ioFlags & Flag.defaultMode != 0 }

    /// True when the mode uses the panel's native pixel size.
    public var isNative: Bool { ioFlags & Flag.native != 0 }

    /// The refresh rate in hundredths of a hertz, for comparisons.
    public var refreshKey: Int { RefreshRate.key(refreshRate) }

    /// "1728 × 1117"
    public var sizeText: String { "\(width) × \(height)" }

    /// "3456 × 2234"
    public var pixelSizeText: String { "\(pixelWidth) × \(pixelHeight)" }
}

/// Comparing and formatting refresh rates.
public enum RefreshRate {
    /// Hundredths of a hertz, so 59.94 and 59.9400024 compare equal.
    public static func key(_ hertz: Double) -> Int {
        Int((hertz * 100).rounded())
    }

    /// "120 Hz", "59.94 Hz", "59.9 Hz"; empty when the rate is unknown.
    public static func format(_ hertz: Double) -> String {
        let key = key(hertz)
        guard key > 0 else { return "" }
        if key % 100 == 0 { return "\(key / 100) Hz" }
        var text = String(format: "%.2f", Double(key) / 100)
        if text.hasSuffix("0") { text.removeLast() }
        return "\(text) Hz"
    }
}
