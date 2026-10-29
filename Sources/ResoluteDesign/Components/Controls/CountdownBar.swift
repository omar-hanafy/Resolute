import SwiftUI

/// The trial dialog's countdown (Figma 28:34, the kit's medium determinate progress bar):
/// the share of the trial that is left, emptying toward the revert.
///
/// Redraw it as time passes (a `TimelineView` gives a smooth bar); it doesn't animate on
/// its own. It is a native progress indicator to VoiceOver, labeled "Time left".
public struct CountdownBar: View {
    /// The share of the time left, from 0 (none) to 1 (all of it).
    public var fraction: Double
    /// The seconds left, which VoiceOver reads when known.
    public var remaining: TimeInterval?

    /// - Parameter fraction: the share of the time left; values outside 0...1 are clamped.
    public init(fraction: Double) {
        self.fraction = Self.clamped(fraction)
        remaining = nil
    }

    /// A bar for `remaining` seconds left of `total`.
    public init(remaining: TimeInterval, total: TimeInterval) {
        fraction = Self.fraction(remaining: remaining, total: total)
        self.remaining = remaining.isFinite ? max(0, remaining) : nil
    }

    public var body: some View {
        ProgressView(value: fraction)
            .progressViewStyle(CountdownBarStyle())
            .accessibilityLabel(Text("Time left"))
            .accessibilityValue(Text(accessibilityValue))
    }

    /// The share of `total` that `remaining` is, between 0 and 1. A trial with no length
    /// has nothing left.
    public static func fraction(remaining: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0, total.isFinite else { return 0 }
        return clamped(remaining / total)
    }

    static func clamped(_ fraction: Double) -> Double {
        fraction.isNaN ? 0 : min(max(fraction, 0), 1)
    }

    var accessibilityValue: String {
        guard let remaining else { return "\(Int((fraction * 100).rounded())) percent" }
        let seconds = Int(remaining.rounded(.up))
        return seconds == 1 ? "1 second" : "\(seconds) seconds"
    }
}

/// The bar: a capsule track with a hairline, filled with the accent from the leading edge.
private struct CountdownBarStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let fraction = configuration.fractionCompleted ?? 0
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.progressTrack)
                Capsule().strokeBorder(Palette.progressTrackStroke, lineWidth: Metrics.Countdown.strokeWidth)
                if fraction > 0 {
                    // Never narrower than it is tall, so the last moments stay a round dot.
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: max(height, proxy.size.width * fraction))
                }
            }
        }
        .frame(height: Metrics.Countdown.height)
    }
}
