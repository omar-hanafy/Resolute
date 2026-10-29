import Foundation
import Observation
import ResoluteKit

/// The override editors of the window's display pages: one per display, made the first time
/// its Custom Resolutions or Picture & Name tab opens and kept while Resolute runs, so its
/// unsaved changes survive switching pages and tabs, closing the window and the display
/// disconnecting. Both tabs edit the same draft, so one Save writes the picture, the name and
/// the custom resolutions together.
///
/// The shell owns it, gives it to the window's root, and asks it before quitting whether an
/// override is being written and whose changes are unsaved.
@MainActor
@Observable
final class DisplayEditors {
    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let store: OverrideStore
    @ObservationIgnored private let installer: OverrideInstaller
    @ObservationIgnored private let icons: DisplayIcons
    /// Ignored by observation: an editor is made while a page draws, and a new one has
    /// nothing unsaved. What views show comes from the editors' own observable state.
    @ObservationIgnored private var editors: [OverrideKey: CustomResolutionsModel] = [:]

    /// `store` must be the one `model` reads overrides from, so a save shows in the panel and
    /// the window's header at once.
    init(
        model: AppModel,
        store: OverrideStore = OverrideStore(),
        installer: OverrideInstaller = .privileged,
        icons: DisplayIcons = .system
    ) {
        app = model
        self.store = store
        self.installer = installer
        self.icons = icons
    }

    /// The override key of the display `target` names: a connected display's, or the key a
    /// display that is not connected is known by. Nil for a display ID that is gone.
    func key(for target: DisplayTarget) -> OverrideKey? {
        if let display = app.display(for: target) { return OverrideKey(display: display) }
        if case .overrideKey(let key) = target { return key }
        return nil
    }

    /// The editor of `key`'s override, made on first use.
    func editor(for key: OverrideKey) -> CustomResolutionsModel {
        if let editor = editors[key] { return editor }
        let editor = CustomResolutionsModel(
            service: app.service, store: store, installer: installer, icons: icons, pinnedTo: key
        )
        // The panel's pictures, the header and Not Connected read the file through the app.
        editor.didWrite = { [weak app] in app?.refresh() }
        editor.isOtherWriteUnderWay = { [weak self] in self?.isWorking == true }
        editors[key] = editor
        return editor
    }

    func editor(for target: DisplayTarget) -> CustomResolutionsModel? {
        key(for: target).map(editor(for:))
    }

    /// The editor of `key` if one was made, without making one.
    func existingEditor(for key: OverrideKey) -> CustomResolutionsModel? {
        editors[key]
    }

    /// An override is being written, possibly behind the administrator prompt, by an editor
    /// or by Sharp Scaling: quitting refuses, and no other save starts.
    var isWorking: Bool {
        isSaving || app.sharpScaling.working != nil
    }

    /// An editor is writing its override.
    var isSaving: Bool {
        editors.values.contains(where: \.isWorking)
    }

    /// The editors with unsaved changes, by display name.
    var unsavedEditors: [CustomResolutionsModel] {
        editors.values
            .filter(\.hasChanges)
            .sorted { ($0.selectedTarget?.name ?? "", $0.pinnedKey ?? OverrideKey(vendorID: 0, productID: 0))
                < ($1.selectedTarget?.name ?? "", $1.pinnedKey ?? OverrideKey(vendorID: 0, productID: 0)) }
    }

    /// "DELL U2723QE", "DELL U2723QE and LG UltraFine 5K": the displays whose changes
    /// quitting would lose, as the question before quitting names them. Nil when none.
    var unsavedDisplayName: String? {
        let names = unsavedEditors.map { $0.selectedTarget?.name ?? "the display" }
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }

    /// Displays with unsaved changes that are not connected and have no override file, so
    /// the sidebar still lists them under Not Connected.
    func unsavedKeysOutside(_ listed: Set<OverrideKey>) -> [OverrideKey] {
        unsavedEditors.compactMap(\.pinnedKey).filter { !listed.contains($0) }
    }

    /// Saves `editor`'s draft; not while another override is being written, so two
    /// administrator prompts never race for the same files.
    func save(_ editor: CustomResolutionsModel) async {
        guard !isWorking else { return }
        await editor.save()
    }

    /// Reads `key`'s override again when the window comes back into use: another app or
    /// `resolute` may have changed it. Unsaved changes stay, under a banner.
    func refresh(_ key: OverrideKey) {
        editors[key]?.refresh()
    }

    /// The screens changed: each editor reads the displays again, keeping its own.
    func displaysDidChange() {
        for editor in editors.values {
            editor.reloadTargets()
        }
    }
}
