import ResoluteKit
import SwiftUI

/// Lists the selected display's backups, newest first, and hands back the one to restore.
/// The restore itself runs once the sheet is gone, so what it asks can be shown.
struct RestoreBackupSheet: View {
    let model: CustomResolutionsModel
    let onRestore: (CustomResolutionsModel.BackupChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [CustomResolutionsModel.BackupChoice] = []
    @State private var chosenID: URL?

    private var chosen: CustomResolutionsModel.BackupChoice? {
        choices.first { $0.id == chosenID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restore a Backup")
                    .font(.headline)
                Text("Backups of the override for \(model.selectedTarget?.name ?? "this display"), newest first. Restoring puts the backup's file back as it is, and backs up the current file first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            List(choices, selection: $chosenID) { choice in
                BackupRow(choice: choice)
                    .selectionDisabled(!choice.canRestore)
            }
            .listStyle(.bordered)
            .frame(minHeight: 130)

            Text("Entries in this backup")
                .font(.subheadline.weight(.semibold))
            Table(chosen?.rows ?? []) {
                TableColumn("Resolution") { row in Text(row.resolution).monospacedDigit() }
                TableColumn("Type") { row in Text(row.kind) }
            }
            .frame(minHeight: 120)
            .overlay {
                if chosen == nil {
                    Text("Choose a backup to see its entries.")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore") {
                    guard let chosen else { return }
                    onRestore(chosen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(chosen?.canRestore != true || !model.canRestoreBackup)
            }
        }
        .padding(20)
        .frame(width: 560, height: 520)
        .onAppear {
            choices = model.backupChoices()
            chosenID = choices.first(where: \.canRestore)?.id
        }
    }
}

/// When a backup was made and what it holds, or why it can't be read.
private struct BackupRow: View {
    let choice: CustomResolutionsModel.BackupChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(choice.dateText())
                .foregroundStyle(choice.canRestore ? .primary : .secondary)
            HStack(spacing: 4) {
                if !choice.canRestore {
                    Image(systemName: "exclamationmark.triangle")
                        .accessibilityHidden(true)
                }
                Text(choice.detail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
