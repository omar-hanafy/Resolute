import AppKit
import SwiftUI

/// A borderless, transparent window for a view that draws its own glass: the Keep/Revert
/// dialog, the quit confirmation and the notices. It floats above other windows (the panel
/// under the menu bar icon included) on every Space, over full-screen apps too.
@MainActor
final class GlassAlertPanel: NSPanel {
    /// A key pressed in the window; returns true when it answered the key.
    var onKey: ((NSEvent) -> Bool)?
    private let takesKeyboard: Bool

    /// `takesKeyboard` is false for a notice, which never takes clicks or keys.
    init(content: some View, title: String, takesKeyboard: Bool = true) {
        self.takesKeyboard = takesKeyboard
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        self.title = title
        // Above the menu bar panel, which a trial can start from.
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = takesKeyboard
        hidesOnDeactivate = false
        canHide = false
        isReleasedWhenClosed = false
        isMovable = false
        becomesKeyOnlyIfNeeded = false
        ignoresMouseEvents = !takesKeyboard
        animationBehavior = takesKeyboard ? .alertPanel : .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        setAccessibilitySubrole(takesKeyboard ? .dialog : .floatingWindow)
        let host = NSHostingView(rootView: content)
        host.sizingOptions = [.intrinsicContentSize]
        contentView = host
        setContentSize(host.fittingSize)
    }

    override var canBecomeKey: Bool { takesKeyboard }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }

    /// Esc that reached the window some other way, such as ⌘. or VoiceOver.
    override func cancelOperation(_ sender: Any?) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: windowNumber, context: nil,
            characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53
        ) else { return }
        _ = onKey?(event)
    }

    /// Centers the window on the screen of `displayID`, or on the main screen when that
    /// display has none.
    func center(onDisplay displayID: CGDirectDisplayID?) {
        guard let screen = TrialPlacement.screen(for: displayID) else { return }
        setFrameOrigin(TrialPlacement.origin(centering: frame.size, in: screen.frame, within: screen.visibleFrame))
    }

    /// Ends the modal session the window runs in. A session is only checked for its end
    /// between events, so an event is posted for a timer's call to take effect at once.
    static func stopModal() {
        NSApp.stopModal()
        if let wake = NSEvent.otherEvent(
            with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            subtype: 0, data1: 0, data2: 0
        ) {
            NSApp.postEvent(wake, atStart: false)
        }
    }
}

/// Where the dialog and notices go: on the display a trial is about, centered as the design
/// places them.
enum TrialPlacement {
    @MainActor
    static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        let screens = NSScreen.screens
        let ids = screens.map(\.shownDisplayID)
        let index = displayID.flatMap { index(of: $0, in: ids, mirroring: { CGDisplayMirrorsDisplay($0) }) }
        return index.map { screens[$0] } ?? NSScreen.main ?? screens.first
    }

    /// The screen that shows `displayID`: its own, or, for a display in a mirror set, the
    /// screen of the display it mirrors (only that one has a screen). Nil when none does.
    static func index(
        of displayID: CGDirectDisplayID, in screenIDs: [CGDirectDisplayID?],
        mirroring: (CGDirectDisplayID) -> CGDirectDisplayID
    ) -> Int? {
        if let index = screenIDs.firstIndex(of: displayID) { return index }
        let mirrored = mirroring(displayID)
        guard mirrored != kCGNullDirectDisplay, mirrored != displayID else { return nil }
        return screenIDs.firstIndex(of: mirrored)
    }

    /// The origin that centers `size` on `frame`, moved inside `visible` (clear of the menu
    /// bar and the Dock) when it would overlap them.
    static func origin(centering size: CGSize, in frame: CGRect, within visible: CGRect) -> CGPoint {
        var origin = CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
    }
}

private extension NSScreen {
    /// The CoreGraphics display the screen shows.
    var shownDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
