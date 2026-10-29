import SwiftUI

/// One display in the panel (Figma: Display Card 18:27, Display Card / Standard 59:704): its
/// picture, name and current mode, with a chevron that opens the display's page in the
/// window; then an optional offer, its sizes, its refresh rates and All Resolutions.
///
/// A Retina-style display offers its sizes as the five "Larger Text ↔ More Space" stops; a
/// display with 1× sizes only, as a Resolution pop-up. Disable the card (`.disabled(true)`)
/// while its display isn't responding: it dims, as in Figma's waiting panel (24:1157).
public struct DisplayCard<Offer: View>: View {
    /// How the card offers the display's sizes.
    public enum Sizes {
        /// A Retina-style display: five pictures from Larger Text to More Space.
        case stops(StopStrip)
        /// A display with 1× sizes only: its resolutions in a pop-up.
        case resolutions([PanelChoice])
    }

    public var name: String
    /// The current mode: "1728 × 1117 · 120 Hz", "Mirroring · 1920 × 1080 · 60 Hz",
    /// "Not responding · trying 2880 × 1620".
    public var summary: String
    public var picture: DisplayPictureModel
    /// "Default", "Standard", or "Sharp" in the accent tone; nil for none.
    public var badge: Badge?
    public var sizes: Sizes
    /// Hidden when empty.
    public var refreshRates: [PanelChoice]
    /// How many modes All Resolutions lists.
    public var resolutionCount: Int
    public var openDisplay: () -> Void
    public var showAllResolutions: () -> Void
    private let offer: Offer

    @Environment(\.isEnabled) private var isEnabled

    public init(
        name: String,
        summary: String,
        picture: DisplayPictureModel,
        badge: Badge? = nil,
        sizes: Sizes,
        refreshRates: [PanelChoice],
        resolutionCount: Int,
        openDisplay: @escaping () -> Void,
        showAllResolutions: @escaping () -> Void,
        @ViewBuilder offer: () -> Offer
    ) {
        self.name = name
        self.summary = summary
        self.picture = picture
        self.badge = badge
        self.sizes = sizes
        self.refreshRates = refreshRates
        self.resolutionCount = resolutionCount
        self.openDisplay = openDisplay
        self.showAllResolutions = showAllResolutions
        self.offer = offer()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.Card.spacing) {
            header
            offer
            switch sizes {
            case .stops(let strip):
                strip
            case .resolutions(let choices):
                resolutionRow(choices)
            }
            if !refreshRates.isEmpty {
                PanelSegments(refreshRates)
                    .accessibilityLabel("Refresh Rate")
            }
            allResolutionsRow
        }
        .padding(PanelMetrics.Card.insets)
        .frame(minHeight: minimumHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: Metrics.DisplayCard.cornerRadius, style: .continuous)
                .fill(Palette.surfaceCard)
        )
        .opacity(isEnabled ? 1 : PanelMetrics.unavailableOpacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(name)
    }

    /// Figma draws a Retina-style card 200 points tall, a few points more than its parts, so
    /// the cards of two displays line up. Without refresh rates it is simply shorter.
    private var minimumHeight: CGFloat? {
        if case .stops = sizes, !refreshRates.isEmpty { return PanelMetrics.Card.stopsHeight }
        return nil
    }

    private var header: some View {
        Button(action: openDisplay) {
            HStack(spacing: PanelMetrics.Card.spacing) {
                DisplayPicture(picture)
                    .frame(width: PanelMetrics.Card.pictureSize.width, height: PanelMetrics.Card.pictureSize.height)
                VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
                    Text(name)
                        .panelTextStyle(.bodyEmphasized)
                        .foregroundStyle(Palette.labelPrimary)
                    HStack(spacing: Metrics.Spacing.small) {
                        Text(summary)
                            .panelTextStyle(.callout)
                            .foregroundStyle(Palette.labelSecondary)
                        if let badge {
                            badge.fixedSize()
                        }
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                PanelIcon(.chevronRight, size: .button)
                    .foregroundStyle(Palette.labelTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headerLabel)
        .accessibilityHint("Opens the display’s page in the Resolute window")
        .accessibilityAddTraits(.isButton)
    }

    /// The header as VoiceOver reads it: "Built-in Retina Display, 1728 by 1117, 120 Hz,
    /// Default".
    var headerLabel: String {
        [name, PanelSpeech.text(summary), badge?.text].compactMap { $0 }.joined(separator: ", ")
    }

    private func resolutionRow(_ choices: [PanelChoice]) -> some View {
        HStack(spacing: Metrics.Spacing.medium) {
            Text("Resolution")
                .panelTextStyle(.callout)
                .foregroundStyle(Palette.labelSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            PanelPopUp(title: "Resolution", choices: choices)
        }
    }

    private var allResolutionsRow: some View {
        Button(action: showAllResolutions) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Palette.strokeHairline)
                    .frame(height: 1)
                HStack(spacing: Metrics.Spacing.small) {
                    Text("All Resolutions")
                        .panelTextStyle(.callout)
                        .foregroundStyle(Palette.labelSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(resolutionCount)")
                        .panelTextStyle(.callout)
                        .foregroundStyle(Palette.labelTertiary)
                    PanelIcon(.chevronRight, size: .trailing)
                        .foregroundStyle(Palette.labelTertiary)
                }
                .lineLimit(1)
                .padding(PanelMetrics.Card.allResolutionsInsets)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("All Resolutions")
        .accessibilityValue("\(resolutionCount)")
        .accessibilityAddTraits(.isButton)
    }
}

extension DisplayCard where Offer == EmptyView {
    /// A card without an offer.
    public init(
        name: String,
        summary: String,
        picture: DisplayPictureModel,
        badge: Badge? = nil,
        sizes: Sizes,
        refreshRates: [PanelChoice],
        resolutionCount: Int,
        openDisplay: @escaping () -> Void,
        showAllResolutions: @escaping () -> Void
    ) {
        self.init(
            name: name, summary: summary, picture: picture, badge: badge, sizes: sizes,
            refreshRates: refreshRates, resolutionCount: resolutionCount,
            openDisplay: openDisplay, showAllResolutions: showAllResolutions
        ) {
            EmptyView()
        }
    }
}
