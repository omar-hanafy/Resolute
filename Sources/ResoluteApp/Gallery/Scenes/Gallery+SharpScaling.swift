import Foundation
import ResoluteDesign
import ResoluteKit
import SwiftUI

extension AppGallery {
    /// Scenes owned by the Sharp Scaling owner: the ASUS PA278QV in each state, from override
    /// files staged in a folder of the scene's own (Figma: Sharp Scaling, page 60:543).
    static var sharpScalingScenes: [GalleryScene] {
        [
            GalleryScene(
                id: "sharp-scaling.panel.offer", title: "Panel, standard display with the Sharp Scaling offer",
                figmaNode: "60:547", backdrop: .wallpaper, padding: 40
            ) {
                PanelRoot(model: SharpScalingGallery.model(.off))
                    .frame(width: Metrics.Panel.width)
            },
            GalleryScene(
                id: "sharp-scaling.panel.after", title: "Panel, Sharp Scaling on, with its switch",
                figmaNode: "60:873", backdrop: .wallpaper, padding: 40
            ) {
                SharpScalingGallery.panelAfter(SharpScalingGallery.model(.switched))
            },
            GalleryScene(id: "sharp-scaling.page.off", title: "Resolution page, Sharp Scaling off", figmaNode: "62:1020", padding: 28) {
                SharpScalingGallery.page(SharpScalingGallery.model(.off))
            },
            GalleryScene(id: "sharp-scaling.page.saved", title: "Resolution page, saved and waiting for a reconnect", figmaNode: "67:1585", padding: 28) {
                SharpScalingGallery.page(SharpScalingGallery.model(.waiting))
            },
            GalleryScene(id: "sharp-scaling.page.ready", title: "Resolution page, Sharp Scaling ready", figmaNode: "67:2175", padding: 28) {
                SharpScalingGallery.page(SharpScalingGallery.model(.switched))
            },
            GalleryScene(id: "sharp-scaling.page.partial", title: "Resolution page, macOS skipped a size", figmaNode: "68:2089", padding: 28) {
                SharpScalingGallery.page(SharpScalingGallery.model(.partial))
            },
            GalleryScene(id: "sharp-scaling.setup-sheet", title: "Set Up Sharp Scaling sheet", figmaNode: "66:1271") {
                SharpScalingGallery.sheet(SharpScalingGallery.model(.off))
            },
            GalleryScene(
                id: "sharp-scaling.setup-sheet.limited", title: "Set Up Sharp Scaling sheet, a size this Mac can't draw",
                figmaNode: "66:1271"
            ) {
                SharpScalingGallery.sheet(SharpScalingGallery.model(.off), limit: DrawingLimit(width: 4800))
            },
        ]
    }
}

/// The Sharp Scaling scenes' app: the built-in display and the ASUS PA278QV, whose override
/// file is staged in a folder of the scene's own. Nothing is written outside it.
@MainActor
enum SharpScalingGallery {
    enum Situation {
        /// No override: the offer and the page before setup.
        case off
        /// The five sizes saved at 9:42, before the reconnect.
        case waiting
        /// Saved with "Switch to the sharp 2560 × 1440", then reconnected: every size is
        /// offered, and Resolute has switched.
        case switched
        /// Reconnected, and macOS skipped 2560 × 1440.
        case partial
    }

    static let native = SharpSize(width: 2560, height: 1440)
    static let designSizes = [(1600, 900), (1920, 1080), (2048, 1152), (2304, 1296), (2560, 1440)]
        .map { SharpSize(width: $0.0, height: $0.1) }
    /// The design's drawing limit, an M2 Pro's.
    static let limit = DrawingLimit(width: 6144)

    static func model(_ situation: Situation) -> AppModel {
        let asus = SampleDisplays.asusPA278QV.display
        let service = FakeDisplayService(displays: [SampleDisplays.builtInRetina.display, asus])
        var environment = AppEnvironment.gallery(service: service)
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ResoluteGallery-sharp-scaling-\(UUID().uuidString)", directoryHint: .isDirectory)
        environment.overrides = OverrideStore(locations: .staged(at: root))
        environment.preferences.dismissedSharpScalingOffers = []
        writePresets(to: environment.support, displays: service.displays())
        switch situation {
        case .off:
            break
        case .waiting:
            stageSetup(at: root, switchTo: nil)
        case .switched:
            stageSetup(at: root, switchTo: native)
        case .partial:
            stageSetup(at: root, switchTo: nil)
        }
        let model = AppModel(environment: environment)
        model.sharpScaling.drawingLimit = limit
        // Not this Mac's start: the scene's file is saved after it, so it waits for a reconnect.
        model.sharpScaling.systemStart = nil
        model.sharpScaling.reload()
        switch situation {
        case .off, .waiting:
            break
        case .switched:
            reconnect(model, service: service, as: withSharpModes(asus, sizes: designSizes))
        case .partial:
            reconnect(model, service: service, as: withSharpModes(asus, sizes: Array(designSizes.dropLast())))
        }
        return model
    }

