import SwiftUI

/// The top of a display's page: its picture, its name, a line of facts ("16.2-inch Liquid
/// Retina XDR · 3456 × 2234 pixels · ProMotion up to 120 Hz") and badges such as "Main"
/// and "HiDPI" (Figma: the Display Header of the display pages, 31:5; not connected,
/// 37:1480).
public struct DisplayHeader: View {
    public var name: String
    public var facts: String
    public var picture: DisplayPictureModel
    public var badges: [Badge]
    /// A display that isn't connected: Figma draws its picture faintly.
    public var isPictureDimmed: Bool

    public init(
        name: String,
        facts: String,
        picture: DisplayPictureModel,
        badges: [Badge] = [],
        isPictureDimmed: Bool = false
    ) {
        self.name = name
        self.facts = facts
        self.picture = picture
        self.badges = badges
        self.isPictureDimmed = isPictureDimmed
    }

    public var body: some View {
        HStack(spacing: WindowMetrics.DisplayHeader.spacing) {
            DisplayPicture(picture)
                .frame(width: WindowMetrics.DisplayHeader.pictureSize.width, height: WindowMetrics.DisplayHeader.pictureSize.height)
                .opacity(isPictureDimmed ? WindowMetrics.DisplayHeader.dimmedPictureOpacity : 1)
                // The name says which display this is; the picture repeats it.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WindowMetrics.DisplayHeader.infoSpacing) {
                Text(name)
                    .textStyle(.title1)
                    .foregroundStyle(Palette.labelPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(facts)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(SpokenText.sizes(facts))
                if !badges.isEmpty {
                    HStack(spacing: WindowMetrics.DisplayHeader.badgeSpacing) {
                        ForEach(badges.indices, id: \.self) { index in
                            badges[index]
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}
