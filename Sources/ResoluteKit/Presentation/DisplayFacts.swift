import Foundation

/// What the panel card and the display page say about a display: its size, panel, refresh
/// rate and kind (Figma: Display Card, Display Header).
public struct DisplayFacts: Hashable, Sendable {
    /// Whether a display has Retina sizes to choose from.
    public enum Kind: String, Hashable, Sendable, Codable {
        /// HiDPI sizes from Larger Text to More Space (see `SpaceStops`).
        case retina
        /// 1× sizes only, as most 1080p and 1440p monitors have.
        case standard
    }

    /// A size in pixels.
    public struct PixelSize: Hashable, Sendable, Codable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        /// "3456 × 2234"
        public var text: String { "\(width) × \(height)" }

        var aspectRatio: Double { height > 0 ? Double(width) / Double(height) : 0 }
    }

    public var kind: Kind
    /// The diagonal the way Apple gives it: "16.2-inch", "27-inch". Nil when the display
    /// reports no size that fits its pixels.
    public var diagonal: String?
    /// The panel's own pixels.
    public var nativeSize: PixelSize?
    /// The fastest refresh rate the display lists, in hertz.
    public var maximumRefreshRate: Double?
    /// A built-in panel faster than 60 Hz. Every Mac panel that fast adapts its rate.
    public var hasProMotion: Bool
    /// "ProMotion up to 120 Hz", "up to 75 Hz" or "60 Hz".
    public var refresh: String?
    /// The current mode, for the panel card and the window's subtitle: "1728 × 1117 · 120 Hz".
    public var summary: String?
    /// The panel card's badge: "Standard" for a display without Retina sizes, otherwise
    /// "Default" or "Native" when the current size is one, else nil.
    public var badge: String?
    /// How many resolutions All Resolutions lists while hidden modes are off.
    public var resolutionCount: Int

    public init(display: Display, details: DisplayDetails) {
        let groups = ModeCatalog.groups(display.modes)
        let currentKey = ModeCatalog.currentKey(for: display)
        let native = Self.nativeSize(of: display)
        let fastest = Self.fastestListedRate(of: display)

        kind = SpaceStops(display: display) == nil ? .standard : .retina
        nativeSize = native
        diagonal = Self.diagonal(of: details.physicalSize, panel: native, display: display)
        maximumRefreshRate = fastest
        hasProMotion = display.isBuiltin && fastest.map { RefreshRate.key($0) > 6_000 } == true
        refresh = Self.refreshText(for: display, fastest: fastest, proMotion: hasProMotion)
        summary = display.currentMode.map { mode in
            let rate = RefreshRate.format(mode.refreshRate)
            return rate.isEmpty ? mode.sizeText : "\(mode.sizeText) · \(rate)"
        }
        badge = kind == .standard ? "Standard" : groups.first { $0.key == currentKey }?.badge
        resolutionCount = Self.resolutionCount(for: display)
    }

    /// "3456 × 2234 pixels"
    public var nativePixels: String? {
        nativeSize.map { "\($0.text) pixels" }
    }

    /// The display page's line under the name: "16.2-inch · 3456 × 2234 pixels · ProMotion up to 120 Hz".
    public var specifications: String {
        [diagonal, nativePixels, refresh].compactMap { $0 }.joined(separator: " · ")
    }

    /// How many resolutions All Resolutions lists, counted the way `ModeCatalog.sections`
    /// lists them: a hidden mode in use is listed, so it counts.
    public static func resolutionCount(
        for display: Display,
        includeLowResolution: Bool = true,
        includeHidden: Bool = false
    ) -> Int {
        ModeCatalog.sections(for: display, includeLowResolution: includeLowResolution, includeHidden: includeHidden)
            .reduce(0) { $0 + $1.groups.count }
    }

    /// Text as VoiceOver should read it: "1728 × 1117 · 120 Hz" becomes "1728 by 1117, 120 Hz",
    /// since "×" is read as "multiplied by".
    public static func spoken(_ text: String) -> String {
        text.replacingOccurrences(of: " × ", with: " by ").replacingOccurrences(of: " · ", with: ", ")
    }

    // MARK: - Pieces

    /// The panel's own pixels: the modes macOS marks as native, or failing those the largest
    /// 1× mode. Listed modes count first; a hidden mode is not proof of anything.
    static func nativeSize(of display: Display) -> PixelSize? {
        let listed = display.modes.filter { $0.origin == .system }
        let modes = listed.isEmpty ? display.modes : listed
        let byArea: (DisplayMode, DisplayMode) -> Bool = {
            $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight
        }
        guard let mode = modes.filter(\.isNative).max(by: byArea) ?? modes.filter({ !$0.isHiDPI }).max(by: byArea),
              mode.pixelWidth > 0, mode.pixelHeight > 0
        else { return nil }
        return PixelSize(width: mode.pixelWidth, height: mode.pixelHeight)
    }

    /// The sizes Apple gives the displays of the Macs that run Resolute (macOS 14 and later)
    /// and of its own monitors. macOS reports a panel's active area, a little less than that
    /// size (16.14 inches for the 16.2-inch MacBook Pro, about 23.5 for the 24-inch iMac), so
    /// a display Apple made takes the nearest of these within half an inch.
    static let appleDiagonals: [Double] = [13.3, 13.6, 14.2, 15.3, 15.4, 16, 16.2, 21.5, 24, 27, 32]

    /// "16.2-inch" for a built-in panel, which Apple sizes to the tenth. A monitor in whole
    /// inches, as monitors are sold: from a half up, so a 31.5-inch panel is "32-inch", and
    /// from 0.05 below it, since a display reports whole millimetres (697 × 392 mm for that
    /// panel is 31.48 inches). Nil when the size and the pixels disagree: a density outside
    /// 10 to 500 pixels per inch is no real display.
    static func diagonal(of size: DisplayDetails.PhysicalSize?, panel: PixelSize?, display: Display) -> String? {
        guard let size, size.width > 0, size.height > 0 else { return nil }
        let inches = size.diagonalInches
        guard inches.isFinite, inches >= 1 else { return nil }
        if let panel {
            let density = Double(panel.width) / (size.width / 25.4)
            guard (10...500).contains(density) else { return nil }
        }
        if display.isBuiltin || display.vendorID == appleVendorID,
           let marketed = appleDiagonals.min(by: { abs($0 - inches) < abs($1 - inches) }),
           abs(marketed - inches) <= 0.5 {
            return inchText(marketed)
        }
        return inchText(display.isBuiltin ? (inches * 10).rounded() / 10 : (inches + 0.05).rounded())
    }

    static let appleVendorID: UInt32 = 0x610

    private static func inchText(_ inches: Double) -> String {
        let tenths = Int((inches * 10).rounded())
        return tenths % 10 == 0 ? "\(tenths / 10)-inch" : "\(tenths / 10).\(tenths % 10)-inch"
    }

    /// The fastest rate among listed modes; nil when none reports one.
    static func fastestListedRate(of display: Display) -> Double? {
        let keys = display.modes.filter { $0.origin == .system }.map(\.refreshKey).filter { $0 > 0 }
        return keys.max().map { Double($0) / 100 }
    }

    /// "up to" only for a display faster than 60 Hz that also runs slower: 60 Hz is what
    /// every display does, so a 60, 50 and 30 Hz monitor is simply "60 Hz".
    static func refreshText(for display: Display, fastest: Double?, proMotion: Bool) -> String? {
        guard let fastest else { return nil }
        let rate = RefreshRate.format(fastest)
        if proMotion { return "ProMotion up to \(rate)" }
        let rates = Set(display.modes.filter { $0.origin == .system }.map(\.refreshKey).filter { $0 > 0 })
        return RefreshRate.key(fastest) > 6_000 && rates.count > 1 ? "up to \(rate)" : rate
    }
}