    /// The panel after the switch (60:873), with its activity row for the switch.
    static func panelAfter(_ model: AppModel) -> some View {
        PanelRoot(model: model)
            .frame(width: Metrics.Panel.width)
    }

    /// The Resolution tab's Sharp Scaling parts as the display page lays them out: the banner
    /// above the tabs, then the section, or the row above Refresh Rate once the sizes are in use.
    static func page(_ model: AppModel) -> some View {
        let display = model.displays.first { $0.name == "ASUS PA278QV" } ?? SampleDisplays.asusPA278QV.display
        return VStack(alignment: .leading, spacing: Metrics.Spacing.xLarge) {
            SharpScalingBanner(model: model, display: display)
            if model.sharpScaling.headerBadge(for: display) != nil {
                Badge(model.sharpScaling.headerBadge(for: display) ?? "", tone: .accent)
            }
            switch model.sharpScaling.placement(for: display) {
            case .section?:
                SharpScalingSection(model: model, display: display)
            case .row?:
                FormGroup {
                    SharpScalingRow(model: model, display: display)
                    FormRow("Refresh Rate", selection: .constant(75), options: [.init(75, "75 Hz"), .init(60, "60 Hz")])
                }
            case nil:
                EmptyView()
            }
        }
        .frame(width: 704)
    }

    static func sheet(_ model: AppModel, limit: DrawingLimit = SharpScalingGallery.limit) -> some View {
        let display = model.displays.first { $0.name == "ASUS PA278QV" } ?? SampleDisplays.asusPA278QV.display
        return SharpScalingSetupSheet(model: model, display: display, plan: SharpScalingPlan(native: native, limit: limit))
    }

    /// Writes the design's five sizes as `asus`'s override, as setup does, saved at 9:42 today.
    private static func stageSetup(at root: URL, switchTo: SharpSize?) {
        let key = OverrideKey(display: SampleDisplays.asusPA278QV.display)
        var calendar = Calendar.current
        calendar.timeZone = .current
        let saved = calendar.date(bySettingHour: 9, minute: 42, second: 0, of: Date()) ?? Date()
        guard let file = try? OverrideStore(locations: .staged(at: root)).editableFile(for: key),
              let setup = try? SharpScalingSetup(file: file, sizes: designSizes, offered: [], switchTo: switchTo, now: saved),
              let data = try? setup.override.propertyListData()
        else { return }
        let url = OverrideLocations.staged(at: root).userFile(for: key)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    /// Unplugs the ASUS and plugs it back in as `display`.
    private static func reconnect(_ model: AppModel, service: FakeDisplayService, as display: Display) {
        service.set([SampleDisplays.builtInRetina.display])
        model.displaysDidChange()
        service.set([SampleDisplays.builtInRetina.display, display])
        model.displaysDidChange()
    }

    /// `display` once macOS has read the override: the sharp modes for `sizes` at 75, 60 and
    /// 50 Hz, as it lists them.
    static func withSharpModes(_ display: Display, sizes: [SharpSize]) -> Display {
        var display = display
        var next = (display.modes.map(\.modeID).max() ?? 0) + 1
        for size in sizes {
            for rate in [75.0, 60, 50] {
                display.modes.append(DisplayMode(
                    modeID: next, privateIndex: next - 1, width: size.width, height: size.height,
                    pixelWidth: size.drawnWidth, pixelHeight: size.drawnHeight, refreshRate: rate,
                    bitsPerSample: 8, ioFlags: DisplayMode.Flag.valid | DisplayMode.Flag.safe
                ))
                next += 1
            }
        }
        return display
    }

    /// `displays` with the built-in one at the HiDPI size `width` points wide.
    private static func builtIn(_ displays: [Display], atWidth width: Int) -> [Display] {
        displays.map { display in
            guard display.isBuiltin, let mode = display.modes.first(where: { $0.width == width && $0.isHiDPI }) else { return display }
            var switched = display
            switched.currentModeID = mode.modeID
            return switched
        }
    }

    /// The design's three presets, Coding in use, so the panel looks as it does in Figma.
    private static func writePresets(to support: SupportLocations, displays: [Display]) {
        _ = try? PresetStore(locations: support).update { library in
            _ = try library.save(PresetCapture(displays: displays), named: "Coding", replacing: true)
            _ = try library.save(PresetCapture(displays: builtIn(displays, atWidth: 1496)), named: "Presenting", replacing: true)
            _ = try library.save(PresetCapture(displays: builtIn(displays, atWidth: 1312)), named: "Gaming", replacing: true)
        }
    }
}
