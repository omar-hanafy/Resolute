import Foundation

/// The setup of the displays right now, as a preset remembers it. Capturing only reads the
/// snapshot it is given; it never switches anything.
public struct PresetCapture: Hashable, Sendable {
    /// A display the capture left out, and why.
    public struct LeftOut: Hashable, Sendable {
        public enum Reason: Hashable, Sendable {
            /// It uses a hidden mode, and presets switch only to modes macOS lists.
            case hiddenMode
            /// Its current mode is unknown.
            case unknownMode
        }

        public var displayName: String
        public var reason: Reason

        /// "DELL P2419H uses a hidden mode, which presets don’t switch to, so it was left out."
        public var message: String {
            switch reason {
            case .hiddenMode: "\(displayName) uses a hidden mode, which presets don’t switch to, so it was left out."
            case .unknownMode: "The current mode of \(displayName) is unknown, so it was left out."
            }
        }
    }

    /// The main display first, then the others in the snapshot's order.
    public var displays: [DisplaySetting]
    /// Whether the displays mirror each other; nil with a single display, which can't.
    public var mirroring: Bool?
    public var leftOut: [LeftOut]

    public init(displays: [Display]) {
        let ordered = displays.enumerated()
            .sorted { ($0.element.isMain ? 0 : 1, $0.offset) < ($1.element.isMain ? 0 : 1, $1.offset) }
            .map(\.element)
        var settings: [DisplaySetting] = []
        var leftOut: [LeftOut] = []
        for display in ordered {
            guard let mode = display.currentMode else {
                leftOut.append(LeftOut(displayName: display.name, reason: .unknownMode))
                continue
            }
            guard mode.origin == .system else {
                leftOut.append(LeftOut(displayName: display.name, reason: .hiddenMode))
                continue
            }
            settings.append(DisplaySetting(display: display, mode: mode))
        }
        self.displays = settings
        // Mirroring alone is no setup to come back to.
        mirroring = displays.count > 1 && !settings.isEmpty ? displays.contains(where: \.isInMirrorSet) : nil
        self.leftOut = leftOut
    }

    /// Whether nothing could be captured, so there is nothing to save.
    public var isEmpty: Bool {
        displays.isEmpty
    }
}
