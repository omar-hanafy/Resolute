import AppKit
import ResoluteKit
import SwiftUI

/// Owns the Custom Resolutions window.
@MainActor
final class CustomResolutionsWindowController: NSWindowController, NSWindowDelegate {
    let model: CustomResolutionsModel

    /// `frameAutosaveName` keeps the window's frame in the user defaults between launches;
    /// nil leaves them alone, as tests must.
    init(model: CustomResolutionsModel, frameAutosaveName: String? = "CustomResolutions") {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "Custom Resolutions"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: CustomResolutionsView(model: model))
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        if let frameAutosaveName {
            window.setFrameAutosaveName(frameAutosaveName)
        }
        super.init(window: window)
        window.delegate = self
        // Another app or `resolute` may change overrides while Resolute is in the background.
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the window, selecting `displayID` when one is given, with what is on disk now.
    func show(selecting displayID: CGDirectDisplayID?) {
        model.select(displayID: displayID)
        model.refresh()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Refreshes the display list after displays are connected or removed.
    func displaysDidChange() {
        guard window?.isVisible == true else { return }
        model.reloadTargets()
    }

    /// Also after a sheet or an alert on the window closes.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    @objc private func applicationDidBecomeActive(_ notification: Notification) {
        guard window?.isVisible == true else { return }
        model.refresh()
    }
}
