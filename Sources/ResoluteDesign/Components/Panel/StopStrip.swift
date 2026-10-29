import SwiftUI

/// The five "Larger Text ↔ More Space" sizes of a Retina-style display, as pictures that
/// switch at once when clicked, with the current size under them (Figma: Display Card's
/// Scale and Caption, 18:44 and 18:100).
///
/// Give the sizes Larger Text first. Each choice's title is its size ("1496 × 967"), which
/// VoiceOver reads and the pointer's help tag shows; the caption names the current size,
/// "1728 × 1117 · Default". When the current mode is none of the five, select none.
public struct StopStrip: View {
    public var stops: [PanelChoice]
    public var caption: String
    public var tone: SpaceThumbnail.Tone

    public init(_ stops: [PanelChoice], caption: String, tone: SpaceThumbnail.Tone) {
        self.stops = stops
        self.caption = caption
        self.tone = tone
    }

    public var body: some View {
        VStack(spacing: PanelMetrics.Card.spacing) {
            pictures
            captions
        }
    }

    private var pictures: some View {
        let drawings = Self.thumbnailStops(count: stops.count)
        return HStack(spacing: Metrics.DisplayCard.thumbnailSpacing) {
            ForEach(stops.indices, id: \.self) { index in
                let stop = stops[index]
                Button(action: stop.select) {
                    SpaceThumbnail(stop: drawings[index], tone: tone, isSelected: stop.isSelected)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(stop.title)
                .accessibilityLabel(stop.spokenLabel)
                .accessibilityAddTraits(stop.isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Larger Text to More Space")
    }

    private var captions: some View {
        HStack(spacing: 0) {
            Text("Larger Text")
                .panelTextStyle(.footnote)
                .foregroundStyle(Palette.labelTertiary)
                .accessibilityHidden(true)
            Spacer(minLength: Metrics.Spacing.xSmall)
            Text(caption)
                .panelTextStyle(.footnote, weight: .semibold)
                .foregroundStyle(Palette.labelPrimary)
                .accessibilityLabel(PanelSpeech.text(caption))
            Spacer(minLength: Metrics.Spacing.xSmall)
            Text("More Space")
                .panelTextStyle(.footnote)
                .foregroundStyle(Palette.labelTertiary)
                .accessibilityHidden(true)
        }
        .lineLimit(1)
    }

    /// Which of `SpaceThumbnail`'s five drawings stands for each of `count` sizes: all five
    /// for five sizes, otherwise spread evenly from Larger Text (1) to More Space (5).
    static func thumbnailStops(count: Int) -> [Int] {
        let range = SpaceThumbnail.stops
        guard count > 1 else { return count == 1 ? [(range.lowerBound + range.upperBound) / 2] : [] }
        let span = Double(range.upperBound - range.lowerBound)
        return (0..<count).map { index in
            range.lowerBound + Int((Double(index) * span / Double(count - 1)).rounded())
        }
    }
}
