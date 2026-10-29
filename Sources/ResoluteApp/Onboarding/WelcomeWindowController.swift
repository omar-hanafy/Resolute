import AppKit
import ResoluteDesign
import SwiftUI

/// When Welcome shows: once, on the first launch a person makes. A launch at login stays
/// quiet in the menu bar, and leaves Welcome for the first time they open Resolute.
enum WelcomeRule {
    static func shouldShow(launchKind: LaunchKind, hasShownWelcome: Bool) -> Bool {
        launchKind == .deliberate && !hasShownWelcome
    }

    @MainActor
    static func shouldShow(_ model: AppModel) -> Bool {
        shouldShow(launchKind: model.launchKind, hasShownWelcome: model.preferences.hasShownWelcome)
    }
}

/// The Welcome window (Figma 40:5): a window of its own, 680 points wide, with the window
/// controls and no title, in front of the Resolute window on the first deliberate launch.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    /// Told after the window closes, so the lead's shell can take Resolute out of the Dock
    /// again when no other window is open.
    var onClose: (() -> Void)?

    private let model: AppModel

    init(model: AppModel, commandLine: CommandLineToolModel? = nil) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: Metrics.Welcome.width, height: 600)),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Welcome to Resolute"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        super.init(window: window)
        let hosting = NSHostingController(rootView: WelcomeView(
            model: model,
            commandLine: commandLine ?? CommandLineToolModel(showError: model.showError),
            onGetStarted: { [weak self] in self?.window?.performClose(nil) }
        ))
        // The window is as tall as Welcome; nothing in it is resizable.
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting
        window.center()
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows Welcome in front and remembers that it was shown, so it shows only once.
    func show() {
        model.preferences.hasShownWelcome = true
        guard let window else { return }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
