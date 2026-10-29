import SwiftUI

/// The title of a window page that isn't a display's, with an optional description under
/// it: History, Presets, Settings (Figma: the History 37:1957, Presets 37:2289 and Settings
/// 40:149 pages). Figma sets the title in Title 1.
public struct PageHeader: View {
    public var title: String
    public var description: String?

    public init(_ title: String, description: String? = nil) {
        self.title = title
        self.description = description
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: WindowMetrics.PageHeader.spacing) {
            Text(title)
                .textStyle(.title1)
                .foregroundStyle(Palette.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            if let description {
                Text(description)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
