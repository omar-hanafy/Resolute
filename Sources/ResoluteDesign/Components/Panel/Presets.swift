import SwiftUI

/// A saved preset in the panel, applied in one click (Figma: Preset Chip, 17:78). The active
/// one, filled with the accent color, is the one the displays match now.
public struct PresetChip: View {
    public var name: String
    public var isActive: Bool
    public var symbol: Symbol?
    public var action: () -> Void

    public init(_ name: String, isActive: Bool = false, symbol: Symbol? = nil, action: @escaping () -> Void) {
        self.name = name
        self.isActive = isActive
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.Spacing.xSmall) {
                if let symbol {
                    PanelIcon(symbol, size: .small)
                        .foregroundStyle(isActive ? PanelPalette.onAccent : Palette.labelSecondary)
                }
                Text(name)
                    .panelTextStyle(.calloutEmphasized)
                    .foregroundStyle(isActive ? PanelPalette.onAccent : Palette.labelPrimary)
                    .lineLimit(1)
            }
            .padding(PanelMetrics.Chip.insets)
            .background(Capsule().fill(isActive ? Palette.accent : Palette.surfaceTrack))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityHint("Applies this preset")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// The panel's Presets section: its label, a chip for each preset, the active one starred,
/// and a round + button that saves the current setup as a new one (Figma 20:402). Chips
/// that don't fit on one line wrap to the next.
public struct PresetsRow: View {
    /// The presets: each one's title is its name, `isSelected` marks the one the displays
    /// match now, and choosing it applies it.
    public var presets: [PanelChoice]
    public var saveCurrentSetup: () -> Void

    public init(_ presets: [PanelChoice], saveCurrentSetup: @escaping () -> Void) {
        self.presets = presets
        self.saveCurrentSetup = saveCurrentSetup
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Spacing.xxSmall) {
            SectionLabel("Presets")
                .padding(PanelMetrics.Presets.labelInsets)
            PanelChipFlow(spacing: PanelMetrics.Presets.chipSpacing) {
                ForEach(presets.indices, id: \.self) { index in
                    let preset = presets[index]
                    PresetChip(
                        preset.title,
                        isActive: preset.isSelected,
                        symbol: preset.isSelected ? .star : nil,
                        action: preset.select
                    )
                }
                PanelCircleButton(symbol: .plus, iconSize: .button, label: "Save Current Setup", action: saveCurrentSetup)
            }
            .padding(.leading, Metrics.Spacing.xSmall)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Presets")
    }
}

/// Lays chips out left to right, top-aligned as in Figma, and starts a new line when the
/// next chip doesn't fit.
struct PanelChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = arrange(subviews, width: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(line.indices, line.sizes) {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var line = Line()
        // A chip wider than the line gets the line's width, and its name is shortened.
        let proposal = ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(proposal)
            let widthWithChip = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            if !line.indices.isEmpty, widthWithChip > width {
                lines.append(line)
                line = Line()
            }
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
            line.sizes.append(size)
        }
        if !line.indices.isEmpty {
            lines.append(line)
        }
        return lines
    }
}
