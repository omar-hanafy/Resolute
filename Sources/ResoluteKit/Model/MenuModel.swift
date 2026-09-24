import CoreGraphics
import Foundation

/// What choosing a menu item does.
public enum MenuAction: Hashable, Sendable {
    case applyMode(displayID: CGDirectDisplayID, modeID: Int32, needsConfirmation: Bool)
    case setMirroring(Bool)
    case openCustomResolutions(displayID: CGDirectDisplayID?)
    case toggleLowResolutionModes
    case toggleLaunchAtLogin
    case showAbout
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
    public var launchAtLogin: LaunchAtLoginState
    /// True while ⌥ is held: show hidden modes, mode IDs and pixel sizes.
    public var showsDetails: Bool

    public init(
        showLowResolutionModes: Bool = true,
        launchAtLogin: LaunchAtLoginState = .disabled,
        showsDetails: Bool = false
    ) {
        self.showLowResolutionModes = showLowResolutionModes
        self.launchAtLogin = launchAtLogin
        self.showsDetails = showsDetails
    }
}

/// Builds the status-bar menu from display snapshots.
public enum MenuModel {
    public static func build(displays: [Display], settings: MenuSettings) -> [MenuNode] {
        var nodes: [MenuNode] = []
        if displays.isEmpty {
            nodes.append(.item(MenuItem(title: "No Displays Found", isEnabled: false)))
        }
        let names = Dictionary(displays.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for display in ordered(displays) {
            nodes.append(.header(headerTitle(for: display, names: names)))
            nodes.append(contentsOf: displayItems(for: display, settings: settings))
        }
        nodes.append(.separator)
        if displays.count > 1 {
            let mirroring = displays.contains(where: \.isInMirrorSet)
            nodes.append(.item(MenuItem(
                title: "Mirror Displays", symbolName: "rectangle.on.rectangle",
                isChecked: mirroring, action: .setMirroring(!mirroring)
            )))
        }
        nodes.append(.item(MenuItem(
            title: "Custom Resolutions…", symbolName: "slider.horizontal.3",
            action: .openCustomResolutions(displayID: nil)
        )))
        nodes.append(.separator)
        nodes.append(.item(MenuItem(
            title: "Show Low-Resolution Modes",
            isChecked: settings.showLowResolutionModes, action: .toggleLowResolutionModes
        )))
        nodes.append(.item(launchAtLoginItem(settings.launchAtLogin)))
        nodes.append(.separator)
        nodes.append(.item(MenuItem(title: "About Resolute", action: .showAbout)))
        nodes.append(.item(MenuItem(title: "Quit Resolute", action: .quit, keyEquivalent: "q")))
        return nodes
    }

    public static func launchAtLoginItem(_ state: LaunchAtLoginState) -> MenuItem {
        switch state {
        case .enabled:
            MenuItem(title: "Launch at Login", isChecked: true, action: .toggleLaunchAtLogin)
        case .disabled:
            MenuItem(title: "Launch at Login", action: .toggleLaunchAtLogin)
        case .requiresApproval:
            MenuItem(title: "Launch at Login", subtitle: "Needs approval in System Settings", action: .toggleLaunchAtLogin)
        case .unavailable:
            MenuItem(title: "Launch at Login", subtitle: "Available when Resolute runs from its app bundle", isEnabled: false)
        }
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

    static func displayItems(for display: Display, settings: MenuSettings) -> [MenuNode] {
        let current = display.currentMode
        var nodes: [MenuNode] = [
            .item(MenuItem(
                title: current.map { $0.sizeText + idSuffix($0, settings) } ?? "Choose a Resolution",
                subtitle: current.flatMap { resolutionSubtitle(for: $0, on: display) },
                symbolName: "display",
                submenu: resolutionSubmenu(for: display, settings: settings)
            )),
        ]
        guard let current, current.refreshRate > 0 else { return nodes }
        let options = ModeCatalog.refreshOptions(for: display, includeHidden: settings.showsDetails)
            .filter { $0.refreshRate > 0 }
        let title = RefreshRate.format(current.refreshRate)
        if options.count > 1 {
            nodes.append(.item(MenuItem(
                title: title,
                symbolName: "arrow.triangle.2.circlepath",
                submenu: options.map { option in
                    MenuNode.item(MenuItem(
                        title: RefreshRate.format(option.refreshRate) + idSuffix(option.mode, settings),
                        symbolName: option.mode.origin == .hidden ? "exclamationmark.triangle" : nil,
                        isChecked: option.isCurrent,
                        action: .applyMode(
                            displayID: display.id, modeID: option.mode.modeID,
                            needsConfirmation: option.mode.origin == .hidden
                        )
                    ))
                }
            )))
        } else {
            nodes.append(.item(MenuItem(title: title, symbolName: "arrow.triangle.2.circlepath", isEnabled: false)))
        }
        return nodes
    }

    static func resolutionSubtitle(for mode: DisplayMode, on display: Display) -> String? {
        if mode.isHiDPI { return "HiDPI · \(mode.pixelSizeText) pixels" }
        // Worth saying only on displays that also offer HiDPI modes.
        return display.modes.contains(where: \.isHiDPI) ? "Low resolution (1×)" : nil
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
                    badge: group.isDefault ? "Default" : group.isNative ? "Native" : nil,
                    symbolName: group.isHidden ? "exclamationmark.triangle" : nil,
                    isChecked: group.key == currentKey,
                    action: .applyMode(displayID: display.id, modeID: mode.modeID, needsConfirmation: mode.origin == .hidden)
                )))
            }
        }
        if sections.isEmpty {
            nodes.append(.item(MenuItem(title: "No Modes Available", isEnabled: false)))
        }
        nodes.append(.separator)
        if !settings.showsDetails, display.hiddenModeCount > 0 {
            nodes.append(.item(MenuItem(
                title: "Hold ⌥ to Show Hidden Modes (\(display.hiddenModeCount))", isEnabled: false
            )))
        }
        if settings.showsDetails, case .untrusted(let reason) = display.privateModes {
            nodes.append(.item(MenuItem(title: "Hidden Modes Unavailable", subtitle: reason, isEnabled: false)))
        }
        nodes.append(.item(MenuItem(title: "Custom Resolutions…", action: .openCustomResolutions(displayID: display.id))))
        return nodes
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
