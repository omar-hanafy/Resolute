import Foundation

/// A setup to come back to: a mode for every display it names, and whether the displays
/// mirror each other. Applying one switches only to modes macOS lists, so nothing has to be
/// tried with Keep or Revert first.
public struct Preset: Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Unique among presets, ignoring case.
    public var name: String
    /// In the order the summary names them.
    public var displays: [DisplaySetting]
    /// Turns mirroring on or off; nil leaves it as it is.
    public var mirroring: Bool?
    public var shortcut: KeyShortcut?

    public init(
        id: UUID = UUID(),
        name: String,
        displays: [DisplaySetting],
        mirroring: Bool? = nil,
        shortcut: KeyShortcut? = nil
    ) {
        self.id = id
        self.name = name
        self.displays = displays
        self.mirroring = mirroring
        self.shortcut = shortcut
    }
}

/// What a preset asks of one display: a resolution, a refresh rate, or both.
public struct DisplaySetting: Hashable, Sendable {
    /// A width and a height, in points or in pixels.
    public struct Size: Hashable, Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        /// "1496 × 967"
        public var text: String { "\(width) × \(height)" }
    }

    public var display: DisplayReference
    /// The resolution in points. Nil keeps the one the display uses.
    public var size: Size?
    /// The pixels `size` is drawn with: twice the points for HiDPI, as many for 1×. Nil
    /// takes either, preferring the scale the display uses now, else HiDPI.
    public var pixelSize: Size?
    /// Nil keeps the current rate when the resolution offers it, else takes the fastest.
    public var refreshRate: Double?

    public init(display: DisplayReference, size: Size? = nil, pixelSize: Size? = nil, refreshRate: Double? = nil) {
        self.display = display
        self.size = size
        self.pixelSize = pixelSize
        self.refreshRate = refreshRate
    }

    /// The setting that puts `display` back in `mode`.
    public init(display: Display, mode: DisplayMode) {
        self.init(
            display: DisplayReference(display),
            size: Size(width: mode.width, height: mode.height),
            pixelSize: Size(width: mode.pixelWidth, height: mode.pixelHeight),
            // A display that reports no rate gets whichever its resolution has.
            refreshRate: mode.refreshKey > 0 ? mode.refreshRate : nil
        )
    }

    /// Whether the resolution is a HiDPI one; nil when the setting leaves the scale open.
    public var isHiDPI: Bool? {
        guard let size, let pixelSize else { return nil }
        return pixelSize.width > size.width
    }
}

/// Which display a setting is for. CoreGraphics' display IDs can change when a display
/// reconnects, so a display is known by its hardware identity, with being built in and its
/// name to fall back on.
public struct DisplayReference: Hashable, Sendable {
    public var vendorID: UInt32
    public var productID: UInt32
    /// 0 when the display reports none, as many do.
    public var serialNumber: UInt32
    public var isBuiltin: Bool
    /// The display's name when the preset was saved.
    public var name: String

    public init(vendorID: UInt32 = 0, productID: UInt32 = 0, serialNumber: UInt32 = 0, isBuiltin: Bool = false, name: String) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.isBuiltin = isBuiltin
        self.name = name
    }

    public init(_ display: Display) {
        self.init(
            vendorID: display.vendorID, productID: display.productID, serialNumber: display.serialNumber,
            isBuiltin: display.isBuiltin, name: display.name
        )
    }

    /// How summaries name the display: "Built-in" for the built-in one, else its name.
    public var label: String {
        isBuiltin ? "Built-in" : name
    }

    /// How messages name the display: its saved name, or "the built-in display" for a
    /// built-in one written without a name.
    public var displayName: String {
        name.isEmpty && isBuiltin ? "the built-in display" : name
    }

    /// Whether the vendor and product IDs are known. Both are 0 for a display written by
    /// name alone, and such displays are not all one model.
    var knowsModel: Bool {
        vendorID != 0 || productID != 0
    }

    func isSameModel(as display: Display) -> Bool {
        knowsModel && vendorID == display.vendorID && productID == display.productID
    }
}

// MARK: - Summaries

extension DisplaySetting {
    /// What the setting sets, without the display: "1496 × 967", "2560 × 1440 at 60 Hz" or
    /// "120 Hz".
    public var modeText: String {
        let rate = refreshRate.map(RefreshRate.format) ?? ""
        guard let size else { return rate }
        return rate.isEmpty ? size.text : "\(size.text) at \(rate)"
    }

    /// "Built-in 1496 × 967", "DELL U2723QE 2560 × 1440 at 60 Hz" or "Built-in 120 Hz".
    public var summary: String {
        modeText.isEmpty ? display.label : "\(display.label) \(modeText)"
    }
}

extension Preset {
    /// The line on the preset's card: "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at
    /// 60 Hz", or "Mirroring on · 1920 × 1080 at 60 Hz".
    public var summary: String {
        var parts: [String] = []
        switch mirroring {
        case true?:
            parts.append("Mirroring on")
            // Mirrored displays show one picture, so a mode they share is said once.
            let modes = Set(displays.map(\.modeText))
            if modes.count == 1, let shared = modes.first, !shared.isEmpty {
                return (parts + [shared]).joined(separator: " · ")
            }
        case false? where displays.isEmpty:
            parts.append("Mirroring off")
        default:
            break
        }
        return (parts + displays.map(\.summary)).joined(separator: " · ")
    }

    /// The summary as VoiceOver should read it: "by" for "×", which it reads as "multiplied
    /// by", and commas between the parts.
    public var spokenSummary: String {
        summary.replacingOccurrences(of: " × ", with: " by ").replacingOccurrences(of: " · ", with: ", ")
    }
}
