import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

extension AppGallery {
    /// Scenes owned by the Custom Resolutions editor owner: its sheets, drawn on their own.
    /// Remove Override… asks with the system's alert (Figma 35:1414), which macOS draws.
    static var customResolutionScenes: [GalleryScene] {
        [
            GalleryScene(
                id: "custom-resolutions.add-sheet", title: "Add Resolution sheet", figmaNode: "35:784",
                size: CGSize(width: Metrics.DisplayPage.Sheet.addWidth, height: 480)
            ) {
                let fixture = DisplayGalleryFixture()
                AddResolutionSheet(
                    model: fixture.editors.editor(for: OverrideKey(display: DisplayGalleryFixture.dell)),
                    display: DisplayGalleryFixture.dell, width: 3008, height: 1692
                )
            },
            GalleryScene(
                id: "custom-resolutions.add-sheet.one-x", title: "Add Resolution sheet, 1×", figmaNode: "35:784",
                size: CGSize(width: Metrics.DisplayPage.Sheet.addWidth, height: 360)
            ) {
                let fixture = DisplayGalleryFixture()
                AddResolutionSheet(
                    model: fixture.editors.editor(for: DisplayGalleryFixture.lg.key), display: nil, width: 2560, height: 1440
                )
            },
            GalleryScene(
                id: "custom-resolutions.restore-sheet", title: "Restore Backup sheet", figmaNode: "35:1103",
                size: CGSize(width: Metrics.DisplayPage.Sheet.restoreWidth, height: 330)
            ) {
                let fixture = DisplayGalleryFixture()
                RestoreBackupSheet(model: fixture.editors.editor(for: OverrideKey(display: DisplayGalleryFixture.dell))) { _ in }
            },
        ]
    }
}
