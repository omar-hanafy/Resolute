import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// The window's Presets page (Figma: Window › Presets, 37:2289): a card for each preset in
/// its saved order, the active one outlined with its Active badge, the others with Apply;
/// then New Preset from Current Setup and Import…. A card's context menu (and its VoiceOver
/// actions) renames it, records or removes its shortcut and deletes it, asking first.
struct PresetsPage: View {
    let model: AppModel
    @State private var page: PresetsPageModel

    init(model: AppModel) {
        self.model = model
        _page = State(initialValue: PresetsPageModel(app: model))
    }

    var body: some View {
        @Bindable var page = page
        TitledPage("Presets", description: Self.description) {
            if page.presets.isEmpty {
                PresetsEmptyState()
            } else {
                VStack(spacing: Metrics.TitledPage.cardSpacing) {
                    ForEach(page.presets) { preset in
                        card(for: preset)
                    }
                }
            }
            HStack(spacing: Metrics.TitledPage.actionSpacing) {
                Button("New Preset from Current Setup") { page.newPresetFromCurrentSetup() }
                Button("Import…") { page.importPresets() }
            }
        }
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // `resolute preset` may have changed the file while Resolute was in the background.
            model.refresh()
        }
        .alert("Rename Preset", isPresented: isPresent($page.renaming)) {
            TextField("Name", text: $page.newName)
            Button("Rename") { page.commitRename() }
            Button("Cancel", role: .cancel) { page.renaming = nil }
        } message: {
            Text("The name shows in the panel and in resolute preset apply <name>.")
        }
        .confirmationDialog(
            "Delete “\(page.deleting?.name ?? "")”?", isPresented: isPresent($page.deleting), presenting: page.deleting
        ) { preset in
            Button("Delete", role: .destructive) { page.delete(preset) }
            Button("Cancel", role: .cancel) { page.deleting = nil }
        } message: { preset in
            Text(preset.shortcut == nil
                ? "This can’t be undone."
                : "Its shortcut \(preset.shortcut?.displayText ?? "") stops working. This can’t be undone.")
        }
    }

    private func card(for preset: Preset) -> some View {
        PresetCard(
            name: preset.name,
            summary: preset.summary,
            shortcut: preset.shortcut?.displayText,
            isActive: page.isActive(preset),
            onApply: { page.apply(preset) }
        )
        .contextMenu { actions(for: preset) }
        .accessibilityActions { actions(for: preset) }
        .popover(isPresented: isEditingShortcut(of: preset), arrowEdge: .bottom) {
            PresetShortcutEditor(preset: preset, page: page)
        }
    }

    @ViewBuilder private func actions(for preset: Preset) -> some View {
        if !page.isActive(preset) {
            Button("Apply") { page.apply(preset) }
        }
        Button("Rename…") { page.beginRename(preset) }
        Button(preset.shortcut == nil ? "Set Shortcut…" : "Change Shortcut…") { page.editingShortcut = preset.id }
        if preset.shortcut != nil {
            Button("Remove Shortcut") { page.setShortcut(nil, for: preset) }
        }
        Divider()
        Button("Delete…", role: .destructive) { page.beginDelete(preset) }
    }

    private func isEditingShortcut(of preset: Preset) -> Binding<Bool> {
        Binding(
            get: { page.editingShortcut == preset.id },
            set: { if !$0, page.editingShortcut == preset.id { page.editingShortcut = nil } }
        )
    }

    /// Up while `value` is set; dismissing it clears `value`.
    private func isPresent<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    static let description = "A preset remembers the mode of every display. Apply one from the panel, the Dock, "
        + "its shortcut, or resolute preset apply <name>."
}

/// The popover Set Shortcut… opens on a card: the recorder, already recording.
private struct PresetShortcutEditor: View {
    let preset: Preset
    let page: PresetsPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.medium) {
            Text("Shortcut for “\(preset.name)”")
                .textStyle(.headline)
                .foregroundStyle(Palette.labelPrimary)
            ShortcutRecorder(
                shortcut: Binding(
                    get: { preset.shortcut },
                    set: { page.setShortcut($0, for: preset) }
                ),
                style: .chip,
                startsRecording: true,
                conflict: { page.shortcutConflict($0, for: preset) },
                onFinish: { page.editingShortcut = nil }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(ShortcutRecorder.recordingHelp)
                .textStyle(.footnote)
                .foregroundStyle(Palette.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.Spacing.xLarge)
        .frame(width: Self.width)
    }

    private static let width: CGFloat = 260
}

/// What the page shows before there is a preset.
struct PresetsEmptyState: View {
    var body: some View {
        GroupedSection {
            VStack(alignment: .leading, spacing: Metrics.TitledPage.emptyTextSpacing) {
                Text(Self.title)
                    .textStyle(.bodyEmphasized)
                    .foregroundStyle(Palette.labelPrimary)
                Text(Self.text)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    static let title = "No presets yet"
    static let text = "Set your displays the way you like them, then choose New Preset from Current Setup "
        + "to come back to that setup in one click."
}
