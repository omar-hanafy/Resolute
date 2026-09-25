import AppKit
import ResoluteKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = SystemDisplayService()
    private let preferences = Preferences()
    private let loginItem = LoginItemController()
    private var statusMenu: StatusMenuController?
    private var modeChanges: ModeChangeCoordinator?
    private var customResolutions: CustomResolutionsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Never shown for an agent app, but it gives text fields and windows their shortcuts.
        NSApp.mainMenu = MainMenu.make()
        let modeChanges = ModeChangeCoordinator(service: service)
        self.modeChanges = modeChanges
        statusMenu = StatusMenuController(
            service: service,
            preferences: preferences,
            loginItem: loginItem,
            modeChanges: modeChanges
        ) { [weak self] displayID in
            self?.showCustomResolutions(selecting: displayID)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A display that reconnects may have a revert waiting for it.
                self?.modeChanges?.displaysDidChange()
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
