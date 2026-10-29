import SwiftUI

/// The small heading over a group: "Presets" in the panel, "Startup" in Settings
/// (Figma: Components › Section Label).
///
/// The label is only its text, as tall as its Figma text box. Figma's panel label is also
/// inset into its section (8 above, 4 below, 10 at the sides); the panel adds those
/// insets from `Metrics.SectionLabel`, so the label lines up wherever it is used.
///
/// Contract (Wave 0): the type and `init(_:)` stay. The controls owner refines the drawing.
public struct SectionLabel: View {
    public enum Style: Sendable {
        /// Over a group in the panel ("Presets"), in `Labels/Secondary` (Figma 17:61).
        case panel
        /// Over a grouped form in the window ("Startup", "Menu Bar" in Settings), in
        /// `Labels/Primary` (Figma 40:149).
        case form
    }

    public var title: String
    public var style: Style

    public init(_ title: String) {
        self.init(title, style: .panel)
    }

    public init(_ title: String, style: Style) {
        self.title = title
        self.style = style
    }

    public var body: some View {
        Text(title)
            .textBox(.subheadlineEmphasized)
            .fixedSize()
            .foregroundStyle(style == .panel ? Palette.labelSecondary : Palette.labelPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}
