import SwiftUI

/// The bar along the bottom of a display's page while its override file has unsaved edits:
/// a lock, what is unsaved ("2 unsaved changes. Saving asks for an administrator
/// password."), Revert and Save… (Figma: Components › Unsaved Bar). Save… also answers ⌘S.
public struct UnsavedBar: View {
    public var message: String
    public var onRevert: () -> Void
    public var onSave: () -> Void

    public init(_ message: String, onRevert: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.message = message
        self.onRevert = onRevert
        self.onSave = onSave
    }

    public var body: some View {
        HStack(spacing: WindowMetrics.UnsavedBar.spacing) {
            Image(symbol: .lock)
                .font(.system(size: WindowMetrics.UnsavedBar.symbolPointSize))
                .foregroundStyle(Palette.labelSecondary)
                .frame(width: WindowMetrics.UnsavedBar.symbolFrame, height: WindowMetrics.UnsavedBar.symbolFrame)
                .accessibilityHidden(true)
            Text(message)
                .textStyle(.callout)
                .foregroundStyle(Palette.labelSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Revert", action: onRevert)
                .fixedSize()
            Button("Save…", action: onSave)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .fixedSize()
        }
        .padding(.leading, WindowMetrics.UnsavedBar.leadingPadding)
        .padding(.trailing, WindowMetrics.UnsavedBar.trailingPadding)
        .frame(maxWidth: .infinity, minHeight: WindowMetrics.UnsavedBar.height)
        .background {
            // Opaque, so the page scrolling under it doesn't show through.
            ZStack {
                Palette.windowBackground
                Palette.surfaceGroup
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.strokeHairline)
                .frame(height: Metrics.Group.dividerThickness)
        }
        .accessibilityElement(children: .contain)
    }
}
