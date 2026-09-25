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
                } else {
                    ContentUnavailableView(
                        "No Display Selected",
                        systemImage: "display",
                        description: Text("Choose a display to edit its custom resolutions.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private struct OverrideEditor: View {
    @Bindable var model: CustomResolutionsModel
    @State private var tableSelection = Set<Int>()
    @State private var isAdding = false
    @State private var isConfirmingRemoval = false

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

            LabeledContent("Name shown by macOS") {
                TextField("Name shown by macOS", text: $model.productName, prompt: Text("The display's own name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
            }

            Table(model.rows, selection: $tableSelection) {
                TableColumn("Resolution") { row in Text(row.resolution).monospacedDigit() }
                TableColumn("Type") { row in Text(row.kind) }
                    .width(min: 60, ideal: 80)
                TableColumn("Rendered At") { row in
                    Text(row.pixels).monospacedDigit().foregroundStyle(.secondary)
                }
                TableColumn("Aspect Ratio") { row in Text(row.aspectRatio).foregroundStyle(.secondary) }
                    .width(min: 70, ideal: 90)
            }
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView(
                        "No Custom Resolutions",
                        systemImage: "rectangle.dashed",
                        description: Text("Add a resolution to create an override for this display.")
                    )
                }
            }

            HStack(spacing: 8) {
                Button {
                    isAdding = true
                } label: {
                    Label("Add Resolution", systemImage: "plus")
                }
                Button {
                    model.remove(rows: tableSelection)
                    tableSelection.removeAll()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(tableSelection.isEmpty)
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
                if model.source == .installed {
                    Button("Remove Override…", role: .destructive) { isConfirmingRemoval = true }
                    Button("Show in Finder") { model.revealInFinder() }
                }
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
        .confirmationDialog("Remove the custom override for this display?", isPresented: $isConfirmingRemoval) {
            Button("Remove Override", role: .destructive) { Task { await model.removeOverride() } }
        } message: {
            Text("macOS goes back to the display's default resolutions after you reconnect it or restart. A backup is kept.")
        }
        .onChange(of: model.selection) {
            tableSelection.removeAll()
        }
    }
}
