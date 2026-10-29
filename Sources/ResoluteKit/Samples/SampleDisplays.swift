import CoreGraphics
import Foundation

/// The displays the design shows, for the app's gallery, previews and tests: a 16-inch
/// MacBook Pro's built-in display, a 4K DELL U2723QE, an ASUS PA278QV without Retina sizes,
/// and an LG UltraFine 5K that is not connected. Every value is fixed, so they look the same
/// on any Mac.
public enum SampleDisplays {
    /// A connected display and what macOS reports about it.
    public struct Sample: Hashable, Sendable, Identifiable {
        public var display: Display
        public var details: DisplayDetails

        public init(display: Display, details: DisplayDetails) {
            self.display = display
            self.details = details
        }

        public var id: CGDirectDisplayID { display.id }
        public var facts: DisplayFacts { DisplayFacts(display: display, details: details) }
        public var stops: SpaceStops? { SpaceStops(display: display) }
        public var skin: DisplaySkin { DisplaySkin.suggestion(for: display, details: details) }
    }

    /// A display that is away, known by its override file.
    public struct NotConnected: Equatable, Sendable, Identifiable {
        public var name: String
        public var key: OverrideKey
        public var nativeSize: DisplayFacts.PixelSize
        public var physicalSize: DisplayDetails.PhysicalSize
        public var lastConnected: Date
        public var skin: DisplaySkin
        /// Its override file, as `OverrideStore` reads it.
        public var override: DisplayOverride

        public init(
            name: String,
            key: OverrideKey,
            nativeSize: DisplayFacts.PixelSize,
            physicalSize: DisplayDetails.PhysicalSize,
            lastConnected: Date,
            skin: DisplaySkin,
            override: DisplayOverride
        ) {
            self.name = name
            self.key = key
            self.nativeSize = nativeSize
            self.physicalSize = physicalSize
            self.lastConnected = lastConnected
            self.skin = skin
            self.override = override
        }

        public var id: OverrideKey { key }
    }

    /// The main display, at its default 1728 × 1117 and 120 Hz. Its modes are the ones
    /// captured from a 16-inch MacBook Pro (M2 Pro) on macOS 27, at the four rates the
    /// design shows; the size is what that Mac reports.
    public static let builtInRetina = Sample(
        display: Display(
            id: 1, name: "Built-in Retina Display", vendorID: 0x610, productID: 0xA050,
            isBuiltin: true, isMain: true,
            currentModeID: 54,
            modes: builtInModes(),
            privateModes: .trusted
        ),
        details: DisplayDetails(
            physicalSize: .init(width: 344.24, height: 222.52),
            macModel: "Mac14,10",
            macName: "MacBook Pro (16-inch, 2023)"
        )
    )

    /// A 27-inch 4K monitor at 2560 × 1440 HiDPI and 60 Hz. It lists seven HiDPI sizes
    /// (1920 × 1080 is the default) and twelve 1× ones, and SkyLight adds three hidden sizes:
    /// 2880 × 1620, 2560 × 1080 (21:9) and 2048 × 1152. Its IDs are the ones in the design's
    /// override path, DisplayVendorID-10ac/DisplayProductID-42a3.
    public static let dellU2723QE: Sample = {
        let modes = dellModes()
        return Sample(
            display: Display(
                id: 2, name: "DELL U2723QE", vendorID: 0x10AC, productID: 0x42A3,
                currentModeID: modeID(in: modes, width: 2560, height: 1440, scale: 2, rate: 60),
                modes: modes,
                privateModes: .trusted
            ),
            details: DisplayDetails(physicalSize: .init(width: 597, height: 336))
        )
    }()

    /// A 27-inch 2560 × 1440 monitor with 1× sizes only, at its native size and 75 Hz. As in
    /// the design, its size is marked native, not default. The product ID is made up.
    public static let asusPA278QV: Sample = {
        let modes = asusModes()
        return Sample(
            display: Display(
                id: 3, name: "ASUS PA278QV", vendorID: 0x469, productID: 0x27A1,
                currentModeID: modeID(in: modes, width: 2560, height: 1440, scale: 1, rate: 75),
                modes: modes,
                privateModes: .trusted
            ),
            details: DisplayDetails(physicalSize: .init(width: 597, height: 336))
        )
    }()

    /// A 27-inch 5K display last connected on 21 October 2026, whose override adds 2560 ×
    /// 1440 and 3200 × 1800 HiDPI and 5120 × 2880 1×. Vendor 1e6d is LG; product 5b11 is the
    /// LG display macOS ships a 5K override for.
    public static let lgUltraFine5K: NotConnected = {
        let key = OverrideKey(vendorID: 0x1E6D, productID: 0x5B11)
        return NotConnected(
            name: "LG UltraFine 5K",
            key: key,
            nativeSize: .init(width: 5120, height: 2880),
            physicalSize: .init(width: 597, height: 336),
            // 21 October 2026, 12:00 UTC: the same day in nearly every time zone.
            lastConnected: Date(timeIntervalSince1970: 1_792_584_000),
            skin: .display,
            override: DisplayOverride(
                key: key,
                resolutions: [
                    .hiDPI(width: 2560, height: 1440, flags: .standard),
                    .hiDPI(width: 3200, height: 1800, flags: .standard),
                    .standard(width: 5120, height: 2880),
                ],
                isNew: false
            )
        )
    }()

