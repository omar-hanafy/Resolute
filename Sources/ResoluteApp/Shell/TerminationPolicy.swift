import AppKit

/// What asked Resolute to quit.
enum TerminationRequest: Equatable, Sendable {
    /// ⌘Q, which closes the window when one is open, as the window owns the shortcut there
    /// (Figma: First close, "⌘Q in the window only closes it").
    case commandQ
    /// Quit Resolute in the panel or a menu, or ⌃⌥⌘Q: quit even with the window open.
    case explicit
    /// A quit Apple event: logging out, restarting, the Dock's Quit, or a script.
    case system

    /// `explicit` when Resolute's own Quit asked; else a quit Apple event comes from
    /// outside, and anything else is ⌘Q.
    init(isExplicit: Bool, appleEvent: NSAppleEventDescriptor?) {
        if isExplicit {
            self = .explicit
        } else if let appleEvent, appleEvent.eventClass == AEEventClass(kCoreEventClass),
                  appleEvent.eventID == AEEventID(kAEQuitApplication) {
            self = .system
        } else {
            self = .commandQ
        }
    }
}

/// Decides what a request to quit does. Ending the process abandons a switch's countdown, a
/// revert waiting for its display, an override being written and unsaved custom
/// resolutions, so each of those refuses or asks first; ⌘Q with the window open only
/// closes it.
enum TerminationPolicy {
    struct State: Equatable {
        var request: TerminationRequest
        /// The Resolute window, or the Custom Resolutions editor, is open.
        var hasOpenWindow = false
        /// The panel has the keyboard: ⌘Q there quits, as the panel's Quit Resolute says.
        var isPanelKey = false
        /// A switch is under way; its Keep/Revert countdown may be up.
        var isChangingMode = false
        /// An override is being written, possibly behind the administrator prompt.
        var isWritingOverride = false
        var hasPendingRestores = false
        /// The display whose custom resolutions have unsaved changes.
        var unsavedOverrideName: String?
    }

    /// A question asked before quitting; Quit Anyway goes on to the next.
    enum Question: Equatable {
        case pendingRestores
        case unsavedCustomResolutions(displayName: String)
    }

    enum Decision: Equatable {
        /// Refuse with a beep: quitting now would cut a switch or a write short.
        case refuse
        /// Close the windows and keep running in the menu bar.
        case closeWindows
        /// Quit once each question, in order, is answered Quit Anyway; at once when there are none.
        case quit(asking: [Question])
    }

    static func decide(_ state: State) -> Decision {
        // ⌘Q also works while a modal countdown is up, and closing a window under it would
        // not help; the switch has to end first.
        if state.isChangingMode || state.isWritingOverride { return .refuse }
        if state.request == .commandQ, state.hasOpenWindow, !state.isPanelKey { return .closeWindows }
        var questions: [Question] = []
        if state.hasPendingRestores { questions.append(.pendingRestores) }
        if let name = state.unsavedOverrideName { questions.append(.unsavedCustomResolutions(displayName: name)) }
        return .quit(asking: questions)
    }
}
