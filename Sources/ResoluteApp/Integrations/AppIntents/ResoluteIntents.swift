import AppIntents
import Foundation

// Resolute's actions in Shortcuts, Siri and Spotlight (Figma: System integrations › Shortcuts
// 45:262, Spotlight 45:442). Each runs in the app, through `ShortcutActions`, so it is
// guarded and recorded in History as the panel's actions are, with Shortcuts as the source.
// macOS finds them through Metadata.appintents, which Scripts/build-app.sh writes.

/// Apply Resolute preset “Coding”.
struct ApplyPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Preset"
    static var description: IntentDescription? {
        IntentDescription("Applies a preset: mirroring first, then each display’s resolution and refresh rate.")
    }

    @Parameter(title: "Preset")
    var preset: PresetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Apply Resolute preset \(\.$preset)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = try await ShortcutActions.current().applyPreset(preset)
        return .result(dialog: "Applied “\(name)”.")
    }
}

/// Set resolution of DELL U2723QE to 2560 × 1440.
struct SetResolutionIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Resolution"
    static var description: IntentDescription? {
        IntentDescription("Switches a display to one of the resolutions it lists. Hidden modes aren’t offered, since nobody may be watching the display.")
    }

    /// When left empty, the display the resolution belongs to.
    @Parameter(title: "Display")
    var display: DisplayEntity?

    @Parameter(title: "Resolution")
    var resolution: ResolutionEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set resolution of \(\.$display) to \(\.$resolution)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DisplayEntity> & ProvidesDialog {
        let display = try await ShortcutActions.current().setResolution(resolution, on: display)
        return .result(value: display, dialog: "\(display.name) is at \(display.resolution).")
    }
}

/// Set refresh rate of Built-in Retina Display to 120 Hz.
struct SetRefreshRateIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Refresh Rate"
    static var description: IntentDescription? {
        IntentDescription("Switches a display to another refresh rate at its current resolution.")
    }

    @Parameter(title: "Display")
    var display: DisplayEntity

    @Parameter(title: "Refresh Rate")
    var rate: RefreshRateEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set refresh rate of \(\.$display) to \(\.$rate)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<DisplayEntity> & ProvidesDialog {
        let display = try await ShortcutActions.current().setRefreshRate(rate, on: display)
        return .result(value: display, dialog: "\(display.name) is at \(display.refreshRate).")
    }
}

/// Turn on display mirroring.
struct MirrorDisplaysIntent: AppIntent {
    static let title: LocalizedStringResource = "Mirror Displays"
    static var description: IntentDescription? {
        IntentDescription("Mirrors every display to the main one, or stops mirroring.")
    }

    @Parameter(title: "Mirroring", default: .turnOn)
    var change: MirroringChange

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$change) display mirroring")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let isOn = try await ShortcutActions.current().mirror(change)
        return .result(value: isOn, dialog: isOn ? "Mirroring is on." : "Mirroring is off.")
    }
}

/// Get all displays from Resolute.
struct GetDisplaysIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Displays"
    static var description: IntentDescription? {
        IntentDescription("Gets the connected displays, with each one’s resolution and refresh rate.")
    }

    @Parameter(title: "Displays", default: .all)
    var scope: DisplayScope

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$scope) from Resolute")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[DisplayEntity]> {
        .result(value: try await ShortcutActions.current().displays(scope))
    }
}

/// Open Resolute.
struct OpenResoluteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Resolute"
    static var description: IntentDescription? {
        IntentDescription("Opens the Resolute window.")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try await ShortcutActions.current().openWindow()
        return .result()
    }
}
