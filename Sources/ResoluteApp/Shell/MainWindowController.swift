import AppKit
import Observation
import ResoluteDesign
import SwiftUI

/// The page the Resolute window shows. `MainWindowController.show(route:)` sets it, and the
/// window's own navigation (its sidebar) does too; the root view reads it.
@MainActor
@Observable
final class WindowNavigation {
    var route: AppRoute

    init(route: AppRoute) {
        self.route = route
    }
}

/// The Resolute window: 1040 × 720 at first, never smaller than 820 × 560, its frame kept
/// between launches, the page's title and subtitle in the toolbar area (Figma: Window, page
/// 8:8). It hosts a SwiftUI root, the window owner's `NavigationSplitView`, whose toolbar
/// items SwiftUI puts in the window's toolbar.
///
/// While it is open Resolute is in the Dock and ⌘Tab; closing it puts Resolute back in the
/// menu bar alone.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    let navigation: WindowNavigation
    /// Told after the window closes. The first time, onboarding points at the menu bar icon
    /// ("Resolute is still running").
    var onClose: (() -> Void)?

    private let model: AppModel
    private let activation: ActivationPolicyController
    private var titles: ObservationLoop?

    /// `frameAutosaveName` keeps the window's frame in the user defaults between launches;
    /// nil leaves them alone, as tests and the gallery must.
    init<Content: View>(
        model: AppModel,
        navigation: WindowNavigation,
        activation: ActivationPolicyController,
        frameAutosaveName: String? = "ResoluteWindow",
        content: Content
    ) {
        self.model = model
        self.navigation = navigation
        self.activation = activation
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Metrics.Window.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Resolute"
        window.isReleasedWhenClosed = false
        // A launch at login stays quiet: macOS must not reopen the window it was in.
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .unified
        window.toolbar = NSToolbar(identifier: "ResoluteWindow")
        window.collectionBehavior.insert(.fullScreenPrimary)
        let hosting = NSHostingController(rootView: AnyView(content))
        // The window's size is the person's, down to the design's minimum, which the content
        // must fit. SwiftUI would size the window to the content instead.
        hosting.sizingOptions = []
        hosting.sceneBridgingOptions = [.toolbars]
        window.contentViewController = hosting
        let minimum = Metrics.Window.minimumSize
        NSLayoutConstraint.activate([
            hosting.view.widthAnchor.constraint(greaterThanOrEqualToConstant: minimum.width),
            hosting.view.heightAnchor.constraint(greaterThanOrEqualToConstant: minimum.height),
        ])
        window.setContentSize(Metrics.Window.defaultSize)
        window.center()
        if let frameAutosaveName {
            window.setFrameAutosaveName(frameAutosaveName)
        }
        super.init(window: window)
        window.delegate = self
        titles = ObservationLoop { [weak self] in self?.updateTitle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Whether the window is open, minimized included.
    var isOpen: Bool {
        guard let window else { return false }
        return window.isVisible || window.isMiniaturized
    }

    /// Goes to `route` without showing the window.
    func navigate(to route: AppRoute) {
        if navigation.route != route { navigation.route = route }
    }

    /// Shows the window in front, on `route` when one is given, with the Dock icon and ⌘Tab.
    func show(route: AppRoute? = nil) {
        if let route { navigate(to: route) }
        model.refresh()
        guard let window else { return }
        activation.windowWillOpen(window)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    /// Asks the window to close, as its close button does, so a page can ask first.
    func performClose() {
        window?.performClose(nil)
    }

    private func updateTitle() {
        let title = model.windowTitle(for: navigation.route)
        if window?.title != title.title { window?.title = title.title }
        if window?.subtitle != title.subtitle { window?.subtitle = title.subtitle }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        if let window { activation.windowDidClose(window) }
        onClose?()
    }
}
