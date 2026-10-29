import AppKit
import ResoluteKit

/// Resolute's presence on screen, and what the app model asks of it: the menu bar icon with
/// its panel and classic menu, the Resolute window, the Dock icon while a window is open,
/// and the decision to quit.
@MainActor
final class ShellController: AppShell {
    let model: AppModel
    let activation: ActivationPolicyController
    let navigation: WindowNavigation
    let statusItem: StatusItemController
    let window: MainWindowController

    /// Each display's editor (custom resolutions, picture and name), kept while the app runs
    /// so unsaved changes outlive the page, the window and an unplugged display.
    let editors: DisplayEditors
    /// Set while Quit Resolute (as opposed to ⌘Q) asks AppKit to quit.
    private var isQuittingExplicitly = false

    init(model: AppModel) {
        self.model = model
        let activation = ActivationPolicyController()
        let navigation = WindowNavigation(route: model.defaultRoute)
        let editors = DisplayEditors(model: model)
        self.activation = activation
        self.navigation = navigation
        self.editors = editors
        model.sharpScaling.isEditorWriting = { [weak editors] in editors?.isSaving == true }
        statusItem = StatusItemController(
            model: model,
            panel: PanelHost(content: ShellRoots.panel(model: model)),
            classicMenu: StatusMenuController(model: model)
        )
        window = MainWindowController(
            model: model,
            navigation: navigation,
            activation: activation,
            content: ShellRoots.window(model: model, navigation: navigation, editors: editors)
        )
        model.shell = self
    }

    // MARK: - AppShell

    func showWindow(_ route: AppRoute) {
        statusItem.closePanel()
        window.show(route: route)
    }

    func showPanel() {
        statusItem.openPanel()
    }

    func closePanel() {
        statusItem.closePanel()
    }

    func quit() {
        isQuittingExplicitly = true
        NSApp.terminate(nil)
        // Reached only when quitting was cancelled.
        isQuittingExplicitly = false
    }

    // MARK: - App events

    /// The app was opened again while running (Finder, the Dock, Spotlight): show the window
    /// on the page it was on.
    func reopen() {
        statusItem.closePanel()
        window.show()
    }

    /// Whether the Resolute window is open; minimized counts.
    var hasOpenWindow: Bool {
        window.isOpen
    }

    /// Answers `applicationShouldTerminate(_:)`: refuses during a switch or a write, closes
    /// the windows for ⌘Q while one is open, and otherwise asks about anything that quitting
    /// would lose before quitting.
    func terminationReply(appleEvent: NSAppleEventDescriptor?) -> NSApplication.TerminateReply {
        let state = TerminationPolicy.State(
            request: TerminationRequest(isExplicit: isQuittingExplicitly, appleEvent: appleEvent),
            hasOpenWindow: hasOpenWindow,
            isPanelKey: statusItem.panel.isOpen && statusItem.panel.panel.isKeyWindow,
            isChangingMode: model.modeChanges.isChangingMode,
            isWritingOverride: editors.isWorking,
            hasPendingRestores: !model.pendingRestores.isEmpty,
            unsavedOverrideName: editors.unsavedDisplayName
        )
        switch TerminationPolicy.decide(state) {
        case .refuse:
            NSSound.beep()
            return .terminateCancel
        case .closeWindows:
            window.performClose()
            return .terminateCancel
        case .quit(let questions):
            for question in questions {
                guard confirm(question) else { return .terminateCancel }
            }
            return .terminateNow
        }
    }

    // MARK: - Helpers

    /// Quit Anyway (true) or keep going (false).
    private func confirm(_ question: TerminationPolicy.Question) -> Bool {
        switch question {
        case .pendingRestores:
            return QuitWhileWaitingDialog.confirm(model: model)
        case .unsavedCustomResolutions(let displayName):
            let alert = NSAlert()
            alert.messageText = "Quit without saving your changes to \(displayName)?"
            alert.informativeText = "Your changes to its custom resolutions, picture or name will be lost."
            alert.addButton(withTitle: "Keep Editing")
            alert.addButton(withTitle: "Quit Anyway")
            NSApp.activate()
            return alert.runModal() == .alertSecondButtonReturn
        }
    }
}
