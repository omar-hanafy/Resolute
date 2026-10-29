import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// One display's page in the window: its header and tabs, a connected display's Resolution,
/// Custom Resolutions and Picture & Name, or a display that is away with the last two
/// (Figma: 31:5, 34:332, 34:866, not connected 37:1480). While its override has unsaved
/// edits, the unsaved bar along the bottom saves or reverts them.
struct DisplayPage: View {
    let model: AppModel
    let editors: DisplayEditors
    let target: DisplayTarget
    let tab: DisplayTab
    /// False lays the page out at its full height, as tests measure it.
    var scrolls = true
    let onSelectTab: (DisplayTab) -> Void

    var body: some View {
        if let display = model.display(for: target) {
            content(display: display, key: OverrideKey(display: display))
        } else if let key = editors.key(for: target) {
            content(display: nil, key: key)
        } else {
            ContentUnavailableView(
                "Display Not Connected",
                systemImage: Symbol.display.name,
                description: Text("Choose a display in the sidebar.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(display: Display?, key: OverrideKey) -> some View {
        let isConnected = display != nil
        let shownTab = DisplayPagePresentation.tab(tab, isConnected: isConnected)
        // The editor is made once its tabs are opened; until then the header asks only
        // whether one exists.
        let editor = shownTab == .resolution ? editors.existingEditor(for: key) : editors.editor(for: key)
        return PageBody(
            model: model, editors: editors, display: display, key: key, editor: editor,
            tab: shownTab, scrolls: scrolls, onSelectTab: onSelectTab
        )
        .id(key)
    }
}

/// The page's scrolling content and its unsaved bar.
private struct PageBody: View {
    let model: AppModel
    let editors: DisplayEditors
    let display: Display?
    let key: OverrideKey
    let editor: CustomResolutionsModel?
    let tab: DisplayTab
    let scrolls: Bool
    let onSelectTab: (DisplayTab) -> Void

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let editor, let message = editor.unsavedMessage {
                UnsavedBar(
                    message,
                    onRevert: { editor.revert() },
                    onSave: { Task { await editors.save(editor) } }
                )
                .disabled(editors.isWorking)
            }
        }
        .background(Palette.windowBackground)
        // Nothing may change while a save waits for the administrator password.
        .disabled(editor?.isWorking == true)
        .modifier(EditorAlerts(editor: editor))
        .onAppear { refreshEditor() }
        // Another app or `resolute` may change the file while Resolute is in the
        // background; the window also becomes key after its sheets and alerts close.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshEditor()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refreshEditor()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Metrics.DisplayPage.sectionSpacing) {
            header
            if let display {
                SharpScalingBanner(model: model, display: display)
            }
            SegmentedTabs(
                DisplayPagePresentation.tabs(isConnected: display != nil).map { SegmentedTabs.Item($0, $0.title) },
                selection: Binding(get: { tab }, set: { onSelectTab($0) })
            )
            .fixedSize()
            .accessibilityLabel("Display settings")
            tabContent
        }
        .padding(Metrics.DisplayPage.insets)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshEditor() {
        guard tab != .resolution else { return }
        editors.refresh(key)
    }

    @ViewBuilder
    private var header: some View {
        if let display {
            let facts = model.facts(for: display)
            DisplayHeader(
                name: display.name,
                facts: facts.specifications,
                picture: picture(fallback: model.skin(for: display), suggestion: DisplaySkin.suggestion(for: display, details: model.details(for: display))),
                badges: DisplayPagePresentation.badges(
                    for: display, facts: facts, displayCount: model.displays.count,
                    hasOverride: hasOverride, hasUnsavedChanges: editor?.hasChanges == true,
                    sharpScaling: model.sharpScaling.headerBadge(for: display)
                ).map { Badge($0.text, tone: $0.tone) }
            )
        } else {
            DisplayHeader(
                name: name,
                facts: DisplayPagePresentation.notConnectedFacts(for: key, history: model.historyEntries),
                picture: picture(fallback: .display, suggestion: .display),
                badges: DisplayPagePresentation.notConnectedBadges(
                    hasOverride: hasOverride, hasUnsavedChanges: editor?.hasChanges == true
                ).map { Badge($0.text, tone: $0.tone) },
                isPictureDimmed: true
            )
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .resolution:
            if let display {
                ResolutionTab(model: model, display: display)
            }
        case .customResolutions:
            if let editor {
                CustomResolutionsTab(editor: editor, display: display)
            }
        case .pictureAndName:
            if let editor {
                PictureAndNameTab(model: model, editor: editor, display: display)
            }
        }
    }

    private var hasOverride: Bool {
        model.overrideTargets.first { $0.key == key }?.hasOverride ?? editor?.selectedTarget?.hasOverride ?? false
    }

    private var name: String {
        DisplayPagePresentation.notConnectedName(
            for: key,
            listed: model.overrideTargets.first { $0.key == key }?.name ?? editor?.selectedTarget?.name,
            history: model.historyEntries
        )
    }

    /// The draft's picture while there is one; the saved picture otherwise.
    private func picture(fallback: DisplaySkin, suggestion: DisplaySkin) -> DisplayPictureModel {
        if let skin = editor?.pictureSkin, editor?.draft != nil {
            return DisplayPagePresentation.picture(draftSkin: skin, fallback: suggestion)
        }
        return DisplayPictureModel(rawValue: fallback.rawValue) ?? .display
    }
}

/// The editor's questions and notices: a file that changed before a save, removal or
/// restore, and what a save, removal or restore did.
private struct EditorAlerts: ViewModifier {
    let editor: CustomResolutionsModel?

    func body(content: Content) -> some View {
        if let editor {
            content
                .alert(
                    editor.conflict?.title ?? "",
                    isPresented: Binding(get: { editor.conflict != nil }, set: { if !$0 { editor.cancelConflict() } }),
                    presenting: editor.conflict
                ) { conflict in
                    // Each button acts on the conflict it was shown for: dismissing the alert
                    // may clear `editor.conflict` before the action runs.
                    if let proceed = conflict.proceedTitle {
                        Button(proceed, role: .destructive) { Task { await editor.proceed(with: conflict) } }
                    }
                    Button(conflict.discardTitle) { editor.reloadFromDisk() }
                    Button("Cancel", role: .cancel) {}
                } message: { conflict in
                    Text(conflict.message)
                }
                .alert(
                    editor.notice?.title ?? "",
                    isPresented: Binding(get: { editor.notice != nil }, set: { if !$0 { editor.notice = nil } }),
                    presenting: editor.notice
                ) { _ in
                    Button("OK") {}
                } message: { notice in
                    Text(notice.detail)
                }
        } else {
            content
        }
    }
}
