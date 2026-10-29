import SwiftUI

/// The top of a display's All Resolutions: Back, the display's picture and its name
/// (Figma 22:373).
public struct AllResolutionsHeader: View {
    public var name: String
    public var picture: DisplayPictureModel
    public var back: () -> Void

    public init(name: String, picture: DisplayPictureModel, back: @escaping () -> Void) {
        self.name = name
        self.picture = picture
        self.back = back
    }

    public var body: some View {
        HStack(spacing: Metrics.Spacing.medium) {
            PanelCircleButton(symbol: .chevronLeft, iconSize: .button, label: "Back", action: back)
            DisplayPicture(picture)
                .frame(width: PanelMetrics.headerPictureSize.width, height: PanelMetrics.headerPictureSize.height)
                .accessibilityHidden(true)
            Text(name)
                .panelTextStyle(.headline)
                .foregroundStyle(Palette.labelPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, Metrics.Spacing.xxSmall)
    }
}

/// The card that lists a display's modes in All Resolutions (Figma: Modes, 22:384): the
/// HiDPI | Low Resolution (1×) tabs, then its rows, two points apart.
///
/// Put the listed `ModeRow`s in it, then a `PanelSeparator`, the Show Hidden Modes row
/// with its `PanelFootnote` and the hidden modes, and the Refresh Rate `PanelPopUpRow`.
public struct ModeList<Content: View>: View {
    /// The tabs above the rows; none for a display with one kind of mode.
    public var tabs: [PanelChoice]
    private let content: Content

    public init(tabs: [PanelChoice], @ViewBuilder content: () -> Content) {
        self.tabs = tabs
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PanelMetrics.ModeList.spacing) {
            if !tabs.isEmpty {
                PanelSegments(tabs)
                // Figma leaves 8 points between the tabs and the first row.
                Spacer()
                    .frame(height: PanelMetrics.ModeList.gapBelowTabs)
            }
            content
        }
        .padding(PanelMetrics.ModeList.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Metrics.DisplayCard.cornerRadius, style: .continuous)
                .fill(Palette.surfaceCard)
        )
        .accessibilityElement(children: .contain)
    }
}

/// One mode in All Resolutions (Figma: Mode Row, 17:100): an outline in the mode's aspect
/// ratio, its size and an optional tag ("Default", "Hidden · 21:9").
///
/// The selected mode, the one in use, is filled with the accent color and checked. A hidden
/// mode (one macOS doesn't list) has a dashed orange outline and offers "Try…": choosing it
/// tries the mode before keeping it.
public struct ModeRow: View {
    public var size: String
    public var tag: String?
    /// Width over height; nil draws Figma's outline.
    public var aspectRatio: CGFloat?
    public var isSelected: Bool
    public var isHidden: Bool
    public var action: () -> Void

    @State private var isHovering = false

    public init(
        _ size: String,
        tag: String? = nil,
        aspectRatio: CGFloat? = nil,
        isSelected: Bool = false,
        isHidden: Bool = false,
        action: @escaping () -> Void
    ) {
        self.size = size
        self.tag = tag
        self.aspectRatio = aspectRatio
        self.isSelected = isSelected
        self.isHidden = isHidden
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: PanelMetrics.ModeRow.spacing) {
                outline
                Text(size)
                    .panelTextStyle(.body)
                    .foregroundStyle(isSelected ? PanelPalette.onAccent : Palette.labelPrimary)
                if let tag {
                    Text(tag)
                        .panelTextStyle(.footnote)
                        .foregroundStyle(tagColor)
                }
                Spacer(minLength: 0)
                if isSelected {
                    PanelIcon(.checkmark, size: .small)
                        .foregroundStyle(PanelPalette.onAccent)
                } else if isHidden {
                    Text("Try…")
                        .panelTextStyle(.calloutEmphasized)
                        .foregroundStyle(Palette.accent)
                }
            }
            .lineLimit(1)
            .padding(PanelMetrics.rowInsets)
            .frame(height: Metrics.PanelRow.height)
            .background(
                RoundedRectangle(cornerRadius: PanelMetrics.ModeRow.cornerRadius, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The row as VoiceOver reads it: "2560 by 1080, Hidden, 21:9, Try…".
    var accessibilityLabel: String {
        var parts = [PanelSpeech.text(size)]
        if let tag { parts.append(PanelSpeech.text(tag)) }
        if isHidden, !isSelected { parts.append("Try…") }
        return parts.joined(separator: ", ")
    }

    private var tagColor: Color {
        if isSelected { return PanelPalette.onAccent }
        return isHidden ? Palette.warningText : Palette.labelSecondary
    }

    private var background: Color {
        if isSelected { return Palette.accent }
        return isHovering ? Palette.surfaceRowHover : Color.clear
    }

    private var outline: some View {
        let size = Self.outlineSize(aspectRatio: aspectRatio)
        let shape = RoundedRectangle(cornerRadius: PanelMetrics.ModeRow.outlineCornerRadius, style: .continuous)
        let color = isSelected ? PanelPalette.onAccent : isHidden ? Palette.orange : Palette.labelTertiary
        return ZStack {
            if isHidden {
                shape.strokeBorder(color, style: StrokeStyle(lineWidth: PanelMetrics.ModeRow.outlineLineWidth, dash: PanelMetrics.ModeRow.outlineDash))
            } else {
                shape.strokeBorder(color, lineWidth: PanelMetrics.ModeRow.outlineLineWidth)
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(width: PanelMetrics.ModeRow.outlineFrame.width, height: PanelMetrics.ModeRow.outlineFrame.height)
        .accessibilityHidden(true)
    }

    /// The outline's size for a mode `aspectRatio` wide per point of height, as large as
    /// fits Figma's 18 × 11 outline: wider modes are flatter, taller ones narrower.
    static func outlineSize(aspectRatio: CGFloat?) -> CGSize {
        let box = PanelMetrics.ModeRow.outlineBox
        guard let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 else { return box }
        if aspectRatio >= box.width / box.height {
            return CGSize(width: box.width, height: box.width / aspectRatio)
        }
        return CGSize(width: box.height * aspectRatio, height: box.height)
    }
}
