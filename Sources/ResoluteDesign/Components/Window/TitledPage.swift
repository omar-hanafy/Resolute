import SwiftUI

/// A window page that isn't a display's, as Figma lays out History (37:1957) and Presets
/// (37:2289): the page's title and description, then its content, each 18 points apart, in
/// a scroll view. The page draws its own margins (Figma's Page frame sits 20 points inside
/// the content area and pads its content by 28 at the sides), so the window hosts it edge
/// to edge under the toolbar.
public struct TitledPage<Content: View>: View {
    public var title: String
    public var description: String?
    private let content: Content

    public init(_ title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.TitledPage.spacing) {
                PageHeader(title, description: description)
                content
            }
            .padding(Metrics.TitledPage.insets)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension Metrics {
    /// A titled window page and what Presets and History put on one.
    public enum TitledPage {
        /// Between the header, each block of content and the footnote.
        public static let spacing: CGFloat = WindowMetrics.PageHeader.spacing
        /// The content area's 20-point margin and the Page frame's own padding: 20 above,
        /// 28 at the sides, 40 below.
        public static let insets = EdgeInsets(top: 40, leading: 48, bottom: 60, trailing: 48)
        /// Between two preset cards.
        public static let cardSpacing: CGFloat = WindowMetrics.Preset.listSpacing
        /// Between the push buttons under a list: New Preset from Current Setup and Import….
        public static let actionSpacing: CGFloat = 8
        /// Between an empty state's title and its text.
        public static let emptyTextSpacing: CGFloat = 4
    }
}
