import AppKit
import ResoluteDesign
import SwiftUI

extension AppGallery {
    /// Scenes owned by the app shell (status item host, panel and window hosts) owner.
    static var shellScenes: [GalleryScene] {
        [
            GalleryScene(
                id: "shell.status-item.states", title: "Status item states", figmaNode: "25:2439",
                size: CGSize(width: 560, height: 260), backdrop: .wallpaper
            ) {
                StatusItemStatesScene()
            },
        ]
    }
}

/// The menu bar icon in each state, as `StatusItemController` draws it, with Figma's
/// captions. The open state's highlight stands in for the one macOS draws.
private struct StatusItemStatesScene: View {
    private let rows: [(state: StatusItemState, caption: String)] = [
        (.normal, "Resting"),
        (.open, "Panel showing"),
        (.trial(secondsLeft: 12), "Hidden mode on trial, 12 s left"),
        (.resolution("1728 × 1117"), "Optional: current resolution"),
        (.waiting, "A revert is waiting for its display"),
    ]

    /// Laid out as Figma's frame is: rows 46 points apart, the first at (24, 22).
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: Metrics.Spacing.xLarge) {
                    StatusItemPreview(state: rows[index].state)
                    Text(rows[index].caption)
                        .textStyle(.bodyMedium)
                        .foregroundStyle(Palette.labelPrimary)
                }
                .frame(height: Metrics.MenuBar.statusItemHeight)
            }
        }
        .padding(.leading, 24)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One state of the icon, as the menu bar draws it.
private struct StatusItemPreview: View {
    let state: StatusItemState

    var body: some View {
        let image = state.image().nsImage()
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .foregroundStyle(Palette.labelPrimary)
            .frame(height: Metrics.MenuBar.statusItemHeight)
            .background {
                if state == .open {
                    Capsule().fill(Palette.surfaceSelectedControl)
                        .overlay(Capsule().strokeBorder(Palette.strokeWindowEdge, lineWidth: 0.5))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.accessibilityLabel)
    }
}
