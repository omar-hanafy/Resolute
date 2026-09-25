import AppKit
import Observation
import ResoluteKit

/// State behind the Custom Resolutions window.
@MainActor
@Observable
final class CustomResolutionsModel {
    /// A display that can have an override: a connected one, or one with an override file.
    struct Target: Identifiable, Hashable {
        var key: OverrideKey
        var name: String
        var isConnected: Bool
        var hasOverride: Bool

        var id: OverrideKey { key }

        var detail: String {
            let ids = "Vendor \(String(key.vendorID, radix: 16)) · Product \(String(key.productID, radix: 16))"
            return hasOverride ? "\(ids) · Custom" : ids
        }
    }

    /// A row in the resolutions table, identified by its entry, which is unique in a list:
    /// a position would name another entry once the list is re-sorted or reverted.
    struct Row: Identifiable, Hashable {
        var entry: ScaleResolution

        var id: ScaleResolution { entry }
        var resolution: String { entry.sizeText }
        var kind: String { entry.kindText }
        var pixels: String { entry.pixelSize.map { "\($0.width) × \($0.height)" } ?? "—" }
        var aspectRatio: String {
            entry.pixelSize.map { AspectRatio(width: $0.width, height: $0.height).description } ?? "—"
        }
    }

    /// A message shown in an alert.
    struct Notice: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
    }

    private(set) var targets: [Target] = []
    private(set) var selection: OverrideKey?
    private(set) var draft: OverrideDraft? {
        // An entry that is gone leaves the selection, or adding it back would select it.
        didSet {
            let listed = selectedEntries.intersection(draft?.working.resolutions ?? [])
            if listed != selectedEntries { selectedEntries = listed }
        }
    }
    /// The entries selected in the table. Cleared whenever a list is read or reverted, so
    /// it never carries over to entries that merely look the same.
    var selectedEntries = Set<ScaleResolution>()
    /// Where the selected display's override comes from, or which file failed to read.
    private(set) var source: OverrideStore.Source = .missing
    /// Why the selected display's override can't be read. The window shows it in place of
    /// the editor, so the display stays selected and its file can still be removed.
    private(set) var readFailure: String?
    private(set) var isWorking = false
    /// A display someone picked while the current one has unsaved changes.
    private(set) var pendingSelection: OverrideKey?
    var notice: Notice?

    @ObservationIgnored private let service: any DisplayControlling
    @ObservationIgnored let store: OverrideStore
    @ObservationIgnored let installer: OverrideInstaller

    init(
        service: any DisplayControlling,
        store: OverrideStore = OverrideStore(),
        installer: OverrideInstaller = .privileged
    ) {
        self.service = service
        self.store = store
        self.installer = installer
        reloadTargets()
    }

    var rows: [Row] {
        (draft?.working.resolutions ?? []).map { Row(entry: $0) }
    }

    var selectedTarget: Target? {
        targets.first { $0.key == selection }
    }

    var hasChanges: Bool { draft?.hasChanges ?? false }

    var canSave: Bool { hasChanges && !isWorking }

    /// Whether Remove Override… is offered: only for a file under the user root. A folder
    /// in the file's place is shown, never deleted with administrator rights.
    var canRemoveOverride: Bool {
        guard let selection, source == .installed else { return false }
        var isFolder: ObjCBool = false
        let path = store.locations.userFile(for: selection).path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder.boolValue
    }

    /// Whether Remove and Delete are available.
    var canRemoveSelection: Bool { !selectedEntries.isEmpty && !isWorking }

    /// The name macOS shows for the display; empty keeps the display's own name.
    var productName: String {
        get { draft?.working.productName ?? "" }
        set {
            guard !isWorking else { return }
            draft?.working.productName = newValue.isEmpty ? nil : newValue
        }
    }

    var sourceDescription: String {
        guard let selection else { return "" }
        switch source {
        case .installed:
            return "Custom override installed at \(store.locations.userFile(for: selection).path(percentEncoded: false))"
        case .system:
            return "macOS ships an override for this display. Saving creates your own copy of it."
        case .missing:
            return "No override yet: macOS uses the display's own list of resolutions."
        }
    }

    // MARK: - Targets

    func reloadTargets() {
        let installed = store.installedKeys()
        var seen = Set<OverrideKey>()
        var result: [Target] = []
        for display in service.displays() {
            let key = OverrideKey(display: display)
            guard seen.insert(key).inserted else { continue }
            result.append(Target(key: key, name: display.name, isConnected: true, hasOverride: installed.contains(key)))
        }
        for key in installed where seen.insert(key).inserted {
            let name = (try? store.installedOverride(for: key))?.productName
                ?? "Display \(String(key.vendorID, radix: 16)):\(String(key.productID, radix: 16))"
            result.append(Target(key: key, name: name, isConnected: false, hasOverride: true))
        }
        // A display with unsaved changes stays listed after it is unplugged.
        if let selection, hasChanges, !result.contains(where: { $0.key == selection }),
           let edited = targets.first(where: { $0.key == selection }) {
            result.append(Target(key: selection, name: edited.name, isConnected: false, hasOverride: edited.hasOverride))
        }
        targets = result
        if let selection, result.contains(where: { $0.key == selection }) { return }
        select(result.first?.key)
    }

    /// Switches to `key`; when that would lose unsaved changes it sets `pendingSelection`
    /// instead, so the window can ask first.
    func requestSelection(_ key: OverrideKey?) {
        guard !isWorking, let key, key != selection else { return }
        if hasChanges {
            pendingSelection = key
        } else {
            select(key)
        }
    }

    func cancelPendingSelection() {
        pendingSelection = nil
    }

    func discardChangesAndSelectPending() {
        guard let key = pendingSelection else { return }
        pendingSelection = nil
        draft?.revert()
        select(key)
    }

    func select(_ key: OverrideKey?) {
        guard key != selection || draft == nil else { return }
        selection = key
        load()
    }

    func select(displayID: CGDirectDisplayID?) {
        reloadTargets()
        guard let displayID, let display = service.displays().first(where: { $0.id == displayID }) else { return }
        requestSelection(OverrideKey(display: display))
    }

    private func load() {
        selectedEntries = []
        readFailure = nil
        guard let selection else {
            draft = nil
            return
        }
        do {
            let (override, source) = try store.editableOverride(for: selection)
            draft = OverrideDraft(override)
            self.source = source
        } catch {
            draft = nil
            readFailure = error.localizedDescription
            // Remove Override… and Show in Finder act only on the installed file: Apple's
            // file is not Resolute's to remove.
            let installed = store.locations.userFile(for: selection).path(percentEncoded: false)
            if case ResoluteError.overrideUnreadable(installed, _) = error {
                source = .installed
            } else {
                source = .system
            }
        }
    }

    // MARK: - Editing

    /// Adds an entry; returns a message when it is not valid.
    func add(_ entry: ScaleResolution) -> String? {
        guard !isWorking else { return "Wait until the save finishes." }
        do {
            try draft?.add(entry)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Removes exactly the selected entries, and the 1× entries this edit added with them.
    func removeSelection() {
        guard !isWorking else { return }
        // Read before `draft?.remove` begins changing the draft.
        let selected = rows.map(\.entry).filter(selectedEntries.contains)
        draft?.remove(selected)
    }

    func revert() {
        guard !isWorking else { return }
        draft?.revert()
        selectedEntries = []
    }

    func save() async {
        guard let draft, let key = selection, canSave else { return }
        let written = draft.working
        isWorking = true
        defer { isWorking = false }
        do {
            try await installer.install(written)
            // Editing is locked while saving, so this is the version that was written.
            if selection == key, self.draft?.working == written {
                self.draft?.markSaved()
                source = .installed
            }
            reloadTargets()
            notice = Notice(
                title: "Custom resolutions saved",
                detail: "Reconnect the display or restart your Mac to use them."
            )
        } catch let error as ResoluteError where error == .cancelled {
            return
        } catch {
            notice = Notice(title: "The override could not be saved", detail: error.localizedDescription)
        }
    }

    func removeOverride() async {
        guard !isWorking, let selection, canRemoveOverride else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await installer.remove(selection)
            load()
            reloadTargets()
            notice = Notice(
                title: "Override removed",
                detail: "A backup is in \(store.locations.backupRoot.path(percentEncoded: false)). Reconnect the display or restart your Mac to go back to its default resolutions."
            )
        } catch let error as ResoluteError where error == .cancelled {
            return
        } catch {
            notice = Notice(title: "The override could not be removed", detail: error.localizedDescription)
        }
    }

    func revealInFinder() {
        guard let selection, source == .installed else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.locations.userFile(for: selection)])
    }
}

extension OverrideInstaller {
    /// The app's installer: scripts run as root after the password prompt. They take the
    /// command line's lock themselves, because the app runs as the user and cannot create
    /// the lock file, so a save never interleaves with `sudo resolute overrides add`.
    static var privileged: OverrideInstaller {
        OverrideInstaller(runner: AdminCommandRunner(), scriptLock: OverrideLocations.standard.lockFile)
    }
}
