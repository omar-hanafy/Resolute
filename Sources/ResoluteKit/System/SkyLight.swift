import CoreGraphics
import Darwin

/// The private SkyLight display-mode functions, resolved at run time.
///
/// Every function is looked up with `dlsym`. If one is missing the bridge is not created
/// and Resolute uses the public CoreGraphics API alone.
public final class SkyLight: @unchecked Sendable {
    // Immutable after init, so sharing across threads is safe.
    private typealias ModeCountFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
    private typealias ModeDescriptionFunction = @convention(c) (CGDirectDisplayID, Int32, UnsafeMutableRawPointer, Int32) -> Void
    private typealias CurrentModeFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Int32>) -> Void
    private typealias ConfigureModeFunction = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Int32) -> Void

    private let modeCount: ModeCountFunction
    private let modeDescription: ModeDescriptionFunction
    private let currentMode: CurrentModeFunction
    private let configureMode: ConfigureModeFunction

    /// The bridge for this process, or nil when the private functions are unavailable.
    public static let shared: SkyLight? = SkyLight()

    private init?() {
        let everyImage = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        func load<Function>(_ name: String, as type: Function.Type) -> Function? {
            guard let symbol = dlsym(everyImage, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }
        guard
            let modeCount = load("CGSGetNumberOfDisplayModes", as: ModeCountFunction.self),
            let modeDescription = load("CGSGetDisplayModeDescriptionOfLength", as: ModeDescriptionFunction.self),
            let currentMode = load("CGSGetCurrentDisplayMode", as: CurrentModeFunction.self),
            let configureMode = load("CGSConfigureDisplayMode", as: ConfigureModeFunction.self)
        else { return nil }
        self.modeCount = modeCount
        self.modeDescription = modeDescription
        self.currentMode = currentMode
        self.configureMode = configureMode
    }

    /// Raw records for every mode of `display`, in list order.
    public func rawRecords(for display: CGDirectDisplayID) -> [[UInt8]] {
        var count: Int32 = 0
        modeCount(display, &count)
        guard count > 0, count < 10_000 else { return [] }
        return (0..<count).map { index in
            // Zeroed and larger than requested, in case the system writes past the length.
            var buffer = [UInt8](repeating: 0, count: 0x100)
            buffer.withUnsafeMutableBytes { bytes in
                modeDescription(display, index, bytes.baseAddress!, Int32(PrivateModeRecord.length))
            }
            return Array(buffer.prefix(PrivateModeRecord.length))
        }
    }

    /// Decoded records for every mode of `display`; nil where a record is unreadable.
    public func records(for display: CGDirectDisplayID) -> [PrivateModeRecord?] {
        rawRecords(for: display).map(PrivateModeRecord.init(bytes:))
    }

    /// Index of the current mode in the private list.
    public func currentModeIndex(for display: CGDirectDisplayID) -> Int32? {
        var index: Int32 = -1
        currentMode(display, &index)
        return index >= 0 ? index : nil
    }

    /// Adds "switch `display` to private mode `index`" to a configuration transaction.
    public func configure(_ config: CGDisplayConfigRef, display: CGDirectDisplayID, index: Int32) {
        configureMode(config, display, index)
    }
}
