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

    private func showCustomResolutions(selecting displayID: CGDirectDisplayID?) {
        if customResolutions == nil {
            customResolutions = CustomResolutionsWindowController(model: CustomResolutionsModel(service: service))
        }
        customResolutions?.show(selecting: displayID)
    }
}
