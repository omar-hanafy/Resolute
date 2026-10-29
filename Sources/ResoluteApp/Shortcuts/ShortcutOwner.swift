import Foundation
import ResoluteKit

/// What a shortcut that works from anywhere does: open the panel, or apply a preset.
enum ShortcutOwner: Hashable, Sendable {
    case panel
    case preset(UUID)
}

extension AppModel {
    /// Every shortcut that works from anywhere, with what it does: the panel's first, then
    /// each preset's in the presets' order. A shortcut that two of them have (the command
    /// line can give a preset the panel's) belongs to the first.
    var shortcutAssignments: [(shortcut: KeyShortcut, owner: ShortcutOwner)] {
        var assignments: [(shortcut: KeyShortcut, owner: ShortcutOwner)] = []
        if let panel = preferences.panelShortcut, panel.isGlobal {
            assignments.append((panel, .panel))
        }
        for preset in presets {
            guard let shortcut = preset.shortcut, shortcut.isGlobal else { continue }
            assignments.append((shortcut, .preset(preset.id)))
        }
        return assignments
    }

    /// What already uses `shortcut`, as the shortcut recorder says it: "⌃⌥R already opens
    /// the panel." Nil when it is free, or used only by `owner`, whose shortcut is being
    /// changed.
    func shortcutConflict(_ shortcut: KeyShortcut, ignoring owner: ShortcutOwner?) -> String? {
        if owner != .panel, preferences.panelShortcut == shortcut {
            return "\(shortcut.displayText) already opens the panel."
        }
        if let other = presets.first(where: { $0.shortcut == shortcut && owner != .preset($0.id) }) {
            return "\(shortcut.displayText) is already the shortcut for “\(other.name)”."
        }
        return nil
    }
}
