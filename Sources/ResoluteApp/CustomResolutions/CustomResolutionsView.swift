import ResoluteKit
import SwiftUI

/// The Custom Resolutions window: displays on the left, their override on the right.
struct CustomResolutionsView: View {
    @Bindable var model: CustomResolutionsModel

    var body: some View {
        // A plain split rather than NavigationSplitView: hosted in an NSWindow, that one
        // sizes itself to the table's ideal height and pushes content out of the window.
        HStack(spacing: 0) {
            TargetList(model: model)
                .frame(width: 270)
            Divider()
            Group {
                if model.draft != nil {
                    OverrideEditor(model: model)
                } else if let reason = model.readFailure {
                    UnreadableOverride(model: model, reason: reason)
                } else {
                    ContentUnavailableView(
                        "No Display Selected",
                        systemImage: "display",
                        description: Text("Choose a display to edit its custom resolutions.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .alert(
                model.conflict?.title ?? "",
                isPresented: Binding(get: { model.conflict != nil }, set: { if !$0 { model.cancelConflict() } }),
                presenting: model.conflict
            ) { conflict in
                // Each button acts on the conflict it was shown for: dismissing the alert
                // may clear `model.conflict` before the action runs.
                if let proceed = conflict.proceedTitle {
                    Button(proceed, role: .destructive) { Task { await model.proceed(with: conflict) } }
                }
                Button(conflict.discardTitle) { model.reloadFromDisk() }
                Button("Cancel", role: .cancel) {}
            } message: { conflict in
                Text(conflict.message)
            }
        }
        .frame(minWidth: 780, minHeight: 500)
        // Nothing may change while a save waits for the administrator password.
        .disabled(model.isWorking)
        .confirmationDialog(
            "Discard your changes to \(model.selectedTarget?.name ?? "this display")?",
            isPresented: Binding(
                get: { model.pendingSelection != nil },
                set: { if !$0 { model.cancelPendingSelection() } }
            )
        ) {
            Button("Discard Changes", role: .destructive) { model.discardChangesAndSelectPending() }
            Button("Keep Editing", role: .cancel) { model.cancelPendingSelection() }
        } message: {
            Text("Your custom resolutions have not been saved.")
        }
        .alert(
            model.notice?.title ?? "",
            isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            presenting: model.notice
        ) { _ in
            Button("OK") {}
        } message: { notice in
            Text(notice.detail)
        }
    }
}

private struct TargetList: View {
    @Bindable var model: CustomResolutionsModel

    var body: some View {
        let connected = model.targets.filter(\.isConnected)
        let others = model.targets.filter { !$0.isConnected }
        List(selection: Binding(get: { model.selection }, set: { model.requestSelection($0) })) {
            Section("Connected") {
                ForEach(connected) { target in
                    TargetRow(target: target).tag(target.key)
                }
            }
            if !others.isEmpty {
                Section("Other Overrides") {
                    ForEach(others) { target in
                        TargetRow(target: target).tag(target.key)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct TargetRow: View {
    let target: CustomResolutionsModel.Target

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name).lineLimit(1)
                Text(target.detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "display")
                .foregroundStyle(target.isConnected ? .primary : .secondary)
        }
    }
}

/// Stands in for the editor when the display's override can't be read, so the file can
/// still be removed or found without the command line.
private struct UnreadableOverride: View {
    let model: CustomResolutionsModel
    let reason: String

    var body: some View {
        ContentUnavailableView {
            Label("The Override Can't Be Read", systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason)
        } actions: {
            OverrideFileActions(model: model)
        }
    }
}

/// Remove Override… and Show in Finder, for an override file under the user root, and
/// Restore Backup… for a display with backups.
private struct OverrideFileActions: View {
    let model: CustomResolutionsModel
    @State private var isConfirmingRemoval = false
    @State private var isChoosingBackup = false
    @State private var chosenBackup: CustomResolutionsModel.BackupChoice?

    var body: some View {
        if model.canRemoveOverride {
            Button("Remove Override…", role: .destructive) { isConfirmingRemoval = true }
                .confirmationDialog("Remove the custom override for this display?", isPresented: $isConfirmingRemoval) {
                    Button("Remove Override", role: .destructive) { Task { await model.removeOverride() } }
                } message: {
                    Text("macOS goes back to the display's default resolutions after you reconnect it or restart. A backup is kept.")
                }
        }
        if !model.backups.isEmpty {
            Button("Restore Backup…") { isChoosingBackup = true }
                .disabled(!model.canRestoreBackup)
                .help(model.restoreBackupHelp)
                // Restores once the sheet is gone, so a question about the file can show.
                .sheet(isPresented: $isChoosingBackup, onDismiss: restoreChosenBackup) {
                    RestoreBackupSheet(model: model) { chosenBackup = $0 }
                }
        }
        if model.source == .installed {
            Button("Show in Finder") { model.revealInFinder() }
        }
    }

    private func restoreChosenBackup() {
        guard let choice = chosenBackup else { return }
        chosenBackup = nil
        Task { await model.restore(choice) }
    }
}

/// Says the file changed on disk under unsaved changes, which stay until Reload.
private struct ChangedOnDiskBanner: View {
    let model: CustomResolutionsModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("This override changed on disk after you opened it.")
                Text("Your changes are still here. Saving asks before it replaces the new version.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reload") { model.reloadFromDisk() }
                .help("Discard your changes and open the version on disk")
        }
        .padding(10)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

private struct OverrideEditor: View {
    @Bindable var model: CustomResolutionsModel
    @State private var isAdding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.selectedTarget?.name ?? "Display")
                    .font(.title2.weight(.semibold))
                Text(model.sourceDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if model.changedOnDisk {
                ChangedOnDiskBanner(model: model)
            }

            LabeledContent("Name shown by macOS") {
                TextField("Name shown by macOS", text: $model.productName, prompt: Text("The display's own name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }

            Table(model.rows, selection: $model.selectedEntries) {
                TableColumn("Resolution") { row in Text(row.resolution).monospacedDigit() }
                TableColumn("Type") { row in Text(row.kind) }
                    .width(min: 60, ideal: 80)
                TableColumn("Rendered At") { row in
                    Text(row.pixels).monospacedDigit().foregroundStyle(.secondary)
                }
                TableColumn("Aspect Ratio") { row in Text(row.aspectRatio).foregroundStyle(.secondary) }
                    .width(min: 70, ideal: 90)
            }
            // Delete does what the Remove button does; nil turns it off while saving.
            .onDeleteCommand(perform: model.canRemoveSelection ? { model.removeSelection() } : nil)
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView(
                        "No Custom Resolutions",
                        systemImage: "rectangle.dashed",
                        description: Text("Add a resolution to create an override for this display.")
                    )
                }
            }

            if let note = model.unpairedNote {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(note.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(note.actionTitle) { model.addMissingPartners() }
                }
            }

            HStack(spacing: 8) {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Resolution", systemImage: "plus")
                }
                Button {
                    model.removeSelection()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(!model.canRemoveSelection)
                Spacer()
            }

            Label(
                "Changes apply after you reconnect the display or restart your Mac. On Apple silicon Macs, macOS may ignore custom scaled resolutions for some displays.",
                systemImage: "info.circle"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                OverrideFileActions(model: model)
                Spacer()
                if model.isWorking {
                    ProgressView().controlSize(.small)
                }
                Button("Revert") { model.revert() }
                    .disabled(!model.hasChanges || model.isWorking)
                Button("Save…") { Task { await model.save() } }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSave)
            }
        }
        .padding(20)
        .sheet(isPresented: $isAdding) {
            AddResolutionSheet(model: model)
        }
    }
}
