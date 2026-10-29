import SwiftUI

extension Metrics {
    /// A display's page in the window and its sheets (Figma: Window › Resolution 31:5, Custom
    /// Resolutions 34:332, Picture & Name 34:866, Add Resolution 35:784, Restore Backup 35:1103).
    public enum DisplayPage {
        /// From the content area's edges to the page's: Figma's page frame sits 20 in, and
        /// its content another 28.
        public static let insets = EdgeInsets(top: 40, leading: 48, bottom: 40, trailing: 48)
        /// Between the header, the tabs and each section.
        public static let sectionSpacing: CGFloat = 18
        /// Between the buttons of a row, such as Restore Backup…, Remove Override… and Show in Finder.
        public static let buttonSpacing: CGFloat = 8
        /// The name field of Picture & Name.
        public static let nameFieldWidth: CGFloat = 240

        /// The Preview of Picture & Name: the display being edited is drawn larger.
        public enum Preview {
            public static let emphasizedPicture = CGSize(width: 120, height: 90)
            public static let picture = CGSize(width: 88, height: 66)
            public static let spacing: CGFloat = 36
            public static let nameSpacing: CGFloat = 6
        }

        /// The sheets of the Custom Resolutions tab.
        public enum Sheet {
            public static let addWidth: CGFloat = 460
            public static let restoreWidth: CGFloat = 600
            public static let insets = EdgeInsets(top: 20, leading: 22, bottom: 18, trailing: 22)
            public static let spacing: CGFloat = 16
            /// Between a label and its field, and between the size fields.
            public static let fieldSpacing: CGFloat = 10
            public static let sizeFieldWidth: CGFloat = 86
            /// The backups table, inset 6 all round, its rows 2 apart.
            public static let tableInsets = EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
            public static let tableSpacing: CGFloat = 2
        }

        /// The size preview of the Add Resolution sheet.
        public enum ResolutionPreview {
            public static let padding: CGFloat = 12
            public static let spacing: CGFloat = 14
            public static let thumbnailSize = CGSize(width: 96, height: 61)
            public static let textSpacing: CGFloat = 3
        }

        /// The small warning of the Add Resolution sheet.
        public enum CompactWarning {
            public static let cornerRadius: CGFloat = 10
            public static let horizontalPadding: CGFloat = 10
            public static let verticalPadding: CGFloat = 8
            public static let spacing: CGFloat = 8
            public static let iconSize: CGFloat = 15
        }
    }
}

/// The pictures a display can have, as `PictureChoice`s in rows that wrap (Figma: the Picture
/// section of 34:866), where a picture this Mac has no artwork for is shown dimmed and can't
/// be chosen, and none is selected when the display has a picture chosen elsewhere.
public struct PictureChoicePicker: View {
    /// One picture the picker offers.
    public struct Choice: Identifiable, Hashable, Sendable {
        public var model: DisplayPictureModel
        public var title: String
        public var isEnabled: Bool
        /// Why a picture can't be chosen, shown as its help tag.
        public var help: String?

        public var id: DisplayPictureModel { model }

        public init(_ model: DisplayPictureModel, title: String? = nil, isEnabled: Bool = true, help: String? = nil) {
            self.model = model
            self.title = title ?? model.title
            self.isEnabled = isEnabled
            self.help = help
        }
    }

    public var choices: [Choice]
    public var selection: DisplayPictureModel?
    public var onSelect: (DisplayPictureModel) -> Void

