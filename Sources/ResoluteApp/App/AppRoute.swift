import CoreGraphics
import ResoluteKit

/// A page of the Resolute window. Everything that opens the window names one: the panel,
/// the classic menu, the main menu's Go menu, Settings… (⌘,) and, later, Shortcuts and
/// the Dock menu.
enum AppRoute: Hashable, Sendable {
    /// One display's page, on one of its tabs.
    case display(DisplayTarget, tab: DisplayTab = .resolution)
    case presets
    case history
    case settings(SettingsTab = .general)
}

/// Which display a page is about. A connected display is named by its ID, which lasts
/// until it disconnects; one that is not connected is named by the override key of the
/// file Resolute keeps for it, the only thing left of it.
enum DisplayTarget: Hashable, Sendable {
    case id(CGDirectDisplayID)
    case overrideKey(OverrideKey)
}

/// The tabs of a display's page (Figma: Window › Resolution, Custom Resolutions, Picture & Name).
enum DisplayTab: String, CaseIterable, Hashable, Sendable {
    case resolution
    case customResolutions
    case pictureAndName

    var title: String {
        switch self {
        case .resolution: "Resolution"
        case .customResolutions: "Custom Resolutions"
        case .pictureAndName: "Picture & Name"
        }
    }
}

/// The tabs of Settings (Figma: Settings › General, Command Line & Agents, About).
enum SettingsTab: String, CaseIterable, Hashable, Sendable {
    case general
    case commandLine
    case about

    var title: String {
        switch self {
        case .general: "General"
        case .commandLine: "Command Line & Agents"
        case .about: "About"
        }
    }
}

/// What the window's toolbar shows for a page: "Built-in Retina Display" over
/// "1728 × 1117 · 120 Hz" (Figma: Window › Resolution, the toolbar).
struct WindowTitle: Equatable, Sendable {
    var title: String
    /// Empty when the page has nothing to add under its title.
    var subtitle: String
}
