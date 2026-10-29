import AppKit
import Observation
import ResoluteKit

/// Settings kept in the app's user defaults: Settings › General in the window (Figma 40:149),
/// and what onboarding has already shown. Each value is read from and written to the
/// defaults as it is used, and observed like a stored property, so views and the status
/// item follow a change made anywhere.
@MainActor
@Observable
final class Preferences {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Menu Bar

    /// Show the resolution next to the icon: "For example 1728 × 1117. The icon alone takes
    /// the least space." Off by default.
    var showsResolutionInMenuBar: Bool {
        get {
            access(keyPath: \.showsResolutionInMenuBar)
            return defaults.object(forKey: Key.showsResolutionInMenuBar) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.showsResolutionInMenuBar) {
                defaults.set(newValue, forKey: Key.showsResolutionInMenuBar)
            }
        }
    }

    /// Open the panel: "A keyboard shortcut that opens the panel from anywhere." ⌃⌥R unless
    /// the person changed it; nil once they cleared it.
    var panelShortcut: KeyShortcut? {
        get {
            access(keyPath: \.panelShortcut)
            guard let spec = defaults.object(forKey: Key.panelShortcut) as? String else { return .openPanel }
            if spec.isEmpty { return nil }
            return KeyShortcut(spec: spec) ?? .openPanel
        }
        set {
            withMutation(keyPath: \.panelShortcut) {
                defaults.set(newValue?.spec ?? "", forKey: Key.panelShortcut)
            }
        }
    }

    // MARK: Panel

    /// Show low-resolution (1×) modes: "Modes that draw one pixel per point." On by default.
    var showLowResolutionModes: Bool {
        get {
            access(keyPath: \.showLowResolutionModes)
            return defaults.object(forKey: Key.showLowResolutionModes) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showLowResolutionModes) {
                defaults.set(newValue, forKey: Key.showLowResolutionModes)
            }
        }
    }

    /// Show hidden modes: "Or hold ⌥ while clicking the menu bar icon to show them once." Off by default.
    var showHiddenModes: Bool {
        get {
            access(keyPath: \.showHiddenModes)
            return defaults.object(forKey: Key.showHiddenModes) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.showHiddenModes) {
                defaults.set(newValue, forKey: Key.showHiddenModes)
            }
        }
    }

    /// Hidden-mode trial: "How long a hidden mode runs before it switches back on its own."
    /// 15 seconds unless the person chose another length; a stored length that is not one
    /// of the choices reads as the default.
    var trialLength: TrialLength {
        get {
            access(keyPath: \.trialLength)
            return (defaults.object(forKey: Key.trialLength) as? Int).flatMap(TrialLength.init(rawValue:)) ?? .standard
        }
        set {
            withMutation(keyPath: \.trialLength) {
                defaults.set(newValue.rawValue, forKey: Key.trialLength)
            }
        }
    }

    // MARK: Command Line & Agents

    /// Hidden modes asked for from the command line: "The display shows Keep or Revert; if
    /// nobody answers, it switches back." Ask me unless the person chose otherwise; a stored
    /// value that is not one of the choices reads as Ask me.
    var commandLineHiddenModes: CommandLineHiddenModes {
        get {
            access(keyPath: \.commandLineHiddenModes)
            return (defaults.string(forKey: Key.commandLineHiddenModes)).flatMap(CommandLineHiddenModes.init(rawValue:)) ?? .ask
        }
        set {
            withMutation(keyPath: \.commandLineHiddenModes) {
                defaults.set(newValue.rawValue, forKey: Key.commandLineHiddenModes)
            }
        }
    }

    /// Show command-line changes in the panel: "The latest change appears in the panel with
    /// Undo." On by default.
    var showsCommandLineChangesInPanel: Bool {
        get {
            access(keyPath: \.showsCommandLineChangesInPanel)
            return defaults.object(forKey: Key.showsCommandLineChangesInPanel) as? Bool ?? true
        }
        set {
            withMutation(keyPath: \.showsCommandLineChangesInPanel) {
                defaults.set(newValue, forKey: Key.showsCommandLineChangesInPanel)
            }
        }
    }

    /// Notify me when an agent changes a display: "A notification with Undo, even when the
    /// panel is closed." Off by default.
    var notifiesAgentChanges: Bool {
        get {
            access(keyPath: \.notifiesAgentChanges)
            return defaults.object(forKey: Key.notifiesAgentChanges) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.notifiesAgentChanges) {
                defaults.set(newValue, forKey: Key.notifiesAgentChanges)
            }
        }
    }

    // MARK: Sharp Scaling

    /// Displays whose Sharp Scaling offer the person closed, by override key, so the panel
    /// doesn't offer it again for them.
    var dismissedSharpScalingOffers: Set<String> {
        get {
            access(keyPath: \.dismissedSharpScalingOffers)
            return Set(defaults.stringArray(forKey: Key.dismissedSharpScalingOffers) ?? [])
        }
        set {
            withMutation(keyPath: \.dismissedSharpScalingOffers) {
                defaults.set(newValue.sorted(), forKey: Key.dismissedSharpScalingOffers)
            }
        }
    }

    // MARK: Onboarding

    /// Whether Welcome has been shown, so only the first deliberate launch shows it.
    var hasShownWelcome: Bool {
        get {
            access(keyPath: \.hasShownWelcome)
            return defaults.object(forKey: Key.hasShownWelcome) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.hasShownWelcome) {
                defaults.set(newValue, forKey: Key.hasShownWelcome)
            }
        }
    }

    /// Whether "Resolute is still running" has pointed at the menu bar icon after the window
    /// closed; it is shown once.
    var hasShownFirstCloseNotice: Bool {
        get {
            access(keyPath: \.hasShownFirstCloseNotice)
            return defaults.object(forKey: Key.hasShownFirstCloseNotice) as? Bool ?? false
        }
        set {
            withMutation(keyPath: \.hasShownFirstCloseNotice) {
                defaults.set(newValue, forKey: Key.hasShownFirstCloseNotice)
            }
        }
    }

    private enum Key {
        static let showsResolutionInMenuBar = "ShowResolutionInMenuBar"
        static let panelShortcut = "PanelShortcut"
        static let showLowResolutionModes = "ShowLowResolutionModes"
        static let showHiddenModes = "ShowHiddenModes"
        static let trialLength = "HiddenModeTrialSeconds"
        static let hasShownWelcome = "HasShownWelcome"
        static let hasShownFirstCloseNotice = "HasShownFirstCloseNotice"
        static let dismissedSharpScalingOffers = "DismissedSharpScalingOffers"
        static let commandLineHiddenModes = "CommandLineHiddenModes"
        static let showsCommandLineChangesInPanel = "ShowCommandLineChangesInPanel"
        static let notifiesAgentChanges = "NotifyWhenAgentChangesDisplay"
    }
}

