import CoreGraphics

/// The `CGConfigureDisplayMirrorOfDisplay` calls that turn mirroring on or off.
public enum MirroringPlan {
    public struct Step: Equatable, Sendable {
        public var display: CGDirectDisplayID
        /// The display to mirror, or `kCGNullDirectDisplay` to stop mirroring.
        public var source: CGDirectDisplayID
    }

    public static func steps(online: [CGDirectDisplayID], main: CGDirectDisplayID, enable: Bool) -> [Step] {
        online
            .filter { $0 != main }
            .map { Step(display: $0, source: enable ? main : kCGNullDirectDisplay) }
    }
}
