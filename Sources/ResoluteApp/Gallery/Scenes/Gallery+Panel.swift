import Foundation
import ResoluteDesign
import ResoluteKit
import SwiftUI

extension AppGallery {
    /// The menu bar panel as the app builds it, from Figma's sample displays, presets and the
    /// change from Terminal its activity row shows (Figma: Menu bar panel, page 8:6).
    static var panelScenes: [GalleryScene] {
        [
            panelScene("panel.two-displays", "Panel, two displays", node: "23:557"),
            panelScene("panel.one-display", "Panel, one display", node: "23:818", displays: [SampleDisplays.builtInRetina]),
            panelScene("panel.all-resolutions", "Panel, All Resolutions", node: "23:1079") { model in
                model.panelAllResolutions = SampleDisplays.dellU2723QE.display.id
            },
            panelScene("panel.all-resolutions.hidden", "Panel, All Resolutions with hidden modes", node: "23:1079") { model in
                model.preferences.showHiddenModes = true
                model.panelAllResolutions = SampleDisplays.dellU2723QE.display.id
            },
            panelScene("panel.mirroring", "Panel, mirroring", node: "24:1435", mirroring: true),
        ]
    }

    private static func panelScene(
        _ id: String, _ title: String, node: String, displays: [SampleDisplays.Sample] = [SampleDisplays.builtInRetina, SampleDisplays.dellU2723QE],
        mirroring: Bool = false, setUp: @escaping @MainActor (AppModel) -> Void = { _ in }
    ) -> GalleryScene {
        GalleryScene(id: id, title: title, figmaNode: node, backdrop: .wallpaper, padding: 40) {
            PanelRoot(model: PanelGallery.model(displays: displays, mirroring: mirroring, setUp: setUp))
                .frame(width: Metrics.Panel.width)
        }
    }
}

/// The panel scenes' app: sample displays, Figma's three presets with Coding in use, and a
/// switch from Terminal two minutes ago.
@MainActor
private enum PanelGallery {
    static func model(displays: [SampleDisplays.Sample], mirroring: Bool, setUp: (AppModel) -> Void) -> AppModel {
        let service = FakeDisplayService(displays: displays.map(\.display))
        if mirroring { try? service.setMirroring(true) }
        let environment = AppEnvironment.gallery(service: service)
        // The gallery's own preferences start as the design's defaults each time.
        environment.preferences.showHiddenModes = false
        writeSamples(to: environment.support, displays: service.displays())
        let model = AppModel(environment: environment)
        setUp(model)
        return model
    }

    static func writeSamples(to support: SupportLocations, displays: [Display]) {
        _ = try? PresetStore(locations: support).update { library in
            _ = try library.save(PresetCapture(displays: displays), named: "Coding", replacing: true)
            _ = try library.save(PresetCapture(displays: switched(displays, toWidth: 1496)), named: "Presenting", replacing: true)
            _ = try library.save(PresetCapture(displays: switched(displays, toWidth: 1312)), named: "Gaming", replacing: true)
        }
        guard !mirroring(displays), let dell = displays.first(where: { !$0.isBuiltin }),
              let now = dell.currentMode, let before = dell.modes.first(where: { $0.width == 1920 && $0.isHiDPI })
        else { return }
        var earlier = dell
        earlier.currentModeID = before.modeID
        try? HistoryStore(locations: support).append(HistoryEntry(
            date: Date().addingTimeInterval(-120), source: .terminal(app: "Terminal"),
            change: .mode(HistoryEntry.ModeChange(display: earlier, to: now)), outcome: .applied
        ))
    }

    /// `displays` with the built-in one at the HiDPI size `width` points wide.
    private static func switched(_ displays: [Display], toWidth width: Int) -> [Display] {
        displays.map { display in
            guard display.isBuiltin, let mode = display.modes.first(where: { $0.width == width && $0.isHiDPI }) else { return display }
            var switched = display
            switched.currentModeID = mode.modeID
            return switched
        }
    }

    private static func mirroring(_ displays: [Display]) -> Bool {
        displays.contains(where: \.isInMirrorSet)
    }
}
