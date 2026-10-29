import AppKit
import ResoluteKit

/// The menu of Resolute's Dock icon, which is there while the window is open (Figma: System
/// integrations › Dock menu 44:76): each display's sizes at hand and its refresh rate, then
/// the presets and Mirror Displays. macOS adds Options, Show All Windows, Hide and Quit
/// under it. Every item goes through the app model, so History records the Dock as the
/// source, and offers listed modes only: nobody may be looking at the display a Dock menu
/// switches, so hidden modes stay in the panel.
@MainActor
enum DockMenu {
    /// The menu for `applicationDockMenu(_:)`, read fresh.
    static func make(model: AppModel) -> NSMenu {
        model.refresh()
        let menu = NSMenu(title: "Resolute")
        menu.autoenablesItems = false
        for (index, display) in model.displays.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: display.name))
            for size in sizes(of: display, presets: model.presets, displays: model.displays) {
                menu.addItem(item(size.title, checked: size.isCurrent) { [weak model] in
                    model?.apply(size.mode, to: display, from: .dock)
                })
            }
            if let rates = refreshRates(of: display, model: model) {
                menu.addItem(rates)
            }
        }
        let presets = model.presets
        if !presets.isEmpty || model.canMirror {
            if !model.displays.isEmpty { menu.addItem(.separator()) }
        }
        if !presets.isEmpty {
            let submenu = NSMenu(title: "Presets")
            submenu.autoenablesItems = false
            for preset in presets {
                submenu.addItem(item(preset.name, checked: model.isActive(preset)) { [weak model] in
                    model?.applyPreset(preset, from: .dock)
                })
            }
            let presetsItem = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
            presetsItem.submenu = submenu
            menu.addItem(presetsItem)
        }
        if model.canMirror {
            let mirroring = model.isMirroring
            menu.addItem(item("Mirror Displays", checked: mirroring) { [weak model] in
                model?.setMirroring(!mirroring, from: .dock)
            })
        }
        return menu
    }

    /// One of a display's sizes in the menu.
    struct Size: Equatable {
        /// "1920 × 1080 — Default".
        var title: String
        var mode: DisplayMode
        var isCurrent: Bool
    }

    /// The sizes at hand, larger first: the one in use, the default, and the ones the
    /// presets give the display. Listed modes only; a hidden mode in use is shown, checked,
    /// so the menu always says where the display is.
    static func sizes(of display: Display, presets: [Preset], displays: [Display]) -> [Size] {
        let currentKey = ModeCatalog.currentKey(for: display)
        let listed = ModeCatalog.groups(display.modes.filter { $0.origin == .system || $0.modeID == display.currentModeID })
        let presetModes = Set(presets.flatMap { preset in
            preset.plan(for: displays).steps.compactMap { step in
                step.display?.id == display.id ? step.mode?.modeID : nil
            }
        })
        return listed.filter { group in
            group.key == currentKey || group.isDefault || group.modes.contains { presetModes.contains($0.modeID) }
        }.map { group in
            Size(
                title: group.sizeText + (group.isDefault ? " — Default" : ""),
                mode: ModeCatalog.preferredMode(in: group, current: display.currentMode),
                isCurrent: group.key == currentKey
            )
        }
    }

    /// "Refresh Rate: 60 Hz", with the rates the display offers at its size; nil when the
    /// display reports none.
    private static func refreshRates(of display: Display, model: AppModel) -> NSMenuItem? {
        guard let current = display.currentMode, current.refreshRate > 0 else { return nil }
        let options = ModeCatalog.refreshOptions(for: display, includeHidden: false).filter { $0.refreshRate > 0 }
        let rates = NSMenuItem(title: "Refresh Rate: " + RefreshRate.format(current.refreshRate), action: nil, keyEquivalent: "")
        guard options.count > 1 else {
            rates.isEnabled = false
            return rates
        }
        let submenu = NSMenu(title: rates.title)
        submenu.autoenablesItems = false
        for option in options {
            let rate = option.refreshRate
            submenu.addItem(item(RefreshRate.format(rate), checked: option.isCurrent) { [weak model] in
                // The Dock offers listed modes only, so no trial runs where nobody may look.
                model?.setRefreshRate(rate, on: display.id, from: .dock, includeHidden: false)
            })
        }
        rates.submenu = submenu
        return rates
    }

    private static func item(_ title: String, checked: Bool, perform: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(DockMenuAction.perform(_:)), keyEquivalent: "")
        item.target = DockMenuAction.shared
        item.representedObject = DockMenuAction.Box(perform)
        item.state = checked ? .on : .off
        return item
    }
}

/// Runs the closure a Dock menu item carries.
@MainActor
final class DockMenuAction: NSObject {
    static let shared = DockMenuAction()

    final class Box: NSObject {
        let perform: @MainActor () -> Void

        init(_ perform: @escaping @MainActor () -> Void) {
            self.perform = perform
        }
    }

    @objc func perform(_ sender: NSMenuItem) {
        (sender.representedObject as? Box)?.perform()
    }
}
