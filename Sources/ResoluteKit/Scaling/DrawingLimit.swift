import Foundation
import IOKit

/// The largest image this Mac can draw for an external display. A sharp size is drawn at
/// twice its size, so it fits only when that drawing does.
///
/// Where the numbers come from: on Apple silicon each external display is driven by a
/// display pipe, whose framebuffer (an `IOMobileFramebufferShim` marked `external` in the
/// IORegistry) publishes `IOMFBMaxSrcPixels`. Its `MaxSrcRectWidthForPipe` and
/// `MaxSrcRectHeightForPipe` list, for each pipe, the largest source image the pipe takes
/// and scales to the panel, and a HiDPI mode's drawing is that source: 7680 × 4320 on an
/// M2 Pro. The same framebuffers' `IOMFBScalingLimits` let a pipe shrink an image to half
/// its size at most (`RGBLayer_MinScaleFraction` 2), which is why sharp sizes stop at the
/// panel's own size.
///
/// How sure this is: Apple documents none of these keys, and a release could rename them.
/// One pipe's limit is used, since whether a display can spread a wider drawing over two
/// pipes, as tiled 6K and 8K displays do, isn't known. Two other numbers are deliberately
/// not used: `MaxPixelWidth` on the DisplayPort transmitters (6144 on an M2 Pro) limits the
/// signal sent to the display rather than the image drawn for it, and the widest mode a
/// display lists says what macOS offers, not what it could draw. A Mac that publishes no
/// limit (an Intel Mac, a virtual machine) has an unknown one: every size is planned, and
/// the check after the reconnect names any size macOS skipped.
public struct DrawingLimit: Hashable, Sendable {
    /// The widest drawing, in pixels; nil when unknown.
    public var width: Int?
    /// The tallest drawing, in pixels; nil when unknown.
    public var height: Int?

    public init(width: Int?, height: Int? = nil) {
        self.width = width
        self.height = height
    }

    public static let unknown = DrawingLimit(width: nil, height: nil)

    public var isKnown: Bool { width != nil || height != nil }

    /// Whether `size`, drawn at twice its size, fits.
    public func allows(_ size: SharpSize) -> Bool {
        (width.map { size.drawnWidth <= $0 } ?? true) && (height.map { size.drawnHeight <= $0 } ?? true)
    }

    /// Whether `size` is too wide; when it fits the width but not the limit, it is too tall.
    public func isTooWide(_ size: SharpSize) -> Bool {
        width.map { size.drawnWidth > $0 } ?? false
    }

    /// The limit this Mac publishes for its external displays, or `unknown`. Read-only.
    public static func current() -> DrawingLimit {
        limit(from: framebuffers())
    }

    /// What one framebuffer publishes: whether it drives external displays, and its
    /// `IOMFBMaxSrcPixels`.
    struct Framebuffer {
        var isExternal: Bool
        var maxSourcePixels: [String: Any]?
    }

    /// The external framebuffers' limit, each at its largest pipe. The framebuffer that will
    /// drive a given display isn't known, so the smallest of them counts; on the Macs seen so
    /// far they are all the same.
    static func limit(from framebuffers: [Framebuffer]) -> DrawingLimit {
        let limits = framebuffers.filter(\.isExternal).compactMap { framebuffer -> (width: Int, height: Int?)? in
            guard let pixels = framebuffer.maxSourcePixels, let width = largest(pixels["MaxSrcRectWidthForPipe"]) else {
                return nil
            }
            return (width, largest(pixels["MaxSrcRectHeightForPipe"]))
        }
        guard let width = limits.map(\.width).min() else { return .unknown }
        return DrawingLimit(width: width, height: limits.compactMap(\.height).min())
    }

    /// The largest positive number in a per-pipe list; a pipe a framebuffer lacks is 0.
    private static func largest(_ value: Any?) -> Int? {
        let numbers = (value as? [NSNumber])?.map(\.intValue) ?? (value as? [Int]) ?? []
        return numbers.filter { $0 > 0 }.max()
    }

    private static func framebuffers() -> [Framebuffer] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"), &iterator)
            == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var framebuffers: [Framebuffer] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            framebuffers.append(Framebuffer(
                isExternal: property("external", of: service) as? Bool ?? false,
                maxSourcePixels: property("IOMFBMaxSrcPixels", of: service) as? [String: Any]
            ))
        }
        return framebuffers
    }

    private static func property(_ name: String, of service: io_service_t) -> Any? {
        IORegistryEntryCreateCFProperty(service, name as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
