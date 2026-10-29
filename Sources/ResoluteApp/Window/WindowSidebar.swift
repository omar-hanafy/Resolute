import ResoluteDesign
import ResoluteKit
import SwiftUI

/// A row of the window's sidebar, which names a page without its tab.
enum SidebarDestination: Hashable {
    case display(DisplayTarget)
    case presets
    case history
    case settings
}

/// What the window's sidebar lists (Figma: Window › Resolution 31:5, Sidebar Header 18:129 and
/// Sidebar Item 18:128): the connected displays in the app model's order, the displays that
/// are away but have an override file (or unsaved changes), then Presets, History and Settings.
struct SidebarContent: Equatable {
    struct Item: Equatable, Identifiable {
        var destination: SidebarDestination
        var title: String
        var symbol: Symbol
        /// "Main", or the number of presets.
        var detail: String?
        var isDimmed = false

        var id: SidebarDestination { destination }
    }

    var displays: [Item]
    var notConnected: [Item]
    var resolute: [Item]

    @MainActor
    init(model: AppModel, editors: DisplayEditors) {
        displays = model.displays.map { display in
            Item(
                destination: .display(.id(display.id)),
                title: display.name,
                symbol: display.isBuiltin ? .laptopcomputer : .display,
                // Which display has the menu bar matters only when there is another.
                detail: display.isMain && model.displays.count > 1 ? "Main" : nil
            )
        }
        let history = model.historyEntries
        var away = model.notConnectedTargets.map { target in
            Item(
                destination: .display(.overrideKey(target.key)),
                title: DisplayPagePresentation.notConnectedName(for: target.key, listed: target.name, history: history),
                symbol: .display,
                isDimmed: true
            )
        }
        let listed = Set(model.overrideTargets.map(\.key))
        for key in editors.unsavedKeysOutside(listed) {
            let name = DisplayPagePresentation.notConnectedName(
                for: key, listed: editors.existingEditor(for: key)?.selectedTarget?.name, history: history
            )
            away.append(Item(destination: .display(.overrideKey(key)), title: name, symbol: .display, isDimmed: true))
        }
        notConnected = away
        let presets = model.presets.count
        resolute = [
            Item(destination: .presets, title: "Presets", symbol: .star, detail: presets > 0 ? String(presets) : nil),
            Item(destination: .history, title: "History", symbol: .clockArrowCirclepath),
            Item(destination: .settings, title: "Settings", symbol: .gearshape),
        ]
    }

    /// The row `route` selects. A connected display named by its override key selects its
    /// row under Displays.
    @MainActor
    static func destination(for route: AppRoute, model: AppModel) -> SidebarDestination {
        switch route {
        case .display(let target, _):
            if case .overrideKey = target, let display = model.display(for: target) {
                return .display(.id(display.id))
            }
            return .display(target)
        case .presets: return .presets
        case .history: return .history
        case .settings: return .settings
        }
    }

    /// The page choosing `destination` goes to from `current`: a display on the tab the
    /// window is on, if that display has it; Settings on its tab.
    @MainActor
    static func route(for destination: SidebarDestination, from current: AppRoute, model: AppModel) -> AppRoute {
        switch destination {
        case .display(let target):
            var tab = DisplayTab.resolution
            if case .display(_, let currentTab) = current { tab = currentTab }
            return .display(target, tab: DisplayPagePresentation.tab(tab, isConnected: model.display(for: target) != nil))
        case .presets:
            return .presets
        case .history:
            return .history
        case .settings:
            if case .settings = current { return current }
            return .settings()
        }
    }
}

/// The window's sidebar, its selection the window's page.
struct WindowSidebar: View {
    let model: AppModel
    let editors: DisplayEditors
    @Bindable var navigation: WindowNavigation

    var body: some View {
        let content = SidebarContent(model: model, editors: editors)
        let selected = SidebarContent.destination(for: navigation.route, model: model)
        List(selection: Binding<SidebarDestination?>(
            get: { selected },
            set: { destination in
                guard let destination, destination != selected else { return }
                navigation.route = SidebarContent.route(for: destination, from: navigation.route, model: model)
            }
        )) {
            section("Displays", items: content.displays, selected: selected)
            if !content.notConnected.isEmpty {
                section("Not Connected", items: content.notConnected, selected: selected)
            }
            section("Resolute", items: content.resolute, selected: selected)
        }
        .listStyle(.sidebar)
        .sidebarItemStyle(.list)
    }

    private func section(_ title: String, items: [SidebarContent.Item], selected: SidebarDestination) -> some View {
        Section {
            ForEach(items) { item in
                SidebarItem(
                    item.title, symbol: item.symbol, detail: item.detail,
                    isSelected: item.destination == selected, isDimmed: item.isDimmed
                )
                .tag(item.destination)
            }
        } header: {
            SidebarHeader(title)
        }
    }
}
