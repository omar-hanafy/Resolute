import Foundation

/// A width:height ratio in its conventional reduced form.
public struct AspectRatio: Hashable, Sendable, CustomStringConvertible {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        guard width > 0, height > 0 else {
            self.width = 0
            self.height = 0
            return
        }
        let divisor = Self.greatestCommonDivisor(width, height)
        var reduced = (width / divisor, height / divisor)
        // Screens are sold as 16:10 and 21:9, not 8:5 and 7:3.
        if reduced == (8, 5) { reduced = (16, 10) }
        if reduced == (7, 3) { reduced = (21, 9) }
        self.width = reduced.0
        self.height = reduced.1
    }

    /// Common ratios offered by the resolution editor.
    public static let presets: [AspectRatio] = [(16, 9), (16, 10), (21, 9), (32, 9), (64, 27), (4, 3), (3, 2)]
        .map { AspectRatio(width: $0.0, height: $0.1) }

    public var value: Double {
        height > 0 ? Double(width) / Double(height) : 0
    }

    /// "16:9", or "1.55:1" when the reduced numbers are unwieldy.
    public var description: String {
        guard width > 0 else { return "—" }
        if width <= 64 && height <= 64 { return "\(width):\(height)" }
        return String(format: "%.2f:1", value)
    }

    /// The height that gives this ratio at `width`.
    public func height(forWidth width: Int) -> Int {
        guard value > 0 else { return 0 }
        return Int((Double(width) / value).rounded())
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : greatestCommonDivisor(b, a % b)
    }
}
