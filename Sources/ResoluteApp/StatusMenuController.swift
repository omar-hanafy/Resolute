import AppKit
import ResoluteKit

/// The status-bar item. Its menu is rebuilt each time it opens, so it is always current.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let service: any DisplayControlling
    private let preferences: Preferences
    private let loginItem: LoginItemController
    private let modeChanges: ModeChangeCoordinator
    private let openCustomResolutions: (CGDirectDisplayID?) -> Void

    init(
        service: any DisplayControlling,
        preferences: Preferences,
        loginItem: LoginItemController,
        modeChanges: ModeChangeCoordinator,
        openCustomResolutions: @escaping (CGDirectDisplayID?) -> Void
    ) {
        self.service = service
        self.preferences = preferences
        self.loginItem = loginItem
        self.modeChanges = modeChanges
        self.openCustomResolutions = openCustomResolutions
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "Resolute")
            button.image?.isTemplate = true
            button.toolTip = "Resolute"
        }
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    /// The menu for the current displays and settings.
    static func nodes(
        service: any DisplayControlling,
        preferences: Preferences,
        loginItem: any LoginItemControlling,
        showsDetails: Bool
    ) -> [MenuNode] {
        MenuModel.build(
            displays: service.displays(),
            settings: MenuSettings(
                showLowResolutionModes: preferences.showLowResolutionModes,
                launchAtLogin: loginItem.state,
                showsDetails: showsDetails
            )
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let nodes = Self.nodes(
            service: service, preferences: preferences, loginItem: loginItem,
            showsDetails: NSEvent.modifierFlags.contains(.option)
        )
        MenuRenderer.fill(menu, with: nodes, target: self, action: #selector(menuItemChosen(_:)))
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? MenuActionBox)?.action else { return }
        // Let the menu finish closing before the displays reconfigure.
        Task { self.perform(action) }
    }

    private func perform(_ action: MenuAction) {
        // About, login-item failures and editor dialogs can open a nested modal session
        // that prevents the countdown from reverting on time. Mirroring also changes
        // the topology the trial must restore.
        guard !modeChanges.isChangingMode else { return }
        switch action {
        case .applyMode(let displayID, let modeID, let needsConfirmation):
            modeChanges.apply(modeID: modeID, to: displayID, needsConfirmation: needsConfirmation)
        case .setMirroring(let enabled):
            do {
                try service.setMirroring(enabled)
            } catch {
                Alerts.show(error, title: "Mirroring could not be changed")
            }
        case .openCustomResolutions(let displayID):
            openCustomResolutions(displayID)
        case .toggleLowResolutionModes:
            preferences.showLowResolutionModes.toggle()
        case .toggleLaunchAtLogin:
            loginItem.toggle()
        case .showAbout:
            AboutPanel.show()
        case .quit:
            NSApp.terminate(nil)
        }
    }
}
