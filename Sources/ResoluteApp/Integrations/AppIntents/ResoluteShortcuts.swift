import AppIntents
import ResoluteKit

/// The App Shortcuts Spotlight, Siri and the Shortcuts app offer without setup. Set Resolution
/// and Apply Preset take their value from the phrase, so Spotlight finds “Set 1496 × 967” and
/// “Apply Coding” as you type.
struct ResoluteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ApplyPresetIntent(),
            phrases: [
                "Apply \(\.$preset) with \(.applicationName)",
                "Apply a preset with \(.applicationName)",
            ],
            shortTitle: "Apply Preset",
            systemImageName: "star"
        )
        AppShortcut(
            intent: SetResolutionIntent(),
            phrases: [
                "Set \(\.$resolution) with \(.applicationName)",
                "Set the resolution with \(.applicationName)",
            ],
            shortTitle: "Set Resolution",
            systemImageName: "display"
        )
        AppShortcut(
            intent: SetRefreshRateIntent(),
            phrases: ["Set the refresh rate with \(.applicationName)"],
            shortTitle: "Set Refresh Rate",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        AppShortcut(
            intent: MirrorDisplaysIntent(),
            phrases: ["Mirror displays with \(.applicationName)"],
            shortTitle: "Mirror Displays",
            systemImageName: "rectangle.on.rectangle"
        )
        AppShortcut(
            intent: GetDisplaysIntent(),
            phrases: ["Get displays from \(.applicationName)"],
            shortTitle: "Get Displays",
            systemImageName: "list.bullet"
        )
        AppShortcut(
            intent: OpenResoluteIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Resolute",
            systemImageName: "macwindow"
        )
    }
}

/// Tells App Shortcuts to read the presets and the displays' resolutions again whenever they
/// change, so the phrases that name one stay current.
@MainActor
final class ShortcutParameterUpdates {
    private var observation: ObservationLoop?
    private var last: Snapshot?
    private let update: @MainActor () -> Void

    /// What the phrases name: preset names and each display's listed resolutions.
    private struct Snapshot: Equatable {
        var presets: [String]
        var resolutions: [String]
    }

    init(update: @escaping @MainActor () -> Void = { ResoluteShortcuts.updateAppShortcutParameters() }) {
        self.update = update
    }

    func start(model: AppModel) {
        observation = ObservationLoop { [weak self, weak model] in
            guard let self, let model else { return }
            let snapshot = Snapshot(
                presets: model.presets.map(\.name),
                resolutions: ShortcutCatalog.resolutions(of: model.displays, onlyOn: nil).map(\.id)
            )
            guard snapshot != last else { return }
            last = snapshot
            update()
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
    }
}
