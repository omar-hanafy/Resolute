import SwiftUI

/// One picture in the display-picture picker of Picture & Name: the display's picture and
/// its name in a 118 × 110 tile, which turns accent when chosen (Figma: Components ›
/// Picture Choice, Default and Selected).
public struct PictureChoice: View {
    public var model: DisplayPictureModel
    /// "Studio Display", or "Display (default)" for the picture macOS would choose.
    public var title: String
    public var isSelected: Bool

    public init(_ model: DisplayPictureModel, title: String? = nil, isSelected: Bool = false) {
        self.model = model
        self.title = title ?? model.title
        self.isSelected = isSelected
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: WindowMetrics.Picture.cornerRadius, style: .continuous)
        VStack(spacing: WindowMetrics.Picture.spacing) {
            DisplayPicture(model)
                .frame(width: WindowMetrics.Picture.pictureSize.width, height: WindowMetrics.Picture.pictureSize.height)
                .accessibilityHidden(true)
            Text(title)
                .textStyle(isSelected ? .calloutEmphasized : .callout)
                .foregroundStyle(Palette.labelPrimary)
                .lineLimit(1)
        }
        // Figma lays the selected outline out inside the tile, which moves its picture and
        // name down by the outline's width.
        .padding(.top, WindowMetrics.Picture.topPadding + (isSelected ? WindowMetrics.Picture.selectionWidth : 0))
        .frame(
            width: WindowMetrics.Picture.choiceSize.width,
            height: WindowMetrics.Picture.choiceSize.height,
            alignment: .top
        )
        .background(isSelected ? Palette.surfaceAccentTint : Palette.fillSecondary, in: shape)
        .overlay {
            if isSelected {
                shape.strokeBorder(Palette.accent, lineWidth: WindowMetrics.Picture.selectionWidth)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The pictures a display can have, as `PictureChoice`s in rows that wrap, 12 points apart
/// (Figma: the Picture section of Picture & Name, 34:866). Clicking one chooses it.
public struct PictureChoiceGrid: View {
    /// One picture the grid offers.
    public struct Choice: Identifiable, Hashable, Sendable {
        public var model: DisplayPictureModel
        public var title: String

        public var id: DisplayPictureModel { model }

        /// A picture under its own name, or another such as "Display (default)".
        public init(_ model: DisplayPictureModel, title: String? = nil) {
            self.model = model
            self.title = title ?? model.title
        }
    }

    public var choices: [Choice]
    @Binding public var selection: DisplayPictureModel

    public init(_ choices: [Choice], selection: Binding<DisplayPictureModel>) {
        self.choices = choices
        _selection = selection
    }

    public var body: some View {
        WrappingLayout(spacing: WindowMetrics.Picture.gridSpacing, lineSpacing: WindowMetrics.Picture.gridSpacing) {
            ForEach(choices) { choice in
                Button {
                    selection = choice.model
                } label: {
                    PictureChoice(choice.model, title: choice.title, isSelected: choice.model == selection)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice.model == selection ? .isSelected : [])
            }
        }
    }
}

/// Lays views out left to right at their own sizes, starting a new line when the next one
/// doesn't fit, like a Figma auto-layout frame that wraps.
struct WrappingLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let width = proposal.width ?? .infinity
        let frames = Self.frames(for: sizes, width: width, spacing: spacing, lineSpacing: lineSpacing)
        let used = frames.reduce(CGRect.null) { $0.union($1) }
        guard !used.isNull else { return .zero }
        // Like Figma's frame, it fills the width it is given and is as tall as its lines.
        return CGSize(width: width.isFinite ? width : used.maxX, height: used.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let frames = Self.frames(for: sizes, width: bounds.width, spacing: spacing, lineSpacing: lineSpacing)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Where views of `sizes` go in a line `width` wide: each line as full as it can be, and
    /// a view wider than the line on a line of its own. Lines are as tall as their tallest
    /// view, with the views at the top.
    static func frames(for sizes: [CGSize], width: CGFloat, spacing: CGFloat, lineSpacing: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}
