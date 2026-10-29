import ResoluteDesign
import SwiftUI

/// The window's Settings page on one of its tabs (Figma: Settings › General 40:149, Command
/// Line & Agents 42:295, About 42:789): the title, the tabs, then the tab's groups. Settings
/// live in the Resolute window rather than a panel of their own, so they are a ⌘Tab away
/// while a path is pasted or System Settings compared. Choosing a tab goes through the
/// window's route, so Settings… and About Resolute open on the right one.
struct SettingsPage: View {
    let model: AppModel
    let tab: SettingsTab
    /// The `resolute` link; the page reads it again when it appears. The gallery gives one
    /// with a fixed status.
    @State private var commandLine: CommandLineToolModel
    private let about: AboutInfo

    init(model: AppModel, tab: SettingsTab) {
        self.init(
            model: model, tab: tab,
            commandLine: CommandLineToolModel(showError: model.showError),
            about: .current
        )
    }

    init(model: AppModel, tab: SettingsTab, commandLine: CommandLineToolModel, about: AboutInfo) {
        self.model = model
        self.tab = tab
        _commandLine = State(initialValue: commandLine)
        self.about = about
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Settings.spacing) {
                PageHeader("Settings")
                SegmentedTabs(
                    SettingsTab.allCases.map { SegmentedTabs.Item($0, $0.title) },
                    selection: Binding(get: { tab }, set: { model.openSettings($0) })
                )
                .fixedSize()
                .accessibilityLabel("Settings")
                switch tab {
                case .general:
                    GeneralSettings(model: model)
                case .commandLine:
                    CommandLineSettings(model: model, commandLine: commandLine)
                case .about:
                    AboutSettings(info: about)
                }
            }
            .padding(Metrics.TitledPage.insets)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A group's heading: "Startup", "The resolute command". Figma draws these in
/// `Labels/Secondary` on all three tabs, which is the panel style of the label.
struct SettingsSectionLabel: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        SectionLabel(title, style: .panel)
    }
}

extension Metrics {
    /// The Settings pages (Figma 40:149, 42:295, 42:789), where they differ from a titled page.
    enum Settings {
        /// Between the title, the tabs, each heading and its group: Figma's Page stack.
        static let spacing: CGFloat = 14

        /// Teach your agent.
        enum Teach {
            static let insets = EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14)
            static let spacing: CGFloat = 10
            static let codeInsets = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            static let codeLineSpacing: CGFloat = 2
            static let codeCornerRadius: CGFloat = 10
            static let buttonSpacing: CGFloat = 8
        }

        /// The About tab.
        enum About {
            static let insets = EdgeInsets(top: 24, leading: 0, bottom: 8, trailing: 0)
            static let spacing: CGFloat = 10
            static let iconSize: CGFloat = 109
            /// The description wraps at Figma's text box.
            static let descriptionWidth: CGFloat = 440
            /// Above the links, on top of the stack's spacing.
            static let linksTopPadding: CGFloat = 6
            static let linkSpacing: CGFloat = 8
            static let creditsInsets = EdgeInsets(top: 12, leading: 16, bottom: 14, trailing: 16)
            static let creditsSpacing: CGFloat = 6
        }
    }
}
