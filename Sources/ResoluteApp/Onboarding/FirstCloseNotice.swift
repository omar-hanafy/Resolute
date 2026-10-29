import AppKit
import ResoluteDesign
import SwiftUI

/// "Resolute is still running", in a popover from the menu bar icon the first time the
/// window closes (Figma: Menu bar panel › first close 25:2477): closing the window doesn't
/// quit Resolute, and this is where it went. It shows once.
@MainActor
enum FirstCloseNotice {
    /// The notice on screen and its delegate, kept until it closes.
    private static var current: NSPopover?
    private static var closer: PopoverCloser?

    /// Whether the notice is still to show.
    static func isDue(_ preferences: Preferences) -> Bool {
        !preferences.hasShownFirstCloseNotice
    }

    /// Shows the notice under `button` unless it has been shown before, and remembers that it
    /// has. Returns whether it showed. The button must be in the menu bar, on screen.
    @discardableResult
    static func showIfDue(from button: NSStatusBarButton?, model: AppModel) -> Bool {
        guard isDue(model.preferences), current == nil,
              let button, button.window != nil
        else { return false }
        model.preferences.hasShownFirstCloseNotice = true
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let delegate = PopoverCloser()
        popover.delegate = delegate
        popover.contentViewController = NSHostingController(rootView: FirstCloseNoticeView { [weak popover] in
            popover?.performClose(nil)
        })
        current = popover
        closer = delegate
        delegate.onClose = {
            current = nil
            closer = nil
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        return true
    }
}

/// Clears the notice once its popover closes.
@MainActor
private final class PopoverCloser: NSObject, NSPopoverDelegate {
    var onClose: (() -> Void)?

    func popoverDidClose(_ notification: Notification) {
        onClose?()
    }
}

/// The notice's content: what happened and how to quit, with Got It.
struct FirstCloseNoticeView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.FirstCloseNotice.spacing) {
            Text("Resolute is still running")
                .textStyle(.bodyEmphasized)
                .foregroundStyle(Palette.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Click this icon to switch resolutions. To quit, choose Quit Resolute here or press ⌃⌥⌘Q.")
                .textStyle(.subheadline)
                .foregroundStyle(Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Click this icon to switch resolutions. To quit, choose Quit Resolute here or press Control-Option-Command-Q.")
            HStack {
                Spacer(minLength: 0)
                Button("Got It", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: Metrics.FirstCloseNotice.width)
        .padding(Metrics.FirstCloseNotice.insets)
    }
}

extension Metrics {
    /// The first-close notice (Figma 25:2477).
    enum FirstCloseNotice {
        /// The text's width in Figma's 300-point popover.
        static let width: CGFloat = 262
        static let spacing: CGFloat = 6
        static let insets = EdgeInsets(top: 26, leading: 18, bottom: 18, trailing: 18)
    }
}
