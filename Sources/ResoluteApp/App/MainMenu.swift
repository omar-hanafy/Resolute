import AppKit
import ResoluteKit

/// The menu bar Resolute shows while its window is open: Resolute, File, Edit, View, Go,
/// Window and Help. While Resolute is only in the menu bar the menus are not shown, but their
/// key equivalents still give text fields and windows their shortcuts.
///
/// ⌘Q belongs to the window: with a window open it closes it (`TerminationPolicy`), and with
/// none it quits. Quit Resolute (⌃⌥⌘Q) always quits, as the first-close notice says.
@MainActor
enum MainMenu {
    /// Where Resolute Help goes: the README on GitHub.
    static let helpURL = URL(string: "https://github.com/omar-hanafy/Resolute#readme")!

    /// Sets the app's menu bar, with `handler` performing Resolute's own items.
    static func install(handler: MainMenuHandler) {
        let menu = make(handler: handler)
        NSApp.mainMenu = menu
        NSApp.servicesMenu = submenu(titled: "Services", in: menu.items.first?.submenu)
        NSApp.windowsMenu = submenu(titled: "Window", in: menu)
        NSApp.helpMenu = submenu(titled: "Help", in: menu)
    }

    /// The menu bar. Without a handler, as in tests, Resolute's own items go up the
    /// responder chain and the Go menu stays empty.
    static func make(handler: MainMenuHandler? = nil) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "Resolute")
        app.addItem(item("About Resolute", #selector(MainMenuHandler.showAbout(_:)), handler))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(MainMenuHandler.showSettings(_:)), handler, key: ","))
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        app.addItem(services)
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Resolute", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        let quit = item("Quit Resolute", #selector(MainMenuHandler.quitResolute(_:)), handler, key: "q")
        quit.keyEquivalentModifierMask = [.control, .option, .command]
        app.addItem(quit)
        // ⌘Q, hidden so the menu shows the shortcut that always quits.
        let commandQ = NSMenuItem(title: "Close Window or Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        commandQ.isHidden = true
        commandQ.allowsKeyEquivalentWhenHidden = true
        app.addItem(commandQ)
        main.addItem(submenuItem(app))

        // Close lives here, as in Apple's apps that have a File menu.
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenuItem(file))

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenuItem(edit))

        let view = NSMenu(title: "View")
        let sidebar = view.addItem(
            withTitle: "Show Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s"
        )
        sidebar.keyEquivalentModifierMask = [.command, .control]
        main.addItem(submenuItem(view))

        let go = NSMenu(title: "Go")
        go.delegate = handler
        main.addItem(submenuItem(go))

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        main.addItem(submenuItem(window))

        let help = NSMenu(title: "Help")
        help.addItem(item("Resolute Help", #selector(MainMenuHandler.showHelp(_:)), handler, key: "?"))
        main.addItem(submenuItem(help))

        return main
    }

    /// The Go menu: each connected display (⌘1 to ⌘9 in the panel's order), the displays that
    /// are not connected but have an override, then Presets and History, as the window's
    /// sidebar lists them.
    static func fillGoMenu(
        _ menu: NSMenu,
        displays: [Display],
        notConnected: [AppModel.OverrideTarget],
        handler: MainMenuHandler?
    ) {
        menu.removeAllItems()
        for (index, display) in displays.enumerated() {
            menu.addItem(goItem(display.name, .display(.id(display.id)), handler, key: index < 9 ? "\(index + 1)" : ""))
        }
        for target in notConnected {
            menu.addItem(goItem(target.name, .display(.overrideKey(target.key)), handler))
        }
        if menu.numberOfItems > 0 { menu.addItem(.separator()) }
        menu.addItem(goItem("Presets", .presets, handler))
        menu.addItem(goItem("History", .history, handler))
    }

    private static func goItem(_ title: String, _ route: AppRoute, _ handler: MainMenuHandler?, key: String = "") -> NSMenuItem {
        let item = item(title, #selector(MainMenuHandler.go(_:)), handler, key: key)
        item.representedObject = RouteBox(route)
        return item
    }

    private static func item(_ title: String, _ action: Selector, _ handler: MainMenuHandler?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = handler
        return item
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func submenu(titled title: String, in menu: NSMenu?) -> NSMenu? {
        menu?.items.first { $0.title == title }?.submenu
    }
}

/// Performs the main menu's Resolute items through the app model, and fills the Go menu
/// each time it opens or a key equivalent is looked up.
@MainActor
final class MainMenuHandler: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let openURL: @MainActor (URL) -> Void

    init(model: AppModel, openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.model = model
        self.openURL = openURL
    }

    /// About is a page of Settings in the window (Figma: Settings › About).
    @objc func showAbout(_ sender: Any?) {
        model.openSettings(.about)
    }

    @objc func showSettings(_ sender: Any?) {
        model.openSettings()
    }

    @objc func quitResolute(_ sender: Any?) {
        model.quit()
    }

    @objc func go(_ sender: NSMenuItem) {
        guard let route = (sender.representedObject as? RouteBox)?.route else { return }
        model.openWindow(route)
    }

    @objc func showHelp(_ sender: Any?) {
        openURL(MainMenu.helpURL)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainMenu.fillGoMenu(menu, displays: model.displays, notConnected: model.notConnectedTargets, handler: self)
    }
}

/// Carries an `AppRoute` in `NSMenuItem.representedObject`.
final class RouteBox: NSObject {
    let route: AppRoute

    init(_ route: AppRoute) {
        self.route = route
    }
}
