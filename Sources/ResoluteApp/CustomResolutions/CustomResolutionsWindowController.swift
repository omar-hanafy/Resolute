import AppKit
import ResoluteKit
import SwiftUI

/// Owns the Custom Resolutions window.
@MainActor
final class CustomResolutionsWindowController: NSWindowController {
    let model: CustomResolutionsModel

    init(model: CustomResolutionsModel) {
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
        window.setFrameAutosaveName("CustomResolutions")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the window, selecting `displayID` when one is given.
    func show(selecting displayID: CGDirectDisplayID?) {
        model.select(displayID: displayID)
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Refreshes the display list after displays are connected or removed.
    func displaysDidChange() {
        guard window?.isVisible == true else { return }
        model.reloadTargets()
    }
}
