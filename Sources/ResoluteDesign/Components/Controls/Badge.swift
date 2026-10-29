import AppKit
import SwiftUI

/// A small capsule label: "Default", "Main", "HiDPI", "Override installed", "Unsaved"
/// (Figma: Components › Badge, tones Neutral, Accent and Warning).
///
/// Contract (Wave 0): the type, `Tone` and `init(_:tone:)` stay; tones may be added. The
/// controls owner refines the drawing.
public struct Badge: View {
    public enum Tone: Sendable, CaseIterable {
        /// A plain fact: "Default", "Main", "Built-in", "Reverted", "Off".
        case neutral
        /// Something Resolute set up or the person chose: "HiDPI", "Kept", "Active",
        /// "Override installed", "Sharp Scaling".
        case accent
        /// Something that needs attention: "Unsaved".
        case warning
    }

    public var text: String
    public var tone: Tone

    public init(_ text: String, tone: Tone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .textStyle(.footnoteEmphasized)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Color(nsColor: tone.foreground))
            .padding(.horizontal, Metrics.Badge.horizontalPadding)
            .frame(height: Metrics.Badge.height)
            .background(Capsule().fill(Color(nsColor: tone.background)))
    }
}

extension Badge.Tone {
    /// The text color: `Labels/Secondary`, the accent, or orange text (`Palette.warningText`).
    var foreground: NSColor {
        switch self {
        case .neutral: .secondaryLabelColor
        case .accent: .controlAccentColor
        case .warning: NSPalette.warningText
        }
    }

    /// The capsule: `Fills - Opaque/Primary`, `surface/accent-tint` or `surface/warning-tint`.
    var background: NSColor {
        switch self {
        case .neutral: NSPalette.fillPrimary
        case .accent: NSPalette.surfaceAccentTint
        case .warning: NSPalette.surfaceWarningTint
        }
    }
}
