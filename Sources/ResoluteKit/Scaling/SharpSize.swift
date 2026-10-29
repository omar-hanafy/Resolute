import Foundation

/// A size Sharp Scaling offers, in points. macOS draws it at twice as many pixels each way,
/// as it draws a Retina display's sizes, and scales the result to the panel.
public struct SharpSize: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// The size of `mode` in points.
    public init(_ mode: DisplayMode) {
        self.init(width: mode.width, height: mode.height)
    }

    /// Reads "1600x900" or "1600 × 900"; nil for anything else, including sizes no display
    /// could have.
    public init?(_ text: String) {
        let compact = text.lowercased().replacingOccurrences(of: "×", with: "x").replacingOccurrences(of: " ", with: "")
        let parts = compact.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 5 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let width = Int(parts[0]), let height = Int(parts[1]),
              (1...ModeQuery.maximumDimension).contains(width), (1...ModeQuery.maximumDimension).contains(height)
        else { return nil }
        self.init(width: width, height: height)
    }

    /// The pixels macOS draws for this size: twice as many each way.
    public var drawnWidth: Int { width * 2 }
    public var drawnHeight: Int { height * 2 }

    /// "1600 × 900"
    public var sizeText: String { "\(width) × \(height)" }
    /// "3200 × 1800"
    public var drawnText: String { "\(drawnWidth) × \(drawnHeight)" }
    /// "1600x900", the form the command line takes and prints.
    public var description: String { "\(width)x\(height)" }

    /// The HiDPI override entry for this size, with the flags Apple gives most of its own.
    public var entry: ScaleResolution { .hiDPI(width: width, height: height, flags: .standard) }

    /// The 1× entry at the drawn size, which Resolute and RDM pair with each HiDPI entry.
    public var partner: ScaleResolution { .standard(width: drawnWidth, height: drawnHeight) }

    /// Whether `mode` shows this size drawn at twice its size: the sharp mode for it.
    public func isDrawn(by mode: DisplayMode) -> Bool {
        mode.width == width && mode.height == height && mode.pixelWidth == drawnWidth && mode.pixelHeight == drawnHeight
    }

    /// Smaller sizes, which make text larger, sort first.
    public static func < (lhs: SharpSize, rhs: SharpSize) -> Bool {
        (lhs.width, lhs.height) < (rhs.width, rhs.height)
    }
}
