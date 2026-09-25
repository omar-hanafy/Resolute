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
        // Command-Q remains available even while a modal confirmation is running.
        // Ending the process here would abandon the session mode or an in-flight write.
        guard modeChanges?.isChangingMode != true, customResolutions?.model.isWorking != true else {
            NSSound.beep()
            return .terminateCancel
        }
        if modeChanges?.pendingRestores.isEmpty == false {
            let alert = NSAlert()
            alert.messageText = "Quit before the display mode is restored?"
            alert.informativeText = "Resolute is waiting to restore a display's previous mode. Quitting stops recovery; the trial mode may remain until you log out."
            alert.addButton(withTitle: "Keep Waiting")
            alert.addButton(withTitle: "Quit Anyway")
            NSApp.activate()
            guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        }
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