/// How long a hidden mode runs before it switches back on its own: the choices of Settings ›
/// General › Hidden-mode trial. Figma shows only the default, 15 seconds, which matches
/// how long System Settings waits; the longer choices give more time to judge a mode, and
/// none is shorter, because a display can take seconds to show a new mode at all.
enum TrialLength: Int, CaseIterable, Identifiable, Sendable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60

    static let standard = TrialLength.fifteenSeconds

    var id: Int { rawValue }

    var duration: TimeInterval { TimeInterval(rawValue) }

    /// "15 seconds", as the pop-up lists it.
    var title: String {
        switch self {
        case .fifteenSeconds: "15 seconds"
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        }
    }
}

/// What happens when `resolute` asks for a hidden mode: the choices of Settings › Command
/// Line & Agents › Hidden modes asked for from the command line. Figma shows only the
/// default, Ask me; Don't Allow is for a Mac where nobody watches the screen, so an agent
/// can never leave a display on a mode it can't show.
enum CommandLineHiddenModes: String, CaseIterable, Identifiable, Sendable {
    /// The display shows Keep or Revert; if nobody answers, it switches back.
    case ask
    /// The request is refused before anything changes.
    case refuse

    var id: String { rawValue }

    /// "Ask me", as the pop-up lists it.
    var title: String {
        switch self {
        case .ask: "Ask me"
        case .refuse: "Don’t allow"
        }
    }

    /// What the choice does, under the pop-up.
    var help: String {
        switch self {
        case .ask: "The display shows Keep or Revert; if nobody answers, it switches back."
        case .refuse: "The command is turned away before it changes anything."
        }
    }
}
