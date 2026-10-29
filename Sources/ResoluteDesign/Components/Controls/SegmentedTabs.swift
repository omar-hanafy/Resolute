import SwiftUI

/// A row of segments with one selected (Figma: Components › Segment): the window's
/// Resolution | Custom Resolutions | Picture & Name tabs, the panel's HiDPI | Low
/// Resolution (1×) tabs and its refresh rates, History's filters, Settings' tabs.
///
/// Name the whole control for VoiceOver with `.accessibilityLabel(_:)` ("Refresh rate");
/// each segment is a button that reads its title and whether it is selected.
///
/// Contract (Wave 0): the type, `Item`, `Size` and `init(_:selection:size:)` stay. The
/// controls owner refines the drawing.
public struct SegmentedTabs<Value: Hashable>: View {
    public struct Item {
        public var value: Value
        public var title: String

        public init(_ value: Value, _ title: String) {
            self.value = value
            self.title = title
        }
    }

    public enum Size: Sendable {
        /// Segments as wide as their titles: the window's tabs, History's filters and
        /// Settings' tabs.
        case regular
        /// Segments that share the control's full width equally: the panel's refresh
        /// rates and its HiDPI | Low Resolution (1×) tabs. They are as tall as regular ones.
        case large
    }

    public var items: [Item]
    @Binding public var selection: Value
    public var size: Size

    public init(_ items: [Item], selection: Binding<Value>, size: Size = .regular) {
        self.items = items
        _selection = selection
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let isSelected = isSelected(item)
                Button {
                    select(item.value)
                } label: {
                    SegmentLabel(title: item.title, isSelected: isSelected, fillsWidth: size == .large)
                }
                .buttonStyle(SegmentButtonStyle())
                .accessibilityLabel(Text(SpokenText.sizes(item.title)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(Metrics.Segment.trackPadding)
        .background(Capsule().fill(Palette.surfaceTrack))
        .accessibilityElement(children: .contain)
    }

    /// Whether `item` is the selected segment.
    func isSelected(_ item: Item) -> Bool {
        item.value == selection
    }

    /// Selects `value`, as clicking its segment does.
    func select(_ value: Value) {
        selection = value
    }
}

/// One segment, selected or not (Figma: Components › Segment, State=Selected and
/// State=Default).
struct SegmentLabel: View {
    var title: String
    var isSelected: Bool
    var fillsWidth: Bool

    var body: some View {
        // The emphasized title sizes every segment, selected or not, so the segments
        // keep their widths when the selection moves. Segments that hug their titles
        // never truncate them.
        Text(title)
            .textStyle(.calloutEmphasized)
            .lineLimit(1)
            .fixedSize(horizontal: !fillsWidth, vertical: false)
            .hidden()
            .overlay {
                Text(title)
                    .textStyle(isSelected ? .calloutEmphasized : .callout)
                    .lineLimit(1)
                    .foregroundStyle(Palette.labelPrimary)
            }
            .padding(.horizontal, Metrics.Segment.horizontalPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: Metrics.Segment.height)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Palette.surfaceSelectedControl)
                        .shadow(color: Palette.shadowSelectedControl, radius: 0.5, x: 0, y: 1)
                }
            }
            .contentShape(Capsule())
    }
}

/// Dims a segment while it is pressed, as native segmented controls do.
private struct SegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
