import AppKit
import Observation
import ResoluteKit
import UniformTypeIdentifiers

/// What the Presets page does, apart from drawing: applying, saving the current setup,
/// renaming, deleting and importing presets and setting their shortcuts. Every change goes
/// through the app model's `updatePresets`, which writes the file `resolute preset` shares
/// under its lock, and every failure is shown with `showError`.
@MainActor
@Observable
final class PresetsPageModel {
    let app: AppModel

    /// The preset being renamed, while the Rename Preset alert is up.
    var renaming: Preset?
    /// The name typed in the Rename Preset alert.
    var newName = ""
    /// The preset that Delete… asks about.
    var deleting: Preset?
    /// The preset whose shortcut is being recorded, while its popover is up.
    var editingShortcut: UUID?

    /// Picks the file Import… reads; nil when the person cancels. An open panel in the app.
    @ObservationIgnored var chooseImportFile: @MainActor () -> URL? = PresetsPageModel.runOpenPanel

    init(app: AppModel) {
        self.app = app
    }

    /// The presets in their saved order.
    var presets: [Preset] { app.presets }

    func isActive(_ preset: Preset) -> Bool {
        app.isActive(preset)
    }

    func apply(_ preset: Preset) {
        app.applyPreset(preset, from: .window)
    }

    /// New Preset from Current Setup: saves the displays as they are now as "New Preset"
    /// (or "New Preset 2", …), then asks for its name.
    func newPresetFromCurrentSetup() {
        do {
            let preset = try app.saveCurrentSetupAsPreset()
            beginRename(preset)
        } catch {
            app.showError(error, "The preset could not be saved")
        }
    }

    func beginRename(_ preset: Preset) {
        newName = preset.name
        renaming = preset
    }

    /// Renames the preset the alert was for to `newName`. False when it could not be
    /// renamed; the error has been shown.
    @discardableResult
    func commitRename() -> Bool {
        guard let preset = renaming else { return false }
        renaming = nil
        return rename(preset, to: newName)
    }

    @discardableResult
    func rename(_ preset: Preset, to name: String) -> Bool {
        do {
            try app.updatePresets { library in
                guard var current = library.preset(id: preset.id) else { throw PresetError.noLongerExists(preset.id) }
                current.name = name
                try library.update(current)
            }
            return true
        } catch {
            app.showError(error, "The preset could not be renamed")
            return false
        }
    }

    /// Delete…: asks first, through the page's confirmation.
    func beginDelete(_ preset: Preset) {
        deleting = preset
    }

    func delete(_ preset: Preset) {
        deleting = nil
        if editingShortcut == preset.id { editingShortcut = nil }
        do {
            // Deleting a preset someone already deleted from the command line is no error.
            try app.updatePresets { library in library.delete(id: preset.id) }
        } catch {
            app.showError(error, "The preset could not be deleted")
        }
    }

    /// Gives `preset` a shortcut, or takes its shortcut away with nil.
    func setShortcut(_ shortcut: KeyShortcut?, for preset: Preset) {
        do {
            try app.updatePresets { library in try library.setShortcut(shortcut, forPresetWithID: preset.id) }
        } catch {
            app.showError(error, "The shortcut could not be changed")
        }
    }

    /// What already uses `shortcut`, for the recorder of `preset`'s shortcut.
    func shortcutConflict(_ shortcut: KeyShortcut, for preset: Preset) -> String? {
        app.shortcutConflict(shortcut, ignoring: .preset(preset.id))
    }

    /// Import…: adds the presets of a presets file saved elsewhere, such as on another Mac.
    func importPresets() {
        guard let url = chooseImportFile() else { return }
        importPresets(from: url)
    }

    /// Adds every preset `url` holds after the ones there are. A name that is taken gets a
    /// number ("Coding 2"); a shortcut that is taken is left off, so the preset is added
    /// without one. Returns how many were added.
    @discardableResult
    func importPresets(from url: URL) -> Int {
        do {
            let imported = try PresetLibrary(data: Data(contentsOf: url), path: url.path)
            guard !imported.presets.isEmpty else { throw PresetsImportError.empty(fileName: url.lastPathComponent) }
            let panelShortcut = app.preferences.panelShortcut
            return try app.updatePresets { library in
                for var preset in imported.presets {
                    preset.name = library.availableName(preset.name)
                    if let shortcut = preset.shortcut,
                       shortcut == panelShortcut || library.presets.contains(where: { $0.shortcut == shortcut }) {
                        preset.shortcut = nil
                    }
                    try library.add(preset)
                }
                return imported.presets.count
            }
        } catch {
            app.showError(error, "The presets could not be imported")
            return 0
        }
    }

    /// The open panel Import… shows: presets files, which are JSON.
    static func runOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Presets"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Why Import… added nothing.
enum PresetsImportError: LocalizedError, Equatable {
    case empty(fileName: String)

    var errorDescription: String? {
        switch self {
        case .empty(let fileName): "“\(fileName)” has no presets this version of Resolute can read."
        }
    }
}
