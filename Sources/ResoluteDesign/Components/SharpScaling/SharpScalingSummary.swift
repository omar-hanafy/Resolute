import SwiftUI

/// Sharp Scaling on a display's page before its sizes are in use: a grouped section with a
/// symbol and a badge, what it does or what was saved, the sizes, and one button with a note
/// beside it (Figma: Sharp Scaling › page off 62:1020, saved 67:1585).
///
/// Before setup the sizes are a preview, drawn faintly; once saved they are the saved sizes.
public struct SharpScalingSummary: View {
    /// The section's button: "Set Up Sharp Scaling…", prominent, or "Undo Setup…".
    public struct Action {
        public var title: String
        public var isProminent: Bool
        public var perform: @MainActor () -> Void

        public init(_ title: String, isProminent: Bool, perform: @escaping @MainActor () -> Void) {
            self.title = title
            self.isProminent = isProminent
            self.perform = perform
        }
    }

    public var symbol: Symbol
    public var symbolColor: Color
    /// "Off", "Waiting for reconnect".
    public var badge: String
    public var message: String
    public var sizes: [StopPicker.Option]
    /// Draws the sizes faintly, as sizes the display doesn't have yet.
    public var isPreview: Bool
    public var action: Action
    /// The note beside the button: "Asks for an administrator password. …"
    public var footnote: String
    /// While a change is being written: the button is off and a spinner shows beside it.
    public var isWorking: Bool

    public init(
        symbol: Symbol,
        symbolColor: Color,
        badge: String,
        message: String,
        sizes: [StopPicker.Option],
        isPreview: Bool,
        action: Action,
        footnote: String,
        isWorking: Bool = false
    ) {
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.badge = badge
        self.message = message
        self.sizes = sizes
        self.isPreview = isPreview
        self.action = action
        self.footnote = footnote
        self.isWorking = isWorking
    }

    public var body: some View {
        GroupedSection(
            "Sharp Scaling",
            symbol: symbol,
            symbolColor: symbolColor,
            insets: WindowMetrics.Space.pickerInsets,
            spacing: WindowMetrics.Section.spacing
        ) {
            Text(message)
                .textStyle(.body)
                .foregroundStyle(Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(SpokenText.sizes(message))
            SpaceOptionRow(sizes, tone: .teal)
                .opacity(isPreview ? SharpScalingMetrics.previewOpacity : 1)
            HStack(spacing: WindowMetrics.Section.spacing) {
                button
                    .disabled(isWorking)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Writing the override file")
                }
                SectionFootnote(footnote)
            }
        } accessory: {
            Badge(badge)
        }
    }

    @ViewBuilder
    private var button: some View {
        if action.isProminent {
            Button(action.title) { action.perform() }
                .buttonStyle(.borderedProminent)
        } else {
            Button(action.title) { action.perform() }
        }
    }
}

/// The geometry of the Sharp Scaling components that the window's metrics don't name, as
/// Figma gives it.
enum SharpScalingMetrics {
    /// The sizes Sharp Scaling would add, before setup (62:1020).
    static let previewOpacity: Double = 0.55

    /// The setup sheet (66:1271).
    enum Sheet {
        static let width: CGFloat = 600
        static let insets = EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22)
        static let spacing: CGFloat = 14
        /// A size in the preview: its picture, then its size and caption.
        static let thumbnailSize = CGSize(width: 98, height: 62)
        static let previewSpacing: CGFloat = 4
        static let previewMinimumGap: CGFloat = 8
        /// The list of sizes: 4 around its rows, each 7 above and below, 10 before and 12
        /// after, its columns 12 apart.
        static let listPadding: CGFloat = 4
        static let rowInsets = EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 12)
        static let rowSpacing: CGFloat = 12
        static let sizeColumnWidth: CGFloat = 160
        static let drawnColumnWidth: CGFloat = 190
        static let checkboxHeight: CGFloat = 20
        /// The note about this Mac's drawing limit.
        static let noteInsets = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        static let noteSpacing: CGFloat = 8
        static let noteCornerRadius: CGFloat = 10
        static let noteIconSize: CGFloat = 15
        static let buttonSpacing: CGFloat = 8
    }
}
