import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Lists the display's backups, newest first, and hands back the one to restore (Figma
/// 35:1103). The restore itself runs once the sheet is gone, so what it asks can be shown.
struct RestoreBackupSheet: View {
    let model: CustomResolutionsModel
    let onRestore: (CustomResolutionsModel.BackupChoice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [CustomResolutionsModel.BackupChoice] = []
    @State private var chosenID: URL?

    private var chosen: CustomResolutionsModel.BackupChoice? {
        choices.first { $0.id == chosenID }
    }

    static let columns = [
        DataTableColumn("Saved", width: 200),
        DataTableColumn("Resolutions", width: 110),
        DataTableColumn("Note"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.DisplayPage.Sheet.spacing) {
            Text("Restore a Backup of \(model.selectedTarget?.name ?? "This Display")")
                .textStyle(.headline)
                .foregroundStyle(Palette.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Backups are kept in \(model.store.locations.backupRoot.path(percentEncoded: false)).")
                .textStyle(.subheadline)
                .foregroundStyle(Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            DataTable(
                columns: Self.columns,
                rows: choices.map { choice in
                    .init(
                        id: choice.id,
                        values: [choice.savedText(), choice.resolutionCount, choice.note],
                        accessibilityLabel: choice.accessibilityLabel()
                    )
                },
                selection: $chosenID,
                spacing: Metrics.DisplayPage.Sheet.tableSpacing,
                insets: Metrics.DisplayPage.Sheet.tableInsets
            )

            Text("The file being replaced is backed up first, so restoring can be undone the same way.")
                .textStyle(.footnote)
                .foregroundStyle(Palette.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Metrics.DisplayPage.buttonSpacing) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore…") {
                    guard let chosen else { return }
                    onRestore(chosen)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(chosen?.canRestore != true || !model.canRestoreBackup)
                .help(chosen?.canRestore == false ? "This backup can't be read, so it can't be restored." : "")
            }
        }
        .padding(Metrics.DisplayPage.Sheet.insets)
        .frame(width: Metrics.DisplayPage.Sheet.restoreWidth)
        .onAppear {
            choices = model.backupChoices()
            chosenID = choices.first(where: \.canRestore)?.id
        }
    }
}
