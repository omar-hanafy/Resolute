import CoreGraphics

/// Whether hidden modes from the private SkyLight API can be used for a display.
public enum PrivateModeStatus: Hashable, Sendable, Codable {
    /// The private functions are not available on this system.
    case unavailable
    /// The private records disagree with CoreGraphics, so they are ignored.
    case untrusted(reason: String)
    /// The private records agree with CoreGraphics; hidden modes are listed.
    case trusted
}

/// A snapshot of one online display.
public struct Display: Hashable, Sendable, Codable, Identifiable {
    public var id: CGDirectDisplayID
    public var name: String
    public var vendorID: UInt32
    public var productID: UInt32
    public var serialNumber: UInt32
    public var isBuiltin: Bool
    public var isMain: Bool
    /// The display this one mirrors, when it is a mirror.
    public var mirrorSourceID: CGDirectDisplayID?
    public var isInMirrorSet: Bool
    public var currentModeID: Int32?
    public var modes: [DisplayMode]
    public var privateModes: PrivateModeStatus

    public init(
        id: CGDirectDisplayID,
        name: String,
        vendorID: UInt32 = 0,
        productID: UInt32 = 0,
        serialNumber: UInt32 = 0,
        isBuiltin: Bool = false,
        isMain: Bool = false,
        mirrorSourceID: CGDirectDisplayID? = nil,
        isInMirrorSet: Bool = false,
        currentModeID: Int32?,
        modes: [DisplayMode],
        privateModes: PrivateModeStatus = .unavailable
    ) {
        self.id = id
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.mirrorSourceID = mirrorSourceID
        self.isInMirrorSet = isInMirrorSet
        self.currentModeID = currentModeID
        self.modes = modes
        self.privateModes = privateModes
    }

    /// The mode the display is using, when it is in `modes`.
    public var currentMode: DisplayMode? {
        guard let currentModeID else { return nil }
        return modes.first { $0.modeID == currentModeID }
    }

    /// How many modes only the private API lists.
    public var hiddenModeCount: Int {
        modes.filter { $0.origin == .hidden }.count
    }
}