    /// The connected samples, built-in first.
    public static let all: [Sample] = [builtInRetina, dellU2723QE, asusPA278QV]

    // MARK: - Modes

    private static let nativeFlags = DisplayMode.Flag.valid | DisplayMode.Flag.safe | DisplayMode.Flag.native

    /// The capture's sizes, each with six modes numbered from `first`: 120, 60, 59.94, 50,
    /// 48 and 47.95 Hz. The sample keeps 120, 60, 50 and 48 Hz under the capture's IDs.
    private static func builtInModes() -> [DisplayMode] {
        let sizes: [(first: Int32, width: Int, height: Int, scale: Int)] = [
            (0, 960, 600, 2), (6, 1168, 730, 2), (12, 1168, 755, 2), (18, 1280, 800, 2),
            (24, 1312, 820, 2), (30, 1312, 848, 2), (36, 1496, 935, 2), (42, 1496, 967, 2),
            (48, 1728, 1080, 2), (54, 1728, 1117, 2), (60, 1920, 1200, 1), (66, 2056, 1285, 2),
            (72, 2056, 1329, 2), (78, 2336, 1460, 1), (84, 2336, 1510, 1), (90, 2560, 1600, 1),
            (96, 2624, 1640, 1), (102, 2624, 1696, 1), (108, 2992, 1870, 1), (114, 2992, 1934, 1),
            (120, 3456, 2160, 1), (126, 3456, 2234, 1),
        ]
        let rates: [(offset: Int32, hertz: Double)] = [(0, 120), (1, 60), (3, 50), (4, 48)]
        return sizes.flatMap { size in
            rates.map { rate in
                let id = size.first + rate.offset
                let pixelWidth = size.width * size.scale
                let pixelHeight = size.height * size.scale
                var flags = DisplayMode.Flag.valid | DisplayMode.Flag.safe
                if pixelWidth == 3456 && pixelHeight == 2234 { flags |= DisplayMode.Flag.native }
                if id == 54 { flags |= DisplayMode.Flag.defaultMode }
                return DisplayMode(
                    modeID: id, privateIndex: id, width: size.width, height: size.height,
                    pixelWidth: pixelWidth, pixelHeight: pixelHeight, refreshRate: rate.hertz,
                    bitsPerSample: 10, ioFlags: flags
                )
            }
        }
    }

    private static func dellModes() -> [DisplayMode] {
        var list = SampleModeList()
        let panelRates: [Double] = [60, 50, 30]
        for (width, height) in [(3360, 1890), (3008, 1692), (2560, 1440), (2304, 1296)] {
            list.add(width, height, scale: 2, rates: panelRates)
        }
        list.add(1920, 1080, scale: 2, rates: panelRates, flags: nativeFlags, defaultRate: 60)
        for (width, height) in [(1600, 900), (1280, 720)] {
            list.add(width, height, scale: 2, rates: panelRates)
        }
        list.add(3840, 2160, rates: panelRates, flags: nativeFlags)
        let oneX = [
            (3200, 1800), (2560, 1440), (2048, 1152), (1920, 1080), (1680, 1050), (1600, 900),
            (1440, 900), (1280, 1024), (1280, 720), (1024, 768), (800, 600),
        ]
        for (width, height) in oneX {
            list.add(width, height, rates: [60])
        }
        for (width, height) in [(2880, 1620), (2560, 1080), (2048, 1152)] {
            list.add(width, height, scale: 2, rates: [60], flags: DisplayMode.Flag.valid, origin: .hidden)
        }
        return list.modes
    }

    private static func asusModes() -> [DisplayMode] {
        var list = SampleModeList()
        list.add(2560, 1440, rates: [75, 60, 50], flags: nativeFlags)
        list.add(2048, 1152, rates: [60])
        list.add(1920, 1080, rates: [75, 60, 50])
        let others = [
            (1680, 1050), (1600, 900), (1440, 900), (1366, 768), (1280, 1024), (1280, 800),
            (1280, 720), (1152, 864), (1024, 768), (800, 600), (640, 480),
        ]
        for (width, height) in others {
            list.add(width, height, rates: [60])
        }
        return list.modes
    }

    private static func modeID(in modes: [DisplayMode], width: Int, height: Int, scale: Int, rate: Double) -> Int32? {
        modes.first {
            $0.width == width && $0.height == height && $0.pixelWidth == width * scale
                && $0.refreshKey == RefreshRate.key(rate)
        }?.modeID
    }
}

/// Modes in the order they are added, numbered from 1 as CoreGraphics numbers an external
/// display's modes, each at its position in the private list, as `ModeMerge` leaves them.
private struct SampleModeList {
    var modes: [DisplayMode] = []

    mutating func add(
        _ width: Int,
        _ height: Int,
        scale: Int = 1,
        rates: [Double],
        flags: UInt32 = DisplayMode.Flag.valid | DisplayMode.Flag.safe,
        defaultRate: Double? = nil,
        origin: DisplayMode.Origin = .system
    ) {
        for rate in rates {
            modes.append(DisplayMode(
                modeID: Int32(modes.count + 1),
                privateIndex: Int32(modes.count),
                width: width,
                height: height,
                pixelWidth: width * scale,
                pixelHeight: height * scale,
                refreshRate: rate,
                bitsPerSample: 8,
                ioFlags: rate == defaultRate ? flags | DisplayMode.Flag.defaultMode : flags,
                origin: origin
            ))
        }
    }
}
