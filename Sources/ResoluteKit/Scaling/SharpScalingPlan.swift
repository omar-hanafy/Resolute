import Foundation

/// The sharp sizes Sharp Scaling gives a standard display: five steps from Larger Text to
/// More Space that end at the panel's own size, each drawn at twice its size.
public struct SharpScalingPlan: Hashable, Sendable {
    /// One size on the scale.
    public struct Step: Hashable, Sendable, Identifiable {
        public var size: SharpSize
        /// How much larger text looks than at the panel's own size, in percent, rounded:
        /// 60 for 1600 × 900 on a 2560 × 1440 panel, 0 for the panel's own size.
        public var textLarger: Int
        /// Whether this Mac can draw the size. One it can't is left out.
        public var fits: Bool

        public var id: SharpSize { size }

        public init(size: SharpSize, textLarger: Int, fits: Bool) {
            self.size = size
            self.textLarger = textLarger
            self.fits = fits
        }
    }

    /// Why a display can't have Sharp Scaling.
    public enum Unavailable: Hashable, Sendable {
        /// A built-in display is a Retina display.
        case builtIn
        /// macOS already offers HiDPI sizes for it, so it has Larger Text ↔ More Space.
        case alreadyHiDPI
        /// None of its modes says how many pixels its panel has.
        case unknownPanel
    }

    /// The panel's own resolution in pixels. The last step is this size in points.
    public var native: SharpSize
    public var limit: DrawingLimit
    /// Every step, Larger Text first, including those this Mac can't draw.
    public var steps: [Step]

    public init(native: SharpSize, limit: DrawingLimit) {
        self.native = native
        self.limit = limit
        steps = Self.ladder(for: native).map { size in
            Step(size: size, textLarger: Self.textLarger(size, native: native), fits: limit.allows(size))
        }
    }

    /// The plan for `display`'s panel; nil when its resolution is unknown. `record` is the
    /// display's Sharp Scaling record, if any, whose 1× entries are not the panel.
    public init?(display: Display, limit: DrawingLimit, record: SharpScalingRecord? = nil) {
        guard let native = Self.nativeSize(of: display, record: record) else { return nil }
        self.init(native: native, limit: limit)
    }

    /// What setup offers, all on by default: the sizes this Mac can draw.
    public var sizes: [SharpSize] { steps.filter(\.fits).map(\.size) }

    /// The step for `size`, if it is one.
    public func step(for size: SharpSize) -> Step? {
        steps.first { $0.size == size }
    }

    // MARK: - Ladders

    /// The steps as fractions of the panel's width. A panel whose shorter side is under 2160
    /// pixels (1080p, 1440p, 16:10 and ultrawide panels) gets the steps the design gives a
    /// 1440p panel: text 60%, 33%, 25% and 11% larger, then the panel's own size. A 4K-class
    /// panel is dense enough that its own size makes text small, so it starts at half its
    /// size, drawn pixel for pixel like macOS's own default for 4K displays: text 100%, 50%,
    /// 25% and 11% larger, then its own size.
    static let standardSteps: [Double] = [5.0 / 8, 3.0 / 4, 4.0 / 5, 9.0 / 10, 1]
    static let denseSteps: [Double] = [1.0 / 2, 2.0 / 3, 4.0 / 5, 9.0 / 10, 1]
    /// The shorter side from which a panel counts as 4K-class.
    static let densePanelSide = 2160

    /// The sizes for a panel of `native` pixels, Larger Text first and ending at `native`.
    /// Sizes past the panel's own would need a pipe to shrink the drawing to less than half,
    /// which Apple silicon's display pipes don't do (see `DrawingLimit`).
    public static func ladder(for native: SharpSize) -> [SharpSize] {
        let fractions = min(native.width, native.height) >= densePanelSide ? denseSteps : standardSteps
        var sizes: [SharpSize] = []
        for fraction in fractions {
            let size = fraction == 1 ? native : scaled(native, by: fraction)
            // Tiny panels can round two steps to one size, or go below what an override holds.
            if let last = sizes.last, size.width <= last.width { continue }
            guard (try? OverrideDraft.validate(size.entry)) != nil else { continue }
            sizes.append(size)
        }
        return sizes
    }

