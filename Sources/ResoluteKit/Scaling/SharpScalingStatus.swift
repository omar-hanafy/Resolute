import Darwin
import Foundation

/// Where Sharp Scaling stands for a display: what it saved, and what macOS offers now.
public struct SharpScalingStatus: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        /// Nothing is saved.
        case off
        /// Saved, and waiting: macOS reads the override file when the display connects, so
        /// the sizes appear after a reconnect or a restart.
        case waiting
        /// macOS offers every saved size.
        case ready
        /// The display has read the file since, and macOS left out `skipped`.
        case partial
    }

    public var state: State
    /// The record in the override, when there is one.
    public var record: SharpScalingRecord?
    /// The saved sizes that the override file still lists, Larger Text first.
    public var saved: [SharpSize]
    /// The saved sizes macOS offers now.
    public var available: [SharpSize]
    /// While `waiting`, the saved sizes macOS doesn't offer yet; empty otherwise.
    public var pending: [SharpSize]
    /// Once `partial`, the saved sizes macOS left out after reading the file; empty otherwise.
    public var skipped: [SharpSize]
    /// The mode the display uses now.
    public var current: DisplayMode?
    /// The sharp mode at the current mode's size, at its refresh rate when macOS offers that:
    /// what moving to the sharp version picks. The current mode when it is sharp already;
    /// nil when macOS offers none.
    public var sharpVersionOfCurrent: DisplayMode?

    /// - Parameters:
    ///   - installed: the display's installed override, or nil when it has none.
    ///   - reconnectedSinceSave: true when the caller saw the display connect after the
    ///     sizes were saved, as the app does; the command line can't.
    ///   - systemStart: when the Mac started (`systemStart()`); a start after the save means
    ///     every display has read the file since.
    public init(display: Display, installed: DisplayOverride?, reconnectedSinceSave: Bool = false, systemStart: Date? = nil) throws {
        current = display.currentMode
        sharpVersionOfCurrent = display.currentMode.flatMap { Self.sharpVersion(of: $0, on: display) }
        guard let installed, let record = try SharpScalingRecord(in: installed) else {
            state = .off
            record = nil
            saved = []
            available = []
            pending = []
            skipped = []
            return
        }
        let saved = record.sizes.filter { size in installed.resolutions.contains { $0.sameMode(as: size.entry) } }
        let available = saved.filter { Self.isOffered($0, on: display) }
        let missing = saved.filter { !available.contains($0) }
        // A sharp size that appeared after the save proves that the display read the file
        // since; without one, a missing size may only be waiting for it.
        let hasReadSince = reconnectedSinceSave
            || systemStart.map { $0 > record.saved } == true
            || available.contains { !record.offered.contains($0) }
        self.record = record
        self.saved = saved
        self.available = available
        pending = hasReadSince ? [] : missing
        skipped = hasReadSince ? missing : []
        state = saved.isEmpty ? .off : missing.isEmpty ? .ready : hasReadSince ? .partial : .waiting
    }

    public var isCurrentHiDPI: Bool { current?.isHiDPI ?? false }

    /// Whether macOS lists `size`, drawn at twice its size, for `display`. Only listed modes
    /// count: one macOS keeps hidden is not on offer.
    public static func isOffered(_ size: SharpSize, on display: Display) -> Bool {
        display.modes.contains { $0.origin == .system && size.isDrawn(by: $0) }
    }

    /// The sharp version of `mode`: `mode` itself when it is HiDPI, else the sharp mode at its
    /// size, keeping its refresh rate when offered.
    public static func sharpVersion(of mode: DisplayMode, on display: Display) -> DisplayMode? {
        mode.isHiDPI ? mode : sharpMode(for: SharpSize(mode), on: display, keeping: mode)
    }

    /// The listed mode that shows `size` sharp, at `current`'s refresh rate and bit depth when
    /// macOS offers them, else the fastest; nil when macOS doesn't offer `size`.
    public static func sharpMode(for size: SharpSize, on display: Display, keeping current: DisplayMode?) -> DisplayMode? {
        let modes = display.modes.filter { $0.origin == .system && size.isDrawn(by: $0) }
        guard let group = ModeCatalog.groups(modes).first else { return nil }
        return ModeCatalog.preferredMode(in: group, current: current)
    }

    /// When this Mac started, from `kern.boottime`; nil when it can't be read.
    public static func systemStart() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
    }
}
