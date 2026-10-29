import CoreGraphics
import Foundation

/// What choosing a menu item does.
public enum MenuAction: Hashable, Sendable {
    case applyMode(displayID: CGDirectDisplayID, modeID: Int32, needsConfirmation: Bool)
    case setMirroring(Bool)
    case openCustomResolutions(displayID: CGDirectDisplayID?)
    /// Open Resolute: the window, on the main display's page.
    case openWindow
    case openSettings
    case quit
}

/// Whether Resolute starts at login.
public enum LaunchAtLoginState: Hashable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    /// Not running from an app bundle, so macOS cannot register it.
    case unavailable
}

/// One menu item, independent of AppKit.
public struct MenuItem: Hashable, Sendable {
    public var title: String
    public var subtitle: String?
    public var badge: String?
    public var symbolName: String?
    public var isChecked: Bool
    public var isEnabled: Bool
    public var action: MenuAction?
    public var keyEquivalent: String
    public var submenu: [MenuNode]?

    public init(
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        symbolName: String? = nil,
        isChecked: Bool = false,
        isEnabled: Bool = true,
        action: MenuAction? = nil,
        keyEquivalent: String = "",
        submenu: [MenuNode]? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.symbolName = symbolName
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.action = action
        self.keyEquivalent = keyEquivalent
        self.submenu = submenu
    }
}

/// An entry in a menu.
public enum MenuNode: Hashable, Sendable {
    case header(String)
    case item(MenuItem)
    case separator
}

/// Preferences and state that shape the menu.
public struct MenuSettings: Hashable, Sendable {
    public var showLowResolutionModes: Bool
    /// True while ⌥ is held: show hidden modes, mode IDs and pixel sizes.
    public var showsDetails: Bool

    public init(showLowResolutionModes: Bool = true, showsDetails: Bool = false) {
        self.showLowResolutionModes = showLowResolutionModes
        self.showsDetails = showsDetails
    }
}

