import AppKit
import ResoluteKit
import UserNotifications

/// Starts Resolute: the app model, then the shell around it (the menu bar icon, the panel,
/// the window) and the main menu, and answers AppKit's questions about reopening and
/// quitting.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var model: AppModel?
    private(set) var shell: ShellController?
    private var mainMenu: MainMenuHandler?
    /// The panel's shortcut and the presets' shortcuts, which work from anywhere.
    private var hotKeys: HotKeyCenter?
    /// Answers `resolute set --allow-hidden` with the Keep/Revert dialog on the display.
    private var agentRequests: AgentRequests?
    /// Notifies of an agent's display changes, with Undo, while Settings says to.
    private var agentChanges: AgentChangeNotifier?
    /// Keeps the App Shortcuts that name a preset or a resolution current.
    private var shortcutParameters: ShortcutParameterUpdates?
    /// Welcome, while it is open.
    private var welcome: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The open-application event that launched the app says whether macOS started it
        // at login; it is the current event only now.
        let launchKind = LaunchKind(appleEvent: NSAppleEventManager.shared().currentAppleEvent)
        let model = AppModel(environment: .live(launchKind: launchKind))
        self.model = model
        // Shortcuts and Spotlight actions run through this model from now on. App Shortcuts
        // belong to the app bundle, which the debug binary lacks.
        IntentHost.appModel = model
        if Bundle.main.bundleIdentifier != nil {
            let shortcutParameters = ShortcutParameterUpdates()
            shortcutParameters.start(model: model)
            self.shortcutParameters = shortcutParameters
        }
        let agentRequests = AgentRequests(model: model)
        model.agentRequests = agentRequests
        agentRequests.start()
        self.agentRequests = agentRequests
        // Notification Center needs a bundle identifier, which the debug binary lacks. Its
        // delegate is set before launching ends, so an Undo clicked while Resolute was not
        // running still arrives.
        if let poster = SystemNotificationPoster.make() {
            UNUserNotificationCenter.current().delegate = poster
            let agentChanges = AgentChangeNotifier(model: model, poster: poster)
            agentChanges.start()
            self.agentChanges = agentChanges
        }
        let mainMenu = MainMenuHandler(model: model)
        self.mainMenu = mainMenu
        MainMenu.install(handler: mainMenu)
        shell = ShellController(model: model)
        let hotKeys = HotKeyCenter(registrar: CarbonHotKeyRegistrar())
        hotKeys.start(model: model)
        self.hotKeys = hotKeys
        // The first time the window closes, point at the menu bar icon, where Resolute lives on.
        shell?.window.onClose = { [weak self] in
            MainRunLoop.perform {
                guard let self, let model = self.model, let shell = self.shell else { return }
                _ = FirstCloseNotice.showIfDue(from: shell.statusItem.button, model: model)
            }
        }
        if WelcomeRule.shouldShow(model) {
            showWelcome(model: model)
        }
    }

    /// Welcome, on the first deliberate launch, in front of the window it introduces.
    private func showWelcome(model: AppModel) {
        guard let shell else { return }
        shell.window.show()
        let welcome = WelcomeWindowController(model: model)
        if let window = welcome.window { shell.activation.track(window) }
        welcome.onClose = { [weak self] in self?.welcome = nil }
        welcome.show()
        self.welcome = welcome
    }

    /// The Dock icon's menu while the window is open: presets, displays and window pages.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        model.map { DockMenu.make(model: $0) }
    }

    /// Opened again while running, from Finder, the Dock or Spotlight: show the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shell?.reopen()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        shell?.terminationReply(appleEvent: NSAppleEventManager.shared().currentAppleEvent) ?? .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        agentRequests?.stop()
        agentChanges?.stop()
        // Quit Anyway, with reverts still waiting for their display.
        model?.recordTrialsLeftWaiting()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
