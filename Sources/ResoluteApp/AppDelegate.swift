import AppKit
import ResoluteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = SystemDisplayService()
    private let preferences = Preferences()
    private let loginItem = LoginItemController()
    private var statusMenu: StatusMenuController?
    private var customResolutions: CustomResolutionsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Never shown for an agent app, but it gives text fields and windows their shortcuts.
        NSApp.mainMenu = MainMenu.make()
        statusMenu = StatusMenuController(
            service: service,
            preferences: preferences,
            loginItem: loginItem,
            modeChanges: ModeChangeCoordinator(service: service)
        ) { [weak self] displayID in
            self?.showCustomResolutions(selecting: displayID)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.customResolutions?.displaysDidChange()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = customResolutions?.model, model.hasChanges else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit without saving your custom resolutions?"
        alert.informativeText = "Your changes to \(model.selectedTarget?.name ?? "the display") have not been saved."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Quit Anyway")
        NSApp.activate()
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    private func showCustomResolutions(selecting displayID: CGDirectDisplayID?) {
        if customResolutions == nil {
            customResolutions = CustomResolutionsWindowController(model: CustomResolutionsModel(service: service))
        }
        customResolutions?.show(selecting: displayID)
    }
}
