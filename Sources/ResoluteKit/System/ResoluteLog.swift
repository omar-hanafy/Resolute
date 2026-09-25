import os

/// Where Resolute logs, so a mode change or an override edit can be traced after the fact:
/// `log show --predicate 'subsystem == "com.omarhanafy.Resolute"' --info --last 1h`.
public enum ResoluteLog {
    public static let subsystem = "com.omarhanafy.Resolute"
    /// Mode switches, trials, reverts and restores that wait for a display.
    public static let modes = Logger(subsystem: subsystem, category: "modes")
    /// Override files written and removed, and backups deleted, by the app or `resolute`.
    public static let overrides = Logger(subsystem: subsystem, category: "overrides")
}