    public init(_ choices: [Choice], selection: DisplayPictureModel?, onSelect: @escaping (DisplayPictureModel) -> Void) {
        self.choices = choices
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        WrappingLayout(spacing: WindowMetrics.Picture.gridSpacing, lineSpacing: WindowMetrics.Picture.gridSpacing) {
            ForEach(choices) { choice in
                let isSelected = choice.model == selection
                Button {
                    onSelect(choice.model)
                } label: {
                    PictureChoice(choice.model, title: choice.title, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .disabled(!choice.isEnabled)
                .opacity(choice.isEnabled ? 1 : WindowMetrics.Sidebar.dimmedOpacity)
                .help(choice.help ?? "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(choice.help ?? "")
            }
        }
    }
}

/// The displays side by side as System Settings › Displays arranges them, the one being
/// edited larger, each named under its picture (Figma: the Preview section of 34:866).
public struct DisplayArrangement: View {
    /// One display in the arrangement.
    public struct Item: Identifiable, Hashable, Sendable {
        public var id: String
        public var picture: DisplayPictureModel
        public var name: String
        public var isEmphasized: Bool

        public init(id: String, picture: DisplayPictureModel, name: String, isEmphasized: Bool) {
            self.id = id
            self.picture = picture
            self.name = name
            self.isEmphasized = isEmphasized
        }
    }

    public var items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: Metrics.DisplayPage.Preview.spacing) {
            ForEach(items) { item in
                let size = item.isEmphasized ? Metrics.DisplayPage.Preview.emphasizedPicture : Metrics.DisplayPage.Preview.picture
                VStack(spacing: Metrics.DisplayPage.Preview.nameSpacing) {
                    DisplayPicture(item.picture)
                        .frame(width: size.width, height: size.height)
                        .accessibilityHidden(true)
                    Text(item.name)
                        .textStyle(item.isEmphasized ? .calloutEmphasized : .callout)
                        .foregroundStyle(item.isEmphasized ? Palette.labelPrimary : Palette.labelSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.name), \(item.picture.title)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// What a size would look like before it is added: its desktop picture, "Looks like 3008 ×
/// 1692" and lines comparing it with now (Figma: the Preview of the Add Resolution sheet,
/// 35:784).
public struct ResolutionPreviewCard: View {
    public var stop: Int
    public var tone: SpaceThumbnail.Tone
    public var title: String
    public var lines: [String]

    public init(stop: Int, tone: SpaceThumbnail.Tone, title: String, lines: [String]) {
        self.stop = stop
        self.tone = tone
        self.title = title
        self.lines = lines
    }

    public var body: some View {
        HStack(spacing: Metrics.DisplayPage.ResolutionPreview.spacing) {
            SpaceThumbnail(stop: stop, tone: tone, isSelected: false)
                .frame(
                    width: Metrics.DisplayPage.ResolutionPreview.thumbnailSize.width,
                    height: Metrics.DisplayPage.ResolutionPreview.thumbnailSize.height
                )
            VStack(alignment: .leading, spacing: Metrics.DisplayPage.ResolutionPreview.textSpacing) {
                Text(title)
                    .textStyle(.bodyEmphasized)
                    .foregroundStyle(Palette.labelPrimary)
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .textStyle(.subheadline)
                        .foregroundStyle(Palette.labelSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Metrics.DisplayPage.ResolutionPreview.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpokenText.sizes(([title] + lines).joined(separator: " ")))
    }
}

/// A one-line warning inside a sheet: an orange triangle and a footnote on the warning tint
/// (Figma: the Warning of the Add Resolution sheet, 35:784).
public struct CompactWarning: View {
    public var text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Metrics.DisplayPage.CompactWarning.spacing) {
            SymbolIcon(.exclamationmarkTriangleFill, size: Metrics.DisplayPage.CompactWarning.iconSize)
                .foregroundStyle(Palette.orange)
                .accessibilityLabel(Text("Warning"))
            Text(text)
                .textStyle(.footnote)
                .foregroundStyle(Palette.labelPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(SpokenText.sizes(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Metrics.DisplayPage.CompactWarning.horizontalPadding)
        .padding(.vertical, Metrics.DisplayPage.CompactWarning.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.DisplayPage.CompactWarning.cornerRadius, style: .continuous)
                .fill(Palette.surfaceWarningTint)
        )
        .accessibilityElement(children: .combine)
    }
}
