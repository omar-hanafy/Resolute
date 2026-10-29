import SwiftUI

/// The SwiftUI views the shells host, chosen in this one place: the panel owner returns the
/// panel's content from `panel`, the window owner the window's `NavigationSplitView` from
/// `window`. The shells take whatever these return.
@MainActor
enum ShellRoots {
    /// The panel's content. The panel makes it 340 points wide and as tall as it asks, up to
    /// the bottom of the screen; the content draws its own glass and scrolls if it must.
    static func panel(model: AppModel) -> some View {
        PanelRoot(model: model)
    }

    /// The window's content, on the page `navigation.route` names, with each display's
    /// editor from `editors`. The window's toolbar takes the content's toolbar items; its
    /// title and subtitle come from `AppModel.windowTitle(for:)`.
    static func window(model: AppModel, navigation: WindowNavigation, editors: DisplayEditors) -> some View {
        WindowRoot(model: model, navigation: navigation, editors: editors)
    }
}
