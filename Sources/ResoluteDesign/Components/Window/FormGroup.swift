import SwiftUI

/// Form rows in one rounded `surface/group` container, with a full-width hairline between
/// rows (Figma: the Startup, Menu Bar and Panel groups of Settings › General, 40:149).
///
///     FormGroup {
///         FormRow("Launch at Login", help: "…", isOn: $launchAtLogin)
///         FormRow("Hidden-mode trial", help: "…", selection: $trial, options: trials)
///     }
public struct FormGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .environment(\.isInFormGroup, true)
        // Every row draws a divider under itself. The group ends a divider early, so the
        // last row's falls outside it and is clipped away.
        .padding(.bottom, -Metrics.Group.dividerThickness)
        .frame(maxWidth: .infinity)
        .groupSurface()
    }
}

extension View {
    /// Makes a view a row of a `FormGroup`, with the divider the group shows between rows.
    /// `FormRow` does this itself; use it for a custom row. Outside a group it does nothing.
    public func formGroupRow() -> some View {
        modifier(FormGroupRow())
    }
}

private struct FormGroupRow: ViewModifier {
    @Environment(\.isInFormGroup) private var isInFormGroup

    func body(content: Content) -> some View {
        if isInFormGroup {
            VStack(spacing: 0) {
                content
                Rectangle()
                    .fill(Palette.strokeHairline)
                    .frame(height: Metrics.Group.dividerThickness)
                    .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}

private struct FormGroupKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the view is a row of a `FormGroup`, which shows dividers between its rows.
    var isInFormGroup: Bool {
        get { self[FormGroupKey.self] }
        set { self[FormGroupKey.self] = newValue }
    }
}
