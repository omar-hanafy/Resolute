import SwiftUI

extension DesignCatalog {
    /// Scenes owned by the pictures owner (display pictures, space thumbnails, app icon).
    /// Each lays its pictures out like the Figma frame it names, so the two compare directly.
    @MainActor static var pictures: [CatalogScene] {
        [
            CatalogScene(id: "ds.pictures.display-pictures", title: "Display pictures", figmaNode: "9:56", padding: 24) {
                DisplayPictureRow(size: CGSize(width: 160, height: 120), spacing: 24)
            },
            CatalogScene(
                id: "ds.pictures.display-pictures.panel",
                title: "Display pictures at the panel's size",
                figmaNode: "18:27",
                padding: 12
            ) {
                DisplayPictureRow(size: CGSize(width: 48, height: 36), spacing: 12)
            },
            CatalogScene(id: "ds.pictures.space-thumbnails", title: "Space thumbnails", figmaNode: "9:297", padding: 24) {
                SpaceThumbnailGrid(size: CGSize(width: 100, height: 64), columnSpacing: 24, rowSpacing: 24)
            },
            CatalogScene(
                id: "ds.pictures.space-thumbnails.panel",
                title: "Space thumbnails at the panel's size",
                figmaNode: "20:156",
                padding: 12
            ) {
                SpaceThumbnailGrid(size: CGSize(width: 54, height: 35), columnSpacing: 6, rowSpacing: 12)
            },
            CatalogScene(
                id: "ds.pictures.space-thumbnails.space-option",
                title: "Space thumbnails in Space Option",
                figmaNode: "18:176",
                padding: 24
            ) {
                // Space Option's thumbnail: stop 4, Default and Selected, 116 × 74.
                HStack(spacing: 24) {
                    SpaceThumbnail(stop: 4, tone: .violet, isSelected: false).frame(width: 116, height: 74)
                    SpaceThumbnail(stop: 4, tone: .violet, isSelected: true).frame(width: 116, height: 74)
                }
            },
            CatalogScene(
                id: "ds.pictures.space-thumbnails.sheet",
                title: "Space thumbnails in the Sharp Scaling sheet",
                figmaNode: "66:1536",
                padding: 8
            ) {
                // The sheet's preview: an external display's five sizes, 98 × 62, the last one current.
                HStack(spacing: 16.5) {
                    ForEach(SpaceThumbnail.stops, id: \.self) { stop in
                        SpaceThumbnail(stop: stop, tone: .teal, isSelected: stop == SpaceThumbnail.stops.upperBound)
                            .frame(width: 98, height: 62)
                    }
                }
            },
            CatalogScene(id: "ds.pictures.app-icon", title: "App icon", figmaNode: "26:475", padding: 24) {
                HStack(spacing: 24) {
                    ForEach(AppIconView.Appearance.allCases, id: \.self) { appearance in
                        AppIconView(appearance).frame(width: 128, height: 128)
                    }
                }
            },
            CatalogScene(id: "ds.pictures.app-icon.sizes", title: "App icon sizes", figmaNode: "46:52", padding: 24) {
                AppIconSizes()
            },
        ]
    }
}

/// Every display picture, left to right in Figma's order.
private struct DisplayPictureRow: View {
    var size: CGSize
    var spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(DisplayPictureModel.allCases, id: \.self) { model in
                DisplayPicture(model).frame(width: size.width, height: size.height)
            }
        }
    }
}

/// Every space thumbnail state: stops 1 to 5 across; Violet, Violet selected, Teal and Teal
/// selected down, as in Figma's component set.
private struct SpaceThumbnailGrid: View {
    var size: CGSize
    var columnSpacing: CGFloat
    var rowSpacing: CGFloat

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(SpaceThumbnail.Tone.allCases, id: \.self) { tone in
                ForEach([false, true], id: \.self) { isSelected in
                    HStack(spacing: columnSpacing) {
                        ForEach(SpaceThumbnail.stops, id: \.self) { stop in
                            SpaceThumbnail(stop: stop, tone: tone, isSelected: isSelected)
                                .frame(width: size.width, height: size.height)
                        }
                    }
                }
            }
        }
    }
}

/// The icon at the sizes macOS shows it, in the color scheme's appearance, as on Figma's
/// App Icon page.
private struct AppIconSizes: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 28) {
            ForEach([16, 32, 64, 128], id: \.self) { (points: Int) in
                VStack(spacing: 8) {
                    AppIconView().frame(width: CGFloat(points), height: CGFloat(points))
                    Text("\(points) px").textStyle(.subheadline).foregroundStyle(Palette.labelSecondary)
                }
            }
        }
    }
}
