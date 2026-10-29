import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

extension AppGallery {
    /// Scenes owned by the window shell, sidebar and routing owner.
    static var windowScenes: [GalleryScene] {
        [
            // Light is Figma 38:3760, the same page.
            GalleryScene(id: "window.resolution.builtin", figmaNode: "31:5") {
                let fixture = DisplayGalleryFixture()
                return fixture.window(on: .display(.id(SampleDisplays.builtInRetina.display.id)))
            },
            GalleryScene(id: "window.sidebar.presets", figmaNode: "37:2289") {
                DisplayGalleryFixture().window(on: .presets)
            },
        ]
    }
}

/// The window as the design draws it, on fakes: the built-in display and the DELL U2723QE
/// connected (or others), the DELL's override installed with two entries and four backups,
/// the LG UltraFine 5K away with its override, three presets, and a History entry from the
/// LG's last visit. Overrides are written by a runner that refuses every script, so nothing
/// can reach /Library.
@MainActor
struct DisplayGalleryFixture {
    let model: AppModel
    let editors: DisplayEditors
    let locations: OverrideLocations

    static let dell = SampleDisplays.dellU2723QE.display
    static let builtIn = SampleDisplays.builtInRetina.display
    static let asus = SampleDisplays.asusPA278QV.display
    static let lg = SampleDisplays.lgUltraFine5K

    /// The DELL's installed entries, as Figma 34:332 lists them before the edit.
    static let dellEntries: [ScaleResolution] = [
        .standard(width: 5120, height: 2160),
        .hiDPI(width: 2560, height: 1080, flags: .standard),
    ]

    init(displays: [Display] = [Self.builtIn, Self.dell], installsDellOverride: Bool = true) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "ResoluteGallery-window-\(UUID().uuidString)", directoryHint: .isDirectory
        )
        locations = .staged(at: root.appending(path: "Overrides", directoryHint: .isDirectory))
        let support = SupportLocations(root: root.appending(path: "Support", directoryHint: .isDirectory))
        if installsDellOverride {
            Self.install(DisplayOverride(key: OverrideKey(display: Self.dell), resolutions: Self.dellEntries), in: locations)
            Self.stageBackups(of: Self.dell, in: locations)
        }
        Self.install(Self.lg.override, in: locations)
        Self.recordVisit(of: Self.lg, in: support)

        let environment = AppEnvironment(
            service: FakeDisplayService(displays: displays),
            preferences: Preferences(defaults: UserDefaults(suiteName: "com.omarhanafy.Resolute.gallery") ?? .standard),
            loginItem: FixedLoginItem(state: .disabled),
            overrides: OverrideStore(locations: locations),
            support: support,
            notificationCenter: NotificationCenter(),
            askToKeep: { _ in false },
            showTrialOutcome: { _, _ in },
            showError: { _, _ in },
            launchKind: .deliberate,
            displayDetails: { display in
                SampleDisplays.all.first { $0.display.id == display.id }?.details ?? DisplayDetails()
            }
        )
        model = AppModel(environment: environment)
        for name in ["Desk", "Presenting", "Reading"] {
            _ = try? model.saveCurrentSetupAsPreset(named: name)
        }
        editors = DisplayEditors(
            model: model,
            store: OverrideStore(locations: locations),
            installer: OverrideInstaller(locations: locations, runner: RefusingRunner())
        )
    }

    /// The window on `route`, at the design's size, without saving its frame.
    func window(on route: AppRoute) -> NSWindow {
        let navigation = WindowNavigation(route: route)
        let controller = MainWindowController(
            model: model,
            navigation: navigation,
            activation: ActivationPolicyController(apply: { _ in }),
            frameAutosaveName: nil,
            content: WindowRoot(model: model, navigation: navigation, editors: editors)
        )
        return controller.window ?? NSWindow()
    }

    /// The DELL's editor with Figma's unsaved edit: 3008 × 1692 HiDPI added (with its 1×
    /// entry), and 2560 × 1080 selected.
    func editDell() -> CustomResolutionsModel {
        let editor = editors.editor(for: OverrideKey(display: Self.dell))
        _ = editor.add(.hiDPI(width: 3008, height: 1692, flags: .standard))
        editor.selectedEntries = [.hiDPI(width: 2560, height: 1080, flags: .standard)]
        return editor
    }

    private static func install(_ override: DisplayOverride, in locations: OverrideLocations) {
        let url = locations.userFile(for: override.key)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? override.propertyListData().write(to: url)
    }

    /// Four backups, as Figma 35:1103 lists them: today, yesterday and two older ones.
    private static func stageBackups(of display: Display, in locations: OverrideLocations) {
        let key = OverrideKey(display: display)
        let folder = locations.backupFolder(for: key)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let hour: TimeInterval = 3600
        let backups: [(age: TimeInterval, resolutions: [ScaleResolution])] = [
            (2 * hour, dellEntries + [.standard(width: 3200, height: 1800), .hiDPI(width: 1600, height: 900, flags: .standard)]),
            (17 * hour, dellEntries),
            (8 * 24 * hour, dellEntries + [.standard(width: 3200, height: 1800)]),
            (17 * 24 * hour, dellEntries),
        ]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        for backup in backups {
            let date = Date().addingTimeInterval(-backup.age)
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let stamp = String(
                format: "%04d%02d%02d-%02d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
            )
            let data = try? DisplayOverride(key: key, resolutions: backup.resolutions).propertyListData()
            try? data?.write(to: folder.appending(path: "\(key.productFileName)-\(stamp).plist"))
        }
    }

    /// A switch on the LG two days ago, at its native size, so its page says when it was last
    /// connected and its panel's pixels.
    private static func recordVisit(of display: SampleDisplays.NotConnected, in support: SupportLocations) {
        let mode = HistoryEntry.ModeRecord(
            modeID: 1, width: 2560, height: 1440, pixelWidth: display.nativeSize.width, pixelHeight: display.nativeSize.height,
            refreshRate: 60, ioFlags: DisplayMode.Flag.native
        )
        let entry = HistoryEntry(
            date: Date().addingTimeInterval(-2 * 24 * 3600),
            source: .panel,
            change: .mode(HistoryEntry.ModeChange(
                display: HistoryEntry.DisplayRecord(id: 9, name: display.name, vendorID: display.key.vendorID, productID: display.key.productID),
                from: nil,
                to: mode
            )),
            outcome: .applied
        )
        try? HistoryStore(locations: support).append(entry)
    }
}
