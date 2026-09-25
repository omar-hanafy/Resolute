import os

/// Where Resolute logs, so a mode change can be traced after the fact:
/// `log show --predicate 'subsystem == "com.omarhanafy.Resolute"' --info --last 1h`.
public enum ResoluteLog {
    public static let subsystem = "com.omarhanafy.Resolute"
    /// Mode switches, trials, reverts and restores that wait for a display.
    public static let modes = Logger(subsystem: subsystem, category: "modes")
}
