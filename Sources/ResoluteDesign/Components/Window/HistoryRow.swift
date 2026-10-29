import SwiftUI

/// One change in History: when, where it came from (a symbol for the panel, Terminal or an
/// agent, Shortcuts), what changed, how it ended and Undo (Figma: Components › History Row).
/// It draws a hairline under itself, as Figma's rows do in their list.
public struct HistoryRow: View {
    /// How a change ended.
    public enum Status: Sendable, CaseIterable {
        case kept
        case reverted
        case undone
        /// The change didn't happen; the row's detail says why.
        case failed

        /// The badge's text, as Figma writes it.
        public var title: String {
            switch self {
            case .kept: "Kept"
            case .reverted: "Reverted"
            case .undone: "Undone"
            case .failed: "Failed"
            }
        }

        /// A kept change is still in use, so it stands out, as does one that failed; the
        /// others are over.
        public var tone: Badge.Tone {
            switch self {
            case .kept: .accent
            case .failed: .warning
            case .reverted, .undone: .neutral
            }
        }
    }

    /// "9:41", "Yesterday".
    public var time: String
    /// Where the change came from: `.terminal`, `.menubarRectangle`, `.switch2`.
    public var source: Symbol
    /// "DELL U2723QE  2560 × 1440 → 2880 × 1620".
    public var title: String
    /// "From Claude Code (Terminal) · hidden mode · nobody answered".
    public var detail: String
    public var status: Status
    /// Puts back what was there before; nil when the change can't be undone.
    public var onUndo: (() -> Void)?

    public init(
        time: String,
        source: Symbol,
        title: String,
        detail: String,
        status: Status,
        onUndo: (() -> Void)? = nil
    ) {
        self.time = time
        self.source = source
        self.title = title
        self.detail = detail
        self.status = status
        self.onUndo = onUndo
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: WindowMetrics.History.spacing) {
                Text(time)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .lineLimit(1)
                    .frame(width: WindowMetrics.History.timeWidth, alignment: .leading)
                Image(symbol: source)
                    .font(.system(size: WindowMetrics.History.symbolPointSize))
                    .foregroundStyle(Palette.labelSecondary)
                    .frame(width: WindowMetrics.History.symbolFrame, height: WindowMetrics.History.symbolFrame)
                VStack(alignment: .leading, spacing: WindowMetrics.History.textSpacing) {
                    Text(title)
                        .textStyle(.body)
                        .foregroundStyle(Palette.labelPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .textStyle(.subheadline)
                        .foregroundStyle(Palette.labelSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Badge(status.title, tone: status.tone)
                if let onUndo {
                    Button(action: onUndo) {
                        Text("Undo")
                            .textStyle(.calloutEmphasized)
                            .foregroundStyle(Palette.accent)
                            .frame(width: WindowMetrics.History.undoWidth, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, WindowMetrics.History.verticalPadding)
            .padding(.horizontal, WindowMetrics.History.horizontalPadding)
            Rectangle()
                .fill(Palette.strokeHairline)
                .frame(height: Metrics.Group.dividerThickness)
        }
        // One line for VoiceOver, with Undo among its actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityActions {
            if let onUndo {
                Button("Undo", action: onUndo)
            }
        }
    }

    /// "9:41, DELL U2723QE 2560 by 1440 to 2880 by 1620, From Terminal, Kept".
    var spokenLabel: String {
        [time, SpokenText.sizes(title), SpokenText.sizes(detail), status.title].joined(separator: ", ")
    }
}
