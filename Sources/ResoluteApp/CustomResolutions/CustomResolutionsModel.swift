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

        /// What VoiceOver reads for the display in the list.
        var accessibilityLabel: String {
            [
                name,
                isConnected ? "connected" : "not connected",
                hasOverride ? "has a custom override" : "no custom override",
            ].joined(separator: ", ")
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

        /// The whole row as VoiceOver reads it: "1280 by 800, HiDPI, rendered at 2560 by
        /// 1600, aspect ratio 16:10". Sizes say "by": "×" is read as "multiplied by".
        var accessibilityLabel: String {
            var parts = [resolution.replacingOccurrences(of: "×", with: "by")]
            switch entry.describedMode {
            case .hiDPI?:
                parts.append("HiDPI")
                if let pixels = entry.pixelSize {
                    parts.append("rendered at \(pixels.width) by \(pixels.height)")
                }
            case .standard?:
                parts.append("1x")
            case .preserved?, nil:
                parts.append("kept as is")
            }
            if entry.pixelSize != nil {
                parts.append("aspect ratio \(aspectRatio)")
            }
            return parts.joined(separator: ", ")
        }
    }

    /// The note under the table when an edit leaves HiDPI entries without their 1× entry,
    /// and the title of its button, which adds them back.
    struct UnpairedNote: Equatable {
        var text: String
        var actionTitle: String

        /// Names up to two entries, then counts the rest.
        init(_ entries: [ScaleResolution]) {
            let names = entries.map { "\($0.sizeText) \($0.kindText)" }
            let reason = "which Resolute and RDM add with each HiDPI entry."
            switch entries.count {
            case 1:
                text = "\(names[0]) no longer has its 1× entry at \(Self.pixels(entries[0])), \(reason)"
            case 2:
                text = "\(names[0]) and \(names[1]) no longer have their 1× entries at "
                    + "\(Self.pixels(entries[0])) and \(Self.pixels(entries[1])), \(reason)"
            default:
                text = "\(names[0]), \(names[1]) and \(entries.count - 2) more no longer have their 1× entries, \(reason)"
            }
            actionTitle = entries.count == 1 ? "Add 1× Entry" : "Add 1× Entries"
        }

        private static func pixels(_ entry: ScaleResolution) -> String {
            entry.pixelSize.map { "\($0.width) × \($0.height)" } ?? "its pixel size"
        }
    }

    /// A message shown in an alert.
    struct Notice: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
    }

    /// A backup Restore Backup… offers, read when the list opens.
    struct BackupChoice: Identifiable, Equatable {
        var backup: OverrideBackup
        /// The override the backup holds, and its bytes, which a restore writes as they are.
        var contents: (override: DisplayOverride, data: Data)?
        /// Why the backup can't be read; it is listed, but cannot be chosen.
        var failure: String?

        var id: URL { backup.id }
        var canRestore: Bool { contents != nil }

        /// "2 entries · sets the name “Studio”", or why it can't be read.
        var detail: String {
            guard let override = contents?.override else { return "Can't be read: \(failure ?? "unknown reason")" }
            let count = override.resolutions.count
            let entries = count == 1 ? "1 entry" : "\(count) entries"
            let name = override.productName.map { "sets the name “\($0)”" } ?? "keeps the display's own name"
            return "\(entries) · \(name)"
        }

        /// The backup's entries, as the table shows them.
        var rows: [Row] {
            (contents?.override.resolutions ?? []).map { Row(entry: $0) }
        }

        /// When the backup was made. Its name has the time in UTC; people read their own.
        func dateText(timeZone: TimeZone = .current, locale: Locale = .current) -> String {
            backup.date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
        }

        static func == (lhs: BackupChoice, rhs: BackupChoice) -> Bool {
            lhs.backup == rhs.backup && lhs.contents?.data == rhs.contents?.data && lhs.failure == rhs.failure
        }
    }

    /// A save, removal or restore held back because the override's file changed after it
    /// was read, by another app or the `resolute` command. No password is asked for until
    /// the person has seen this.
    struct Conflict: Identifiable {
        enum Change: Equatable {
            case save
            case remove
            case restore(BackupChoice)

            var failureTitle: String {
                switch self {
                case .save: "The override could not be saved"
                case .remove: "The override could not be removed"
                case .restore: "The backup could not be restored"
                }
            }
        }

        let id = UUID()
        var change: Change
        var key: OverrideKey
        var displayName: String
        /// What the file holds now. Going ahead expects exactly this, so a change made after
        /// this read is caught again.
        var current: OverrideFileState
        var hasUnsavedChanges: Bool

        var title: String { "The override for \(displayName) changed after it was opened" }

        var message: String {
            let removed = current == .absent
            var text = removed
                ? "It was removed by another app or the resolute command."
                : "It was changed by another app or the resolute command."
            if hasUnsavedChanges { text += " Your changes are still here." }
            switch change {
            case .save where removed:
                text += " \(proceedTitle ?? "") saves them as a new file, and \(discardTitle) shows what macOS uses now."
            case .save:
                text += " \(proceedTitle ?? "") replaces the file with them, and \(discardTitle) opens it as it is now."
            case .remove where removed:
                text += " \(discardTitle) shows what macOS uses now."
            case .remove:
                text += " \(proceedTitle ?? "") removes it as it is now, keeping a backup, and \(discardTitle) opens it first."
            case .restore where removed:
                text += " \(proceedTitle ?? "") puts the backup back, and \(discardTitle) shows what macOS uses now."
            case .restore:
                text += " \(proceedTitle ?? "") replaces it with the backup, keeping a backup of it, and \(discardTitle) opens it first."
            }
            return text
        }

        /// Save Anyway, Remove Anyway or Restore Anyway; nil when there is nothing left to do.
        var proceedTitle: String? {
            switch change {
            case .save: "Save Anyway"
            case .remove: current == .absent ? nil : "Remove Anyway"
            case .restore: "Restore Anyway"
            }
        }

        /// Reading the file again drops unsaved changes, when there are any.
        var discardTitle: String { hasUnsavedChanges ? "Discard My Changes" : "Reload" }
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
    /// What the installed file (the one a save replaces) held at the read that loaded the
    /// override on screen. Nil when that file could not be read, such as without permission.
    private(set) var installedState: OverrideFileState?
    /// Backups of the selected display's override, newest first.
    private(set) var backups: [OverrideBackup] = []
    private(set) var isWorking = false
    /// A display someone picked while the current one has unsaved changes.
    private(set) var pendingSelection: OverrideKey?
    /// A change waiting for the person to decide, because the file changed on disk.
    private(set) var conflict: Conflict?
    /// True when the installed file changed after it was read while there are unsaved
    /// changes: the editor keeps them and shows a banner, and Save asks first.
    private(set) var changedOnDisk = false
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
        let path = store.locations.userFile(for: selection).path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path) && !hasFolder(inPlaceOf: selection)
    }

    /// Whether Restore Backup… can run: the display has backups, and no unsaved changes
    /// would be lost. A folder in the file's place is never written over.
    var canRestoreBackup: Bool {
        guard let selection, !backups.isEmpty, !hasChanges, !isWorking else { return false }
        return !hasFolder(inPlaceOf: selection)
    }

    var restoreBackupHelp: String {
        hasChanges ? "Save or revert your changes before restoring a backup." : "Put back an earlier version of this override."
    }

    /// Whether a folder sits where `key`'s installed file goes.
    private func hasFolder(inPlaceOf key: OverrideKey) -> Bool {
        var isFolder: ObjCBool = false
        let path = store.locations.userFile(for: key).path(percentEncoded: false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && isFolder.boolValue
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
    /// instead, so the window can ask first. Choosing the selected display again reads it
    /// again.
    func requestSelection(_ key: OverrideKey?) {
        guard !isWorking, let key else { return }
        guard key != selection else {
            refresh()
            return
        }
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

    /// Reads the displays and the selected override again, for a window that comes back
    /// into use: another app or `resolute` may have changed them meanwhile. A changed file
    /// is read again, unless there are unsaved changes, which stay, under a banner.
    func refresh() {
        // A pending decision about the file stays as it was shown.
        guard !isWorking, conflict == nil else { return }
        reloadTargets()
        guard let selection else { return }
        backups = store.backups(for: selection)
        // An override that could not be read has nothing to lose.
        guard draft != nil else {
            load()
            return
        }
        guard (try? store.installedState(for: selection)) != installedState else {
            changedOnDisk = false
            return
        }
        if hasChanges {
            changedOnDisk = true
        } else {
            load()
        }
    }

    /// Reads the selected display's override, and what its installed file holds, afresh.
    private func load() {
        selectedEntries = []
        readFailure = nil
        conflict = nil
        changedOnDisk = false
        guard let selection else {
            draft = nil
            installedState = nil
            backups = []
            return
        }
        backups = store.backups(for: selection)
        do {
            let file = try store.editableFile(for: selection)
            draft = OverrideDraft(file.override)
            source = file.source
            installedState = file.installedState
        } catch {
            draft = nil
            readFailure = error.localizedDescription
            // Remove Override… and Show in Finder act only on the installed file: Apple's
            // file is not Resolute's to remove.
            let installed = store.locations.userFile(for: selection).path(percentEncoded: false)
            if case ResoluteError.overrideUnreadable(installed, _) = error {
                source = .installed
                // Its bytes, when only they are wrong, so that removing it checks them too.
                installedState = try? store.installedState(for: selection)
            } else {
                source = .system
                // Apple's file is read only when there is no installed one.
                installedState = .absent
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

    /// Shown when this edit left HiDPI entries without the 1× entry at their pixel size.
    var unpairedNote: UnpairedNote? {
        guard let entries = draft?.newlyUnpairedHiDPIEntries, !entries.isEmpty else { return nil }
        return UnpairedNote(entries)
    }

    /// Adds back the 1× entries `unpairedNote` names.
    func addMissingPartners() {
        guard !isWorking, let entries = draft?.newlyUnpairedHiDPIEntries else { return }
        for entry in entries {
            guard let pixels = entry.pixelSize else { continue }
            // One too large to add stays named in the note.
            try? draft?.add(.standard(width: pixels.width, height: pixels.height))
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
        // The version the edits started from is gone, so going back opens the new one.
        guard !changedOnDisk else {
            load()
            return
        }
        draft?.revert()
        selectedEntries = []
    }

    func save() async {
        guard let key = selection, canSave else { return }
        await attempt(.save, on: key)
    }

    /// Removes the installed file. One that another tool removed since it was read goes
    /// through the check too, which says so, rather than the button doing nothing.
    func removeOverride() async {
        guard !isWorking, let selection, source == .installed, !hasFolder(inPlaceOf: selection) else { return }
        await attempt(.remove, on: selection)
    }

    // MARK: - Backups

    /// The selected display's backups, newest first, with what each holds.
    func backupChoices() -> [BackupChoice] {
        guard let selection else { return [] }
        return store.backups(for: selection).map { backup in
            do {
                return BackupChoice(backup: backup, contents: try store.contents(of: backup))
            } catch ResoluteError.overrideUnreadable(_, let reason) {
                return BackupChoice(backup: backup, failure: reason)
            } catch {
                return BackupChoice(backup: backup, failure: error.localizedDescription)
            }
        }
    }

    /// Writes `choice`'s backup back as it is; the installer backs up the file it replaces.
    func restore(_ choice: BackupChoice) async {
        guard let key = selection, choice.backup.key == key, choice.canRestore, canRestoreBackup else { return }
        await attempt(.restore(choice), on: key)
    }

    // MARK: - Changes on disk

    /// Goes ahead with a change after the person has seen that the file changed: Save
    /// Anyway or Remove Anyway. It expects the file to hold what `conflict` read, so a
    /// change made after that is caught again.
    func proceed(with conflict: Conflict) async {
        if self.conflict?.id == conflict.id { self.conflict = nil }
        guard !isWorking, conflict.key == selection, conflict.proceedTitle != nil else { return }
        await run(conflict.change, on: conflict.key, expecting: conflict.current)
    }

    /// Reads the selected override again, dropping unsaved changes: Discard My Changes,
    /// and Reload.
    func reloadFromDisk() {
        guard !isWorking else { return }
        load()
        reloadTargets()
    }

    func cancelConflict() {
        conflict = nil
    }

    /// Runs `change` when the installed file still holds what it held when it was read;
    /// otherwise sets `conflict`, before anything asks for a password.
    private func attempt(_ change: Conflict.Change, on key: OverrideKey) async {
        // Unknown when the file could not be read; the script then checks nothing either.
        if let expected = installedState {
            let current: OverrideFileState
            do {
                current = try store.installedState(for: key)
            } catch {
                notice = Notice(title: change.failureTitle, detail: error.localizedDescription)
                return
            }
            guard current == expected else {
                conflict = makeConflict(change, on: key, current: current)
                return
            }
        }
        await run(change, on: key, expecting: installedState)
    }

    /// Runs `change` through the installer, whose script checks again that the file holds
    /// `state`: someone may change it between the check and the password prompt.
    private func run(_ change: Conflict.Change, on key: OverrideKey, expecting state: OverrideFileState?) async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch change {
            case .save:
                guard let written = draft?.working else { return }
                let data = try written.propertyListData()
                try await installer.install(contents: data, for: key, expecting: state)
                // Editing is locked while saving, so this is the version that was written.
                if selection == key, draft?.working == written {
                    draft?.markSaved()
                    source = .installed
                    installedState = .contents(data)
                    changedOnDisk = false
                    backups = store.backups(for: key)
                }
                notice = Notice(
                    title: "Custom resolutions saved",
                    detail: "Reconnect the display or restart your Mac to use them."
                )
            case .remove:
                try await installer.remove(key, expecting: state)
                load()
                notice = Notice(
                    title: "Override removed",
                    detail: "A backup is in \(store.locations.backupRoot.path(percentEncoded: false)). Reconnect the display or restart your Mac to go back to its default resolutions."
                )
            case .restore(let choice):
                guard let data = choice.contents?.data else { return }
                try await installer.install(contents: data, for: key, expecting: state)
                load()
                notice = Notice(
                    title: "Backup restored",
                    detail: "Reconnect the display or restart your Mac to use it."
                        + (state == .absent ? "" : " The file it replaced is in the backups too.")
                )
            }
            reloadTargets()
        } catch ResoluteError.cancelled {
            return
        } catch ResoluteError.overrideChanged {
            // Changed between the check and the script: ask as if the check had caught it.
            do {
                conflict = makeConflict(change, on: key, current: try store.installedState(for: key))
            } catch {
                notice = Notice(title: change.failureTitle, detail: error.localizedDescription)
            }
        } catch ResoluteError.overridesBusy {
            notice = Notice(
                title: "Another Resolute command is editing overrides",
                detail: "It has been editing them for too long. Try again when it has finished."
                    + (hasChanges ? " Your changes are still here." : "")
            )
        } catch {
            notice = Notice(title: change.failureTitle, detail: error.localizedDescription)
        }
    }

    private func makeConflict(_ change: Conflict.Change, on key: OverrideKey, current: OverrideFileState) -> Conflict {
        Conflict(
            change: change,
            key: key,
            displayName: targets.first { $0.key == key }?.name ?? "this display",
            current: current,
            hasUnsavedChanges: hasChanges
        )
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