/// Builds the classic menu, which a right-click on the menu bar icon opens (Figma: Menu bar
/// panel › classic menu 25:1842): each display's sizes at hand, More Resolutions and its
/// refresh rate, then Mirror Displays, Open Resolute, Settings… and Quit Resolute. Its items
/// have no images: macOS 27 hides them in menus by default.
public enum MenuModel {
    public static func build(displays: [Display], settings: MenuSettings) -> [MenuNode] {
        var nodes: [MenuNode] = []
        if displays.isEmpty {
            nodes.append(.item(MenuItem(title: "No Displays Found", isEnabled: false)))
        }
        let names = Dictionary(displays.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for (index, display) in ordered(displays).enumerated() {
            if index > 0 { nodes.append(.separator) }
            nodes.append(.header(headerTitle(for: display, names: names)))
            nodes.append(contentsOf: displayItems(for: display, settings: settings))
        }
        nodes.append(.separator)
        if displays.count > 1 {
            let mirroring = displays.contains(where: \.isInMirrorSet)
            nodes.append(.item(MenuItem(title: "Mirror Displays", isChecked: mirroring, action: .setMirroring(!mirroring))))
        }
        nodes.append(.item(MenuItem(title: "Open Resolute", action: .openWindow)))
        nodes.append(.item(MenuItem(title: "Settings…", action: .openSettings, keyEquivalent: ",")))
        nodes.append(.item(MenuItem(title: "Quit Resolute", action: .quit, keyEquivalent: "q")))
        return nodes
    }

    /// A plain-text rendering, for `Resolute --dump-menu` and tests.
    public static func render(_ nodes: [MenuNode]) -> String {
        render(nodes, depth: 0).joined(separator: "\n")
    }

    // MARK: - Pieces

    /// Main display first, then built-in displays, then by ID.
    static func ordered(_ displays: [Display]) -> [Display] {
        displays.sorted { lhs, rhs in
            (lhs.isMain ? 0 : 1, lhs.isBuiltin ? 0 : 1, lhs.id) < (rhs.isMain ? 0 : 1, rhs.isBuiltin ? 0 : 1, rhs.id)
        }
    }

    static func headerTitle(for display: Display, names: [CGDirectDisplayID: String]) -> String {
        guard let source = display.mirrorSourceID, let sourceName = names[source] else { return display.name }
        return "\(display.name) — mirroring \(sourceName)"
    }

    /// A display's sizes at hand, then every size under More Resolutions, then its refresh
    /// rate.
    static func displayItems(for display: Display, settings: MenuSettings) -> [MenuNode] {
        var nodes = quickSizes(for: display, settings: settings)
        nodes.append(.item(MenuItem(
            title: nodes.isEmpty ? "Choose a Resolution" : "More Resolutions",
            submenu: resolutionSubmenu(for: display, settings: settings)
        )))
        guard let current = display.currentMode, current.refreshRate > 0 else { return nodes }
        let options = ModeCatalog.refreshOptions(for: display, includeHidden: settings.showsDetails)
            .filter { $0.refreshRate > 0 }
        let title = "Refresh Rate: " + RefreshRate.format(current.refreshRate)
        if options.count > 1 {
            nodes.append(.item(MenuItem(
                title: title,
                submenu: options.map { option in
                    MenuNode.item(MenuItem(
                        title: RefreshRate.format(option.refreshRate) + idSuffix(option.mode, settings),
                        badge: option.mode.origin == .hidden ? "Hidden" : nil,
                        isChecked: option.isCurrent,
                        action: .applyMode(
                            displayID: display.id, modeID: option.mode.modeID,
                            needsConfirmation: option.mode.origin == .hidden
                        )
                    ))
                }
            )))
        } else {
            nodes.append(.item(MenuItem(title: title, isEnabled: false)))
        }
        return nodes
    }

    /// The sizes the menu offers without a submenu, larger first: a Retina display's
    /// Larger Text ↔ More Space stops, as the panel offers them; another display's default
    /// and native sizes. The size in use is always one of them.
    static func quickSizes(for display: Display, settings: MenuSettings) -> [MenuNode] {
        let currentKey = ModeCatalog.currentKey(for: display)
        let listed = ModeCatalog.groups(display.modes.filter { $0.origin == .system || $0.modeID == display.currentModeID })
        let stops = SpaceStops(display: display).map { Set($0.stops.map(\.key)) }
        return listed.filter { group in
            group.key == currentKey || (stops.map { $0.contains(group.key) } ?? (group.isDefault || group.isNative))
        }.map { group in
            let mode = ModeCatalog.preferredMode(in: group, current: display.currentMode)
            return .item(MenuItem(
                title: group.sizeText + (group.badge.map { " — \($0)" } ?? "") + idSuffix(mode, settings),
                isChecked: group.key == currentKey,
                action: .applyMode(displayID: display.id, modeID: mode.modeID, needsConfirmation: mode.origin == .hidden)
            ))
        }
    }

    static func idSuffix(_ mode: DisplayMode, _ settings: MenuSettings) -> String {
        settings.showsDetails ? "  #\(mode.modeID)" : ""
    }

    static func resolutionSubmenu(for display: Display, settings: MenuSettings) -> [MenuNode] {
        var nodes: [MenuNode] = []
        let currentKey = ModeCatalog.currentKey(for: display)
        let sections = ModeCatalog.sections(
            for: display,
            includeLowResolution: settings.showLowResolutionModes,
            includeHidden: settings.showsDetails
        )
        for section in sections {
            nodes.append(.header(section.kind.title))
            for group in section.groups {
                let mode = ModeCatalog.preferredMode(in: group, current: display.currentMode)
                nodes.append(.item(MenuItem(
                    title: group.sizeText + idSuffix(mode, settings),
                    subtitle: settings.showsDetails && group.isHiDPI ? "\(group.pixelSizeText) pixels" : nil,
                    badge: group.isHidden ? "Hidden" : group.badge,
                    isChecked: group.key == currentKey,
                    action: .applyMode(displayID: display.id, modeID: mode.modeID, needsConfirmation: mode.origin == .hidden)
                )))
            }
        }
        if sections.isEmpty {
            nodes.append(.item(MenuItem(title: "No Modes Available", isEnabled: false)))
        }
        nodes.append(.separator)
        if !settings.showsDetails, let hint = hiddenModesHint(for: display) {
            nodes.append(.item(MenuItem(title: hint, isEnabled: false)))
        }
        if settings.showsDetails, case .untrusted(let reason) = display.privateModes {
            nodes.append(.item(MenuItem(title: "Hidden Modes Unavailable", subtitle: reason, isEnabled: false)))
        }
        nodes.append(.item(MenuItem(title: "Custom Resolutions…", action: .openCustomResolutions(displayID: display.id))))
        return nodes
    }

    /// What holding ⌥ adds to this submenu: resolutions only hidden modes offer, counted as
    /// the menu lists them; failing those, refresh rates of listed resolutions. A hidden
    /// mode in use is listed without ⌥, so it does not count.
    static func hiddenModesHint(for display: Display) -> String? {
        let current = ModeCatalog.currentKey(for: display)
        let hiddenResolutions = ModeCatalog.groups(display.modes).filter { $0.isHidden && $0.key != current }.count
        if hiddenResolutions > 0 { return "Hold ⌥ to Show Hidden Resolutions (\(hiddenResolutions))" }
        let hiddenRates = display.modes.contains { $0.origin == .hidden && $0.modeID != display.currentModeID }
        return hiddenRates ? "Hold ⌥ to Show Hidden Refresh Rates" : nil
    }

    private static func render(_ nodes: [MenuNode], depth: Int) -> [String] {
        let indent = String(repeating: "    ", count: depth)
        var lines: [String] = []
        for node in nodes {
            switch node {
            case .header(let title):
                lines.append("\(indent)# \(title)")
            case .separator:
                lines.append("\(indent)---")
            case .item(let item):
                var line = indent + (item.isChecked ? "✓ " : "  ") + item.title
                if let subtitle = item.subtitle { line += " — \(subtitle)" }
                if let badge = item.badge { line += " [\(badge)]" }
                if !item.isEnabled { line += " (disabled)" }
                if item.submenu != nil { line += " ▸" }
                lines.append(line)
                if let submenu = item.submenu { lines += render(submenu, depth: depth + 1) }
            }
        }
        return lines
    }
}
