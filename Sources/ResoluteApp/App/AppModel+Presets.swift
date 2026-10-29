import Foundation
import ResoluteKit

/// Presets in the app, kept in the same file `resolute preset` reads and writes.
extension AppModel {
    /// The presets, in their saved order.
    var presets: [Preset] {
        presetLibrary.presets
    }

    /// Whether applying `preset` would change nothing: the Active badge.
    func isActive(_ preset: Preset) -> Bool {
        preset.isActive(on: displays)
    }

    /// Changes the presets file under its lock, then reads it again. Names are picked inside
    /// `change`, so two writers never take the same one.
    @discardableResult
    func updatePresets<T>(_ change: (inout PresetLibrary) throws -> T) throws -> T {
        defer { reloadPresets() }
        return try presetStore.update(change)
    }

    /// New Preset from Current Setup: every display's mode now, and mirroring.
    @discardableResult
    func saveCurrentSetupAsPreset(named name: String = "New Preset") throws -> Preset {
        refresh()
        let capture = PresetCapture(displays: displays)
        return try updatePresets { library in
            try library.save(capture, named: library.availableName(name), replacing: false).preset
        }
    }

    /// Applies `preset`, asked for from `source`: mirroring first, then each display, with
    /// listed modes only, so nothing needs Keep or Revert. Each change goes to History.
    ///
    /// It is the preset as the file holds it now: `resolute preset` may have changed or
    /// deleted it since the panel, a menu or a shortcut was set up. A file that can't be read
    /// applies nothing, as `resolute preset apply` does.
    func applyPreset(_ chosen: Preset, from source: HistoryEntry.Source = .panel) {
        do {
            try loadPresets()
        } catch {
            showError(error, "“\(chosen.name)” could not be applied")
            return
        }
        guard let preset = presets.first(where: { $0.id == chosen.id }) else {
            showError(
                PresetNotApplied(details: ["It was deleted outside Resolute, such as with resolute preset delete."]),
                "“\(chosen.name)” could not be applied"
            )
            return
        }
        let before = displays
        guard let result = modeChanges.applyPreset(preset) else { return }
        history(from: source).record(result, applying: preset, displays: before)
        refresh()
        if result.hasFailures {
            let failures = result.displays.compactMap { change -> String? in
                if case .failed(let message) = change.outcome { return "\(change.displayName): \(message)" }
                return nil
            }
            showError(
                PresetNotApplied(details: failures),
                result.changedAnything ? "“\(preset.name)” was applied only in part" : "“\(preset.name)” could not be applied"
            )
        } else if result.appliedNothing {
            showError(
                PresetNotApplied(details: ["Nothing in it applies to the displays connected now."]),
                "“\(preset.name)” could not be applied"
            )
        }
    }
}

/// What went wrong applying a preset, a line for each display.
struct PresetNotApplied: LocalizedError {
    var details: [String]

    var errorDescription: String? { details.joined(separator: "\n") }
}
