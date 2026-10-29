import SwiftUI

/// A saved preset in Presets: a star (filled when active), its name, what it sets, its
/// shortcut, and Apply, or an "Active" badge and an accent outline when the current setup
/// matches it (Figma: Components › Preset Card, Default and Active).
public struct PresetCard: View {
    public var name: String
    /// "Built-in 1496 × 967 · DELL U2723QE 2560 × 1440 at 60 Hz".
    public var summary: String
    /// "⌃⌥1", or nil for a preset without one.
    public var shortcut: String?
    public var isActive: Bool
    public var onApply: () -> Void

    public init(name: String, summary: String, shortcut: String? = nil, isActive: Bool = false, onApply: @escaping () -> Void) {
        self.name = name
        self.summary = summary
        self.shortcut = shortcut
        self.isActive = isActive
        self.onApply = onApply
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: WindowMetrics.Preset.cornerRadius, style: .continuous)
        HStack(spacing: WindowMetrics.Preset.spacing) {
            Image(symbol: isActive ? .starFill : .star)
                .font(.system(size: WindowMetrics.Preset.starPointSize))
                .foregroundStyle(isActive ? Palette.accent : Palette.labelSecondary)
                .frame(width: WindowMetrics.Preset.starFrame, height: WindowMetrics.Preset.starFrame)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WindowMetrics.Preset.textSpacing) {
                Text(name)
                    .textStyle(.bodyEmphasized)
                    .foregroundStyle(Palette.labelPrimary)
                    .lineLimit(1)
                Text(summary)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
            if let shortcut {
                PresetShortcut(keys: shortcut)
                    .accessibilityHidden(true)
            }
            if isActive {
                Badge("Active", tone: .accent)
                    .accessibilityHidden(true)
            } else {
                Button("Apply", action: onApply)
                    .buttonStyle(ApplyButtonStyle())
                    .accessibilityLabel("Apply \(name)")
            }
        }
        .padding(insets)
        .background(Palette.surfaceGroup, in: shape)
        .overlay {
            if isActive {
                shape.strokeBorder(Palette.accent, lineWidth: WindowMetrics.Preset.activeOutlineWidth)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Figma lays the active outline out inside the card, which grows it by the outline's
    /// width on every side.
    private var insets: EdgeInsets {
        let base = WindowMetrics.Preset.insets
        let outline = isActive ? WindowMetrics.Preset.activeOutlineWidth : 0
        return EdgeInsets(
            top: base.top + outline,
            leading: base.leading + outline,
            bottom: base.bottom + outline,
            trailing: base.trailing + outline
        )
    }

    /// "Coding, Built-in 1496 by 967 · DELL U2723QE 2560 by 1440 at 60 Hz, Control-Option-1,
    /// active".
    var spokenLabel: String {
        var parts = [name, SpokenText.sizes(summary)]
        if let shortcut {
            parts.append(SpokenText.shortcut(shortcut))
        }
        if isActive {
            parts.append("active")
        }
        return parts.joined(separator: ", ")
    }
}

/// The preset's shortcut in a small rounded chip: "⌃⌥1".
private struct PresetShortcut: View {
    var keys: String

    var body: some View {
        Text(keys)
            .textStyle(.footnote)
            // Figma's Footnote Emphasized: the footnote size, semibold.
            .fontWeight(.semibold)
            .foregroundStyle(Palette.labelSecondary)
            .lineLimit(1)
            .padding(WindowMetrics.Preset.shortcutInsets)
            .background(
                Palette.surfaceTrack,
                in: RoundedRectangle(cornerRadius: WindowMetrics.Preset.shortcutCornerRadius, style: .continuous)
            )
    }
}

/// Apply: white Callout Emphasized on an accent capsule.
private struct ApplyButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.calloutEmphasized)
            .foregroundStyle(Palette.selectedRowText)
            .lineLimit(1)
            .padding(WindowMetrics.Preset.applyInsets)
            .background(Capsule().fill(Palette.accent))
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
    }
}
