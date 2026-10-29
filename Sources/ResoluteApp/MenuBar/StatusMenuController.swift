import AppKit
import ResoluteKit

/// The classic menu, which a right-click or Control-click on the menu bar icon opens for
/// keyboard and VoiceOver users. It is rebuilt each time it opens, so it is always current,
/// and its choices go to the app model like the panel's.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

    /// The menu for the current displays and settings.
    static func nodes(service: any DisplayControlling, preferences: Preferences, showsDetails: Bool) -> [MenuNode] {
        nodes(displays: service.displays(), preferences: preferences, showsDetails: showsDetails)
    }

    static func nodes(displays: [Display], preferences: Preferences, showsDetails: Bool) -> [MenuNode] {
        MenuModel.build(
            displays: displays,
            settings: MenuSettings(showLowResolutionModes: preferences.showLowResolutionModes, showsDetails: showsDetails)
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refresh()
        let nodes = Self.nodes(
            displays: model.displays,
            preferences: model.preferences,
            showsDetails: NSEvent.modifierFlags.contains(.option)
        )
        MenuRenderer.fill(menu, with: nodes, target: self, action: #selector(menuItemChosen(_:)))
    }

    @objc private func menuItemChosen(_ sender: NSMenuItem) {
        guard let action = (sender.representedObject as? MenuActionBox)?.action else { return }
        // Let the menu finish closing before the displays reconfigure.
        MainRunLoop.perform { [weak self] in self?.perform(action) }
    }

    func perform(_ action: MenuAction) {
        // About, login-item failures and the editor can open a nested modal session that
        // prevents the countdown from reverting on time. Mirroring also changes the
        // topology the trial must restore.
        guard !model.modeChanges.isChangingMode else { return }
        switch action {
        case .applyMode(let displayID, let modeID, let needsConfirmation):
            model.apply(modeID: modeID, to: displayID, needsConfirmation: needsConfirmation, from: .menu)
        case .setMirroring(let enabled):
            model.setMirroring(enabled, from: .menu)
        case .openCustomResolutions(let displayID):
            model.openCustomResolutions(for: displayID)
        case .openWindow:
            model.openWindow(model.defaultRoute)
        case .openSettings:
            model.openSettings()
        case .quit:
            model.quit()
        }
    }
}
