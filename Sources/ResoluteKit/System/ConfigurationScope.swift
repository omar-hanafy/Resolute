import CoreGraphics

/// How long a display configuration change lasts.
public enum ConfigurationScope: String, Sendable, CaseIterable, Codable {
    /// Saved in the display preferences, like a change made in System Settings.
    case permanent
    /// Until the user logs out.
    case session
    /// Until this process exits.
    case app

    var option: CGConfigureOption {
        switch self {
        case .permanent: .permanently
        case .session: .forSession
        case .app: .forAppOnly
        }
    }
}
