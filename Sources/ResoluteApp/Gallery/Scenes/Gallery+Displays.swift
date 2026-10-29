import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

extension AppGallery {
    /// Scenes owned by the display page owner.
    static var displayScenes: [GalleryScene] {
        [
            GalleryScene(id: "displays.resolution.dell", figmaNode: "31:5") {
                DisplayGalleryFixture().window(on: .display(.id(DisplayGalleryFixture.dell.id)))
            },
            GalleryScene(id: "displays.resolution.standard", figmaNode: "62:1020") {
                let fixture = DisplayGalleryFixture(displays: [DisplayGalleryFixture.builtIn, DisplayGalleryFixture.asus])
                return fixture.window(on: .display(.id(DisplayGalleryFixture.asus.id)))
            },
            GalleryScene(id: "displays.custom-resolutions.unsaved", figmaNode: "34:332") {
                let fixture = DisplayGalleryFixture()
                _ = fixture.editDell()
                return fixture.window(on: .display(.id(DisplayGalleryFixture.dell.id), tab: .customResolutions))
            },
            GalleryScene(id: "displays.custom-resolutions.saved", figmaNode: "34:332") {
                DisplayGalleryFixture().window(on: .display(.id(DisplayGalleryFixture.dell.id), tab: .customResolutions))
            },
            GalleryScene(id: "displays.picture-and-name.unsaved", figmaNode: "34:866") {
                let fixture = DisplayGalleryFixture()
                fixture.editors.editor(for: OverrideKey(display: DisplayGalleryFixture.dell)).choosePicture(DisplaySkin.studioDisplay.rawValue)
                return fixture.window(on: .display(.id(DisplayGalleryFixture.dell.id), tab: .pictureAndName))
            },
            GalleryScene(id: "displays.not-connected", figmaNode: "37:1480") {
                DisplayGalleryFixture().window(on: .display(.overrideKey(DisplayGalleryFixture.lg.key), tab: .customResolutions))
            },
            GalleryScene(id: "displays.not-connected.picture-and-name", figmaNode: "37:1480") {
                DisplayGalleryFixture().window(on: .display(.overrideKey(DisplayGalleryFixture.lg.key), tab: .pictureAndName))
            },
        ]
    }
}
