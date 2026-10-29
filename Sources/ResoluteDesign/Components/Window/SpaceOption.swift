import SwiftUI

/// One of the large "Larger Text ↔ More Space" sizes in the window, like System Settings ›
/// Displays: a picture of the desktop at that size, the size, and an optional caption such
/// as "Default" (Figma: Components › Space Option, Default and Selected). It is 116 points
/// wide, 116 high with a caption and 96 without, and narrows with its picture when it has
/// to.
public struct SpaceOption: View {
    /// Which of the five pictures to draw, 1 (largest text) to 5 (most space).
    public var stop: Int
    public var tone: SpaceThumbnail.Tone
    /// "1728 × 1117".
    public var size: String
    /// "Default", "Larger Text", "Same as now".
    public var caption: String?
    public var isSelected: Bool

    public init(stop: Int, tone: SpaceThumbnail.Tone, size: String, caption: String? = nil, isSelected: Bool = false) {
        self.stop = stop
        self.tone = tone
        self.size = size
        self.caption = caption
        self.isSelected = isSelected
    }

    public var body: some View {
        VStack(spacing: WindowMetrics.Space.spacing) {
            SpaceThumbnail(stop: stop, tone: tone, isSelected: isSelected)
                .aspectRatio(WindowMetrics.Space.thumbnailSize.width / WindowMetrics.Space.thumbnailSize.height, contentMode: .fit)
                .frame(idealWidth: WindowMetrics.Space.thumbnailSize.width, maxWidth: WindowMetrics.Space.thumbnailSize.width)
            Text(size)
                .textStyle(isSelected ? .calloutEmphasized : .callout)
                .foregroundStyle(isSelected ? Palette.labelPrimary : Palette.labelSecondary)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.labelTertiary)
                    .lineLimit(1)
            }
        }
        .frame(idealWidth: WindowMetrics.Space.thumbnailSize.width, maxWidth: WindowMetrics.Space.thumbnailSize.width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(size: size, caption: caption))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "1728 by 1117, Default".
    static func spokenLabel(size: String, caption: String?) -> String {
        [SpokenText.sizes(size), caption].compactMap { $0 }.joined(separator: ", ")
    }
}
