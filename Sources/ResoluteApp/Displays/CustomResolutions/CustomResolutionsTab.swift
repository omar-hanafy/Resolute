import ResoluteDesign
import ResoluteKit
import SwiftUI

/// A display's Custom Resolutions tab: a note on when they apply, the override's entries
/// with Add Resolution… and Remove, and the file's actions (Figma: 34:332; not connected,
/// 37:1480). Its edits go into the display's draft, which the page's unsaved bar saves.
struct CustomResolutionsTab: View {
    @Bindable var editor: CustomResolutionsModel
    /// The connected display, for the Add Resolution sheet's comparisons; nil when it is away.
    let display: Display?
    @State private var isAdding = false

    private var name: String { editor.selectedTarget?.name ?? "this display" }

    var body: some View {
        Group {
            if display != nil {
                Banner(
                    "New resolutions appear after reconnecting",
                    message: "After saving, reconnect \(name) or restart your Mac. On Apple silicon, macOS may ignore some custom scaled resolutions.",
                    tone: .info
                )
            } else {
                Banner(
                    "You can edit this display while it’s away",
                    message: "Changes are saved to its override file and apply the next time it connects.",
                    tone: .info
                )
            }
            if editor.changedOnDisk {
                Banner(
                    "This override changed on disk after you opened it",
                    message: "Your changes are still here. Saving asks before replacing it.",
                    tone: .warning,
                    action: Banner.Action("Reload") { editor.reloadFromDisk() }
                )
            }
            if editor.draft != nil {
                if let note = editor.unpairedNote {
                    Banner(
                        "A HiDPI size lost its 1× size",
                        message: note.text,
                        tone: .warning,
                        action: Banner.Action(note.actionTitle) { editor.addMissingPartners() }
                    )
                }
                ResolutionsTable(editor: editor, showsTitle: display != nil, isAdding: $isAdding)
                FileActions(editor: editor, includesEditing: display == nil, isAdding: $isAdding)
                SourceText(editor: editor)
            } else if let reason = editor.readFailure {
                Banner("The override can't be read", message: reason, tone: .warning)
                FileActions(editor: editor, includesEditing: false, isAdding: $isAdding)
                SourceText(editor: editor)
            }
        }
        .sheet(isPresented: $isAdding) {
            AddResolutionSheet(model: editor, display: display)
        }
    }
}

/// The override's entries: "2560 × 1080", "HiDPI · New", "5120 × 2160", "64:27".
private struct ResolutionsTable: View {
    @Bindable var editor: CustomResolutionsModel
    /// Figma titles the table, with Add Resolution… and Remove, only for a connected
    /// display; a display that is away has those under the table.
    let showsTitle: Bool
    @Binding var isAdding: Bool

    static let footnote = "Adding a HiDPI size also adds the 1× size it renders at, as RDM did. Removing it removes that 1× size only if they were added together."

    var body: some View {
        let added = editor.addedEntries
        let rows = editor.rows.map { row in
            let isNew = added.contains(row.entry)
            return TableRowValues(
                id: row.entry,
                values: [row.resolution, isNew ? "\(row.kind) · New" : row.kind, row.pixels, row.aspectRatio],
                accessibilityLabel: row.accessibilityLabel + (isNew ? ", new" : "")
            )
        }
        let footnote = rows.isEmpty
            ? "No custom resolutions yet. Add one to create an override for this display."
            : (showsTitle ? Self.footnote : nil)
        Group {
            if showsTitle {
                DataTable(
                    "Custom Resolutions",
                    columns: DataTableColumn.customResolutions,
                    rows: rows.map { .init(id: $0.id, values: $0.values, accessibilityLabel: $0.accessibilityLabel) },
                    selection: $editor.selectedEntries,
                    footnote: footnote
                ) {
                    TitleButtons(editor: editor, isAdding: $isAdding)
                }
            } else {
                DataTable(
                    columns: DataTableColumn.customResolutions,
                    rows: rows.map { .init(id: $0.id, values: $0.values, accessibilityLabel: $0.accessibilityLabel) },
                    selection: $editor.selectedEntries,
                    footnote: footnote,
                    spacing: Metrics.Spacing.xSmall
                )
            }
        }
        // Delete does what Remove does; nil turns it off while saving.
        .onDeleteCommand(perform: editor.canRemoveSelection ? { editor.removeSelection() } : nil)
    }
}

/// Add Resolution… and Remove, at the end of the table's title.
private struct TitleButtons: View {
    let editor: CustomResolutionsModel
    @Binding var isAdding: Bool

    var body: some View {
        Button("Add Resolution…") { isAdding = true }
            .fixedSize()
        Button("Remove") { editor.removeSelection() }
            .fixedSize()
            .disabled(!editor.canRemoveSelection)
            .help("Remove the selected resolutions")
    }
}

/// Restore Backup…, Remove Override… and Show in Finder; for a display that is away, Add
/// Resolution… (and Remove, while entries are selected) first. The row wraps rather than
/// cutting a title short.
private struct FileActions: View {
    let editor: CustomResolutionsModel
    let includesEditing: Bool
    @Binding var isAdding: Bool
    @State private var isConfirmingRemoval = false
    @State private var isChoosingBackup = false
    @State private var chosenBackup: CustomResolutionsModel.BackupChoice?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.DisplayPage.buttonSpacing) { buttons }
            VStack(alignment: .leading, spacing: Metrics.DisplayPage.buttonSpacing) { buttons }
        }
        .alert(editor.removalTitle, isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { Task { await editor.removeOverride() } }
        } message: {
            Text(editor.removalMessage)
        }
        // Restores once the sheet is gone, so a question about the file can show.
        .sheet(isPresented: $isChoosingBackup, onDismiss: restoreChosenBackup) {
            RestoreBackupSheet(model: editor) { chosenBackup = $0 }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if includesEditing, editor.draft != nil {
            Button("Add Resolution…") { isAdding = true }
            if !editor.selectedEntries.isEmpty {
                Button("Remove") { editor.removeSelection() }
                    .disabled(!editor.canRemoveSelection)
                    .help("Remove the selected resolutions")
            }
        }
        if !editor.backups.isEmpty {
            Button("Restore Backup…") { isChoosingBackup = true }
                .disabled(!editor.canRestoreBackup)
                .help(editor.restoreBackupHelp)
        }
        if editor.canRemoveOverride {
            Button("Remove Override…") { isConfirmingRemoval = true }
        }
        if editor.source == .installed {
            Button("Show in Finder") { editor.revealInFinder() }
        }
    }

    private func restoreChosenBackup() {
        guard let choice = chosenBackup else { return }
        chosenBackup = nil
        Task { await editor.restore(choice) }
    }
}

/// Where the override comes from: the installed file's path, or what macOS uses instead.
private struct SourceText: View {
    let editor: CustomResolutionsModel

    var body: some View {
        if let path = editor.installedPath {
            Text(path)
                .textStyle(.mono)
                .foregroundStyle(Palette.labelTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .accessibilityLabel("Override file: \(path)")
        } else if !editor.sourceDescription.isEmpty {
            Text(editor.sourceDescription)
                .textStyle(.footnote)
                .foregroundStyle(Palette.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
