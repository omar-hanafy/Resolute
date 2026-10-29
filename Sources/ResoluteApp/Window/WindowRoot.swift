import ResoluteDesign
import ResoluteKit
import SwiftUI

/// The Resolute window's content: the sidebar and the page `navigation.route` names (Figma:
/// Window, page 8:8). The window's toolbar shows the page's title and subtitle, which
/// `MainWindowController` reads from the app model.
struct WindowRoot: View {
    let model: AppModel
    @Bindable var navigation: WindowNavigation
    let editors: DisplayEditors

    /// `editors` must be the shell's, which it asks before quitting.
    init(model: AppModel, navigation: WindowNavigation, editors: DisplayEditors) {
        self.model = model
        self.navigation = navigation
        self.editors = editors
    }

    var body: some View {
        NavigationSplitView {
            WindowSidebar(model: model, editors: editors, navigation: navigation)
                .navigationSplitViewColumnWidth(Metrics.Window.sidebarWidth)
        } detail: {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.windowBackground)
        }
        .onChange(of: model.displays) { old, _ in
            editors.displaysDidChange()
            if let route = WindowRouting.route(navigation.route, afterDisplaysChangedFrom: old, model: model, editors: editors) {
                navigation.route = route
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch navigation.route {
        case .display(let target, let tab):
            DisplayPage(model: model, editors: editors, target: target, tab: tab) { newTab in
                navigation.route = .display(target, tab: newTab)
            }
        case .presets:
            PresetsPage(model: model)
        case .history:
            HistoryPage(model: model)
        case .settings(let tab):
            SettingsPage(model: model, tab: tab)
        }
    }
}

/// Where the window goes when the displays change under it.
enum WindowRouting {
    /// The page to show instead of `route` once the display it names by ID is gone: that
    /// display under Not Connected when it has an override file or unsaved changes, else
    /// the main display. Nil to stay.
    @MainActor
    static func route(
        _ route: AppRoute,
        afterDisplaysChangedFrom old: [Display],
        model: AppModel,
        editors: DisplayEditors
    ) -> AppRoute? {
        guard case .display(.id(let id), let tab) = route, model.display(for: .id(id)) == nil else { return nil }
        if let gone = old.first(where: { $0.id == id }) {
            let key = OverrideKey(display: gone)
            let hasOverride = model.notConnectedTargets.contains { $0.key == key }
            let hasChanges = editors.existingEditor(for: key)?.hasChanges == true
            // An identical monitor still connected now owns the key's page.
            if let twin = model.display(for: .overrideKey(key)) {
                return .display(.id(twin.id), tab: tab)
            }
            if hasOverride || hasChanges {
                return .display(.overrideKey(key), tab: DisplayPagePresentation.tab(tab, isConnected: false))
            }
        }
        return model.defaultRoute
    }
}