    /// `native` scaled by `fraction`. The aspect ratio stays exact when its whole-number
    /// steps are fine enough, as a 16:9 panel's 16 × 9 are, so macOS scales the drawing evenly;
    /// otherwise the width is rounded to an even number and the height follows.
    static func scaled(_ native: SharpSize, by fraction: Double) -> SharpSize {
        let divisor = greatestCommonDivisor(native.width, native.height)
        let unitWidth = native.width / divisor, unitHeight = native.height / divisor
        if unitWidth * 32 <= native.width {
            let multiple = max(1, Int((Double(divisor) * fraction).rounded()))
            return SharpSize(width: unitWidth * multiple, height: unitHeight * multiple)
        }
        let width = max(2, Int((Double(native.width) * fraction / 2).rounded()) * 2)
        let height = max(1, Int((Double(width) * Double(native.height) / Double(native.width)).rounded()))
        return SharpSize(width: width, height: height)
    }

    /// How much larger text looks at `size` than at the panel's own size, in percent.
    static func textLarger(_ size: SharpSize, native: SharpSize) -> Int {
        guard size.width > 0 else { return 0 }
        return Int(((Double(native.width) / Double(size.width) - 1) * 100).rounded())
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        b == 0 ? max(a, 1) : greatestCommonDivisor(b, a % b)
    }

    // MARK: - Displays

    /// The resolution of `display`'s panel: the 1× mode macOS marks native, else its 1×
    /// default, else its largest 1× mode. Only listed modes count, and never a 1× entry that
    /// `record` says Sharp Scaling paired with a sharp size, which macOS may list as a larger
    /// 1× mode.
    public static func nativeSize(of display: Display, record: SharpScalingRecord? = nil) -> SharpSize? {
        let partners = Set((record?.partners ?? []).compactMap { $0.pixelSize.map { SharpSize(width: $0.width, height: $0.height) } })
        let candidates = display.modes.filter { mode in
            mode.origin == .system && !mode.isHiDPI && mode.width > 1 && mode.height > 1 && !partners.contains(SharpSize(mode))
        }
        func largest(_ modes: [DisplayMode]) -> DisplayMode? {
            modes.max { ($0.width * $0.height, $0.width) < ($1.width * $1.height, $1.width) }
        }
        let mode = largest(candidates.filter(\.isNative)) ?? largest(candidates.filter(\.isDefault)) ?? largest(candidates)
        return mode.map { SharpSize($0) }
    }

    /// Why `display` can't have Sharp Scaling; nil when it can. `installed` is its installed
    /// override: HiDPI sizes listed there, Sharp Scaling's own or ones added in Custom
    /// Resolutions, don't make it a Retina display.
    public static func unavailability(for display: Display, installed: DisplayOverride?) -> Unavailable? {
        if display.isBuiltin { return .builtIn }
        let record = installed.flatMap { try? SharpScalingRecord(in: $0) }
        guard nativeSize(of: display, record: record) != nil else { return .unknownPanel }
        let written = Set((installed?.resolutions ?? []).compactMap { entry -> SharpSize? in
            guard case .hiDPI(let width, let height, _)? = entry.describedMode else { return nil }
            return SharpSize(width: width, height: height)
        })
        let offersOwnHiDPI = display.modes.contains { $0.origin == .system && $0.isHiDPI && !written.contains(SharpSize($0)) }
        return offersOwnHiDPI ? .alreadyHiDPI : nil
    }

    /// The sharp size to move to from `current`: the same size, so nothing on screen changes
    /// size; else the one of `sizes` nearest its width, the larger on a tie. Without a
    /// current mode, the panel's own size when it is among `sizes`, else the largest.
    public static func switchTarget(from current: DisplayMode?, among sizes: [SharpSize], native: SharpSize?) -> SharpSize? {
        guard let current else {
            return native.flatMap { sizes.contains($0) ? $0 : nil } ?? sizes.max()
        }
        let size = SharpSize(current)
        if sizes.contains(size) { return size }
        return sizes.min { lhs, rhs in
            let left = abs(lhs.width - size.width), right = abs(rhs.width - size.width)
            return left != right ? left < right : lhs.width > rhs.width
        }
    }
}
