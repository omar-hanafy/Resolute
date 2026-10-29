import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Welcome, on the first deliberate launch (Figma: Settings and onboarding › Welcome 40:5):
/// what Resolute does, Launch at Login and the `resolute` command to set up right away, and
/// where Resolute lives once the window is closed.
struct WelcomeView: View {
    let model: AppModel
    let commandLine: CommandLineToolModel
    /// Get Started: closes Welcome.
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: Metrics.Welcome.spacing) {
            AppIconView()
                .frame(width: Metrics.Welcome.iconSize, height: Metrics.Welcome.iconSize)
            Text("Welcome to Resolute")
                .textStyle(.largeTitle)
                .foregroundStyle(Palette.labelPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Every resolution and refresh rate for every display, one click away.")
                .textStyle(.body)
                .foregroundStyle(Palette.labelSecondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Metrics.Welcome.featureSpacing) {
                WelcomeFeature(
                    symbol: .menubarRectangle,
                    title: "Every mode, from the menu bar",
                    detail: "Switch resolution and refresh rate for each display, including modes System Settings hides."
                )
                WelcomeFeature(
                    symbol: .lockShield,
                    title: "Risky modes are tried first",
                    detail: "A hidden mode runs for \(model.preferences.trialLength.title) on its own display and switches back unless you keep it."
                )
                WelcomeFeature(
                    symbol: .terminal,
                    title: "Works with you and your agents",
                    detail: "Everything is in the resolute command with JSON output. Agents can ask for a mode; only you can keep a risky one."
                )
            }
            .padding(Metrics.Welcome.featureInsets)
            FormGroup {
                LaunchAtLoginRow(model: model, help: "Resolute starts quietly in the menu bar when you log in.")
                CommandLineToolRow(model: commandLine)
            }
            MenuBarHint()
            Button(action: onGetStarted) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .frame(width: Metrics.Welcome.buttonWidth)
        }
        .padding(Metrics.Welcome.insets)
        .frame(width: Metrics.Welcome.width)
        .onAppear {
            model.refresh()
            commandLine.refresh()
        }
    }
}

/// One thing Resolute does: an accent symbol, a title and a line about it.
private struct WelcomeFeature: View {
    var symbol: Symbol
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Welcome.featureIconSpacing) {
            SymbolIcon(symbol, size: Metrics.Welcome.featureIconSize)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.Welcome.featureTextSpacing) {
                Text(title)
                    .textStyle(.bodyEmphasized)
                    .foregroundStyle(Palette.labelPrimary)
                Text(detail)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Resolute lives in the menu bar. Close this window any time.", beside the menu bar icon
/// as it looks there.
struct MenuBarHint: View {
    var body: some View {
        HStack(spacing: Metrics.Welcome.hintSpacing) {
            Image(nsImage: StatusItemImage().nsImage())
                .renderingMode(.template)
                .foregroundStyle(Palette.labelPrimary)
                .accessibilityHidden(true)
            Text("Resolute lives in the menu bar. Close this window any time.")
                .textStyle(.callout)
                .foregroundStyle(Palette.labelSecondary)
        }
        .padding(Metrics.Welcome.hintInsets)
        .background(Capsule().fill(Palette.surfaceTrack))
        .accessibilityElement(children: .combine)
    }
}

extension Metrics {
    /// Welcome (Figma 40:5).
    enum Welcome {
        /// The window's content: Figma's 680-point window.
        static let width: CGFloat = 680
        /// The content area's 20-point margin and the Welcome frame's own padding (4 above,
        /// 48 at the sides, 28 below).
        static let insets = EdgeInsets(top: 24, leading: 68, bottom: 48, trailing: 68)
        static let spacing: CGFloat = 16
        static let iconSize: CGFloat = 102
        static let featureInsets = EdgeInsets(top: 8, leading: 0, bottom: 4, trailing: 0)
        static let featureSpacing: CGFloat = 14
        static let featureIconSize: CGFloat = 28
        static let featureIconSpacing: CGFloat = 14
        static let featureTextSpacing: CGFloat = 2
        static let hintInsets = EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 14)
        static let hintSpacing: CGFloat = 10
        static let buttonWidth: CGFloat = 200
    }
}
