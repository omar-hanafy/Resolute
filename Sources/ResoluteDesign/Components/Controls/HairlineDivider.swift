import SwiftUI

/// A one-point `stroke/hairline` line between rows of a group, above the panel's actions,
/// and between a card's sections (Figma's separators and "1 px dividers"). Named apart
/// from SwiftUI's `Divider`, which draws the system separator instead.
public struct HairlineDivider: View {
    public var axis: Axis

    /// - Parameter axis: `.horizontal` for a line across, `.vertical` for one down.
    public init(_ axis: Axis = .horizontal) {
        self.axis = axis
    }

    public var body: some View {
        Rectangle()
            .fill(Palette.strokeHairline)
            .frame(
                width: axis == .vertical ? Metrics.Group.dividerThickness : nil,
                height: axis == .horizontal ? Metrics.Group.dividerThickness : nil
            )
            .accessibilityHidden(true)
    }
}
