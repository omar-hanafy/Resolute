import CoreGraphics
import Foundation
import IOKit

/// What macOS reports about a display beyond its modes: the size of its picture and, for a
/// built-in display, the Mac it is part of. `Display` carries neither, so its JSON and the
/// fakes that stand in for `DisplayControlling` stay as they are: the app reads details with
/// `read(for:)`, and samples and tests make their own.
public struct DisplayDetails: Hashable, Sendable, Codable {
    /// A width and height in millimetres.
    public struct PhysicalSize: Hashable, Sendable, Codable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }

        public var diagonalInches: Double {
            (width * width + height * height).squareRoot() / 25.4
        }
    }

    /// The visible area, as the display reports it; nil when it reports none.
    public var physicalSize: PhysicalSize?
    /// For a built-in display, the model identifier of its Mac ("Mac14,10").
    public var macModel: String?
    /// For a built-in display on Apple silicon, its Mac's name ("MacBook Pro (16-inch, 2023)").
    public var macName: String?

    public init(physicalSize: PhysicalSize? = nil, macModel: String? = nil, macName: String? = nil) {
        self.physicalSize = physicalSize
        self.macModel = macModel
        self.macName = macName
    }

    /// True when the display is an iMac's own screen. Intel and M1 iMacs say so in their
    /// model identifier; later ones are "Mac15,4" and the like, so their name decides, with
    /// the identifiers known so far for a Mac that has no name to read.
    public var isIMacScreen: Bool {
        if macName?.hasPrefix("iMac") == true { return true }
        guard let macModel else { return false }
        return macModel.hasPrefix("iMac") || Self.appleSiliconIMacModels.contains(macModel)
    }

    /// M3 and M4 iMacs.
    static let appleSiliconIMacModels: Set<String> = ["Mac15,4", "Mac15,5", "Mac16,2", "Mac16,3"]

    // MARK: - Reading

    /// What macOS reports for `display` now. Reads only; nothing changes.
    public static func read(for display: Display) -> DisplayDetails {
        let mac = display.isBuiltin ? thisMac : nil
        return DisplayDetails(
            physicalSize: physicalSize(
                reported: CGDisplayScreenSize(display.id),
                bounds: CGDisplayBounds(display.id).size
            ),
            macModel: mac?.model,
            macName: mac?.name
        )
    }

    /// The size CoreGraphics reports, or nil when it is none: zero, or the guess CoreGraphics
    /// makes for a display that gives no size, its bounds at 72 dpi, which would make a 4K
    /// TV look like a 61-inch one.
    static func physicalSize(reported: CGSize, bounds: CGSize) -> PhysicalSize? {
        guard reported.width.isFinite, reported.height.isFinite, reported.width > 0, reported.height > 0 else {
            return nil
        }
        let guessed = CGSize(width: bounds.width * 25.4 / 72, height: bounds.height * 25.4 / 72)
        if abs(reported.width - guessed.width) < 1, abs(reported.height - guessed.height) < 1 {
            return nil
        }
        return PhysicalSize(width: Double(reported.width), height: Double(reported.height))
    }

    /// This Mac's model identifier and, on Apple silicon, its name. Read once: neither
    /// changes while Resolute runs.
    static let thisMac: (model: String?, name: String?) = (systemString("hw.model"), deviceTreeProductName())

    private static func systemString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    /// The name Apple silicon Macs carry in their device tree, such as "iMac (24-inch, 2023)".
    private static func deviceTreeProductName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        guard let data = value as? Data else { return nil }
        let text = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
        return text.isEmpty ? nil : text
    }
}
