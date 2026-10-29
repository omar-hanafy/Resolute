import SwiftUI

/// The panel's segmented choices, filling the width: a display's refresh rates and the
/// HiDPI | Low Resolution (1×) tabs of All Resolutions (Figma: Segment 17:20 in a
/// `surface/track` capsule, Refresh Rates 18:104, Kind 22:385).
///
/// `SegmentedTabs` draws the window's tabs; the panel's segments are shorter than its
/// `.large` size (21 points, not 24), share the width equally and lift the selected one
/// with a shadow, so they are drawn here.
public struct PanelSegments: View {
    public var choices: [PanelChoice]

    public init(_ choices: [PanelChoice]) {
        self.choices = choices
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(choices.indices, id: \.self) { index in
                segment(choices[index])
            }
        }
        .padding(PanelMetrics.Segments.inset)
        .background(Capsule().fill(Palette.surfaceTrack))
        .accessibilityElement(children: .contain)
    }

    private func segment(_ choice: PanelChoice) -> some View {
        Button(action: choice.select) {
            Text(choice.title)
                .panelTextStyle(choice.isSelected ? .calloutEmphasized : .callout)
                .foregroundStyle(Palette.labelPrimary)
                .lineLimit(1)
                // Five refresh rates still fit, a little smaller.
                .minimumScaleFactor(0.8)
                .padding(.horizontal, PanelMetrics.Segments.horizontalPadding)
                .frame(maxWidth: .infinity)
                .frame(height: PanelMetrics.Segments.height)
                .background {
                    if choice.isSelected {
                        Capsule()
                            .fill(Palette.surfaceSelectedControl)
                            .shadow(color: PanelPalette.segmentShadow, radius: 0.5, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.spokenLabel)
        .accessibilityAddTraits(choice.isSelected ? .isSelected : [])
    }
}
