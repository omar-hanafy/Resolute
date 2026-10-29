import Foundation

/// The sizes a display offers from "Larger Text" to "More Space", as System Settings shows
/// them (Figma: Display Card, Space Option): Retina sizes in the panel's own shape, at most
/// five, with the default among them.
///
/// macOS gives no list of these, so they are worked out from the listed modes. On the
/// 16-inch MacBook Pro this gives exactly the five sizes System Settings shows, which are
/// also the five that Apple's override file for the panel lists.
public struct SpaceStops: Hashable, Sendable {
    /// One size on the scale.
    public struct Stop: Hashable, Sendable, Identifiable {
        public var key: ResolutionGroup.Key
        /// "1728 × 1117"
        public var label: String
        public var isDefault: Bool
        public var isCurrent: Bool
        /// What choosing the stop switches to: the size at the current refresh rate when it
        /// has it (see `ModeCatalog.preferredMode`).
        public var mode: DisplayMode
        /// Which of `SpaceThumbnail`'s pictures, 1 (largest text) to 5 (most space), suits
        /// the stop. Fewer than five stops spread over the five pictures.
        public var thumbnail: Int

        public var id: ResolutionGroup.Key { key }

        /// "1728 by 1117, Default"
        public var accessibilityLabel: String {
            DisplayFacts.spoken(label) + (isDefault ? ", Default" : "")
        }
    }

    public static let maximumCount = 5

    /// Largest text first.
    public var stops: [Stop]
    /// Where the size in use is in `stops`; nil when it is not one of them.
    public var currentIndex: Int?
    /// The size in use, with "Default" or "Native" when it is one ("1728 × 1117 · Default"),
    /// whether or not it is a stop; nil when the mode in use is unknown.
    public var currentLabel: String?

    public var current: Stop? {
        currentIndex.map { stops[$0] }
    }

    /// The stops for `display`, or nil when it has fewer than two sizes to step through:
    /// a standard display, which lists 1× sizes only.
    public init?(display: Display) {
        let groups = ModeCatalog.groups(display.modes)
        let chosen = Self.choose(from: Self.candidates(in: groups, panel: DisplayFacts.nativeSize(of: display)))
        guard chosen.count >= 2 else { return nil }
        let current = display.currentMode
        let currentKey = current.map(ResolutionGroup.Key.init)
        stops = chosen.enumerated().map { index, group in
            Stop(
                key: group.key,
                label: group.sizeText,
                isDefault: group.isDefault,
                isCurrent: group.key == currentKey,
                mode: ModeCatalog.preferredMode(in: group, current: current),
                thumbnail: Self.thumbnail(at: index, of: chosen.count)
            )
        }
        currentIndex = stops.firstIndex(where: \.isCurrent)
        currentLabel = groups.first { $0.key == currentKey }.map { group in
            group.badge.map { "\(group.sizeText) · \($0)" } ?? group.sizeText
        }
    }

    // MARK: - Choosing

    /// Listed HiDPI sizes in the panel's shape, smallest first. Shape is matched within 1%:
    /// the 14-inch MacBook Pro's 1352 × 878 is 0.01% off its panel, while the 16:10 sizes
    /// MacBook Pros also list, which would leave bars, are 3% off. Hidden sizes are left to
    /// All Resolutions, where each is tried first.
    static func candidates(in groups: [ResolutionGroup], panel: DisplayFacts.PixelSize?) -> [ResolutionGroup] {
        let shape = panel?.aspectRatio ?? 0
        return groups
            .filter { $0.isHiDPI && !$0.isHidden && $0.key.width > 0 && $0.key.height > 0 }
            .filter { group in
                shape <= 0 || abs(Double(group.key.width) / Double(group.key.height) / shape - 1) <= 0.01
            }
            .sorted { ($0.key.width, $0.key.height) < ($1.key.width, $1.key.height) }
    }

    /// At most five of `candidates` (smallest first). Only sizes from half to twice the
    /// default's width take part: beyond them text is more than twice or less than half its
    /// default size. When more than five remain, the scale runs from the smallest to the
    /// largest in steps as even as the sizes allow, measured in text size (the logarithm of
    /// the width), and keeps the default.
    static func choose(from candidates: [ResolutionGroup]) -> [ResolutionGroup] {
        guard !candidates.isEmpty else { return [] }
        let reference = candidates.first(where: \.isDefault)
            ?? candidates.first(where: \.isNative)
            ?? candidates[candidates.count / 2]
        let widths = (Double(reference.key.width) / 2)...(Double(reference.key.width) * 2)
        let sizes = candidates.filter { widths.contains(Double($0.key.width)) }
        guard sizes.count > maximumCount else { return sizes }

        let steps = sizes.map { log(Double($0.key.width)) }
        let last = sizes.count - 1
        let targets = (0..<maximumCount).map { position in
            steps[0] + (steps[last] - steps[0]) * Double(position) / Double(maximumCount - 1)
        }
        let defaultIndex = sizes.firstIndex(where: \.isDefault)
        var best: [Int] = []
        var bestDistance = Double.infinity
        for second in 1..<last {
            for third in (second + 1)..<last {
                for fourth in (third + 1)..<last {
                    let picks = [0, second, third, fourth, last]
                    if let defaultIndex, !picks.contains(defaultIndex) { continue }
                    let distance = zip(picks, targets).reduce(0) { sum, pair in
                        sum + (steps[pair.0] - pair.1) * (steps[pair.0] - pair.1)
                    }
                    if distance < bestDistance {
                        best = picks
                        bestDistance = distance
                    }
                }
            }
        }
        return best.map { sizes[$0] }
    }

    /// Spreads `count` stops over the five pictures: three stops get 1, 3 and 5.
    static func thumbnail(at index: Int, of count: Int) -> Int {
        guard count > 1 else { return 3 }
        let spread = Double(index) * Double(maximumCount - 1) / Double(count - 1)
        return 1 + Int(spread.rounded())
    }
}
