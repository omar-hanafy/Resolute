import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Settings › Command Line & Agents (Figma 42:295): the `resolute` command, installed or not,
/// with the diagnostic report and the JSON reference; what agents may do; and what to give
/// an agent so it knows the commands.
struct CommandLineSettings: View {
    /// Under JSON output: not every command takes `--json` (`mirror` and the commands that
    /// write overrides or Sharp Scaling don't); the reference the row opens lists which do.
    static let jsonHelp = "Most commands take --json. Keys are always present, null when there is no value."

    let model: AppModel
    let commandLine: CommandLineToolModel
    @State private var isConfirmingSkill = false

    var body: some View {
        @Bindable var preferences = model.preferences
        VStack(alignment: .leading, spacing: Metrics.Settings.spacing) {
            SettingsSectionLabel("The resolute command")
            FormGroup {
                CommandLineToolRow(model: commandLine)
                FormRow(
                    "Diagnostic report",
                    help: "Runs resolute doctor: versions, displays, modes and overrides, ready for a bug report.",
                    buttonTitle: "Copy Report"
                ) {
                    Task { await DiagnosticReport.copy(showError: model.showError) }
                }
                FormRow(
                    "JSON output",
                    help: Self.jsonHelp,
                    value: "docs/json.md"
                ) {
                    ResoluteLinks.jsonReference.open()
                }
                .accessibilityHint("Opens the JSON reference in your browser.")
            }
            SettingsSectionLabel("Agents")
            FormGroup {
                FormRow(
                    "Hidden modes asked for from the command line",
                    help: preferences.commandLineHiddenModes.help,
                    selection: $preferences.commandLineHiddenModes,
                    options: CommandLineHiddenModes.allCases.map { FormRowPopUp.Option($0, $0.title) }
                )
                FormRow(
                    "Show command-line changes in the panel",
                    help: "The latest change appears in the panel with Undo.",
                    isOn: $preferences.showsCommandLineChangesInPanel
                )
                FormRow(
                    "Notify me when an agent changes a display",
                    help: "A notification with Undo, even when the panel is closed.",
                    isOn: $preferences.notifiesAgentChanges
                )
            }
            SettingsSectionLabel("Teach your agent")
            TeachYourAgent(
                copyInstructions: { Clipboard.copy(AgentInstructions.text) },
                installSkill: { isConfirmingSkill = true }
            )
        }
        .onAppear { commandLine.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // A Terminal may have changed the link while Resolute was in the background.
            commandLine.refresh()
        }
        .confirmationDialog(
            ClaudeCodeSkill.live.isInstalled ? "Replace the Resolute skill for Claude Code?" : "Install the Resolute skill for Claude Code?",
            isPresented: $isConfirmingSkill
        ) {
            Button(ClaudeCodeSkill.live.isInstalled ? "Replace" : "Install") { installSkill() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Resolute writes the agent instructions to \(ClaudeCodeSkill.live.displayPath), where Claude Code finds them in every project.")
        }
    }

    private func installSkill() {
        do {
            try ClaudeCodeSkill.live.install()
        } catch {
            model.showError(error, "The skill could not be installed")
        }
    }
}

/// The `resolute` command's row, in Settings and in Welcome: "resolute 0.4.0 is installed"
/// with Uninstall…, or Install the resolute command with Install….
struct CommandLineToolRow: View {
    let model: CommandLineToolModel
    @State private var isConfirmingRemoval = false

    var body: some View {
        Group {
            switch model.status {
            case .installed(let version, let detail):
                FormRow("resolute \(version) is installed", help: detail) {
                    FormRowButton("Uninstall…") { isConfirmingRemoval = true }
                        .disabled(model.isWorking)
                }
                .symbol(.checkmarkCircleFill, color: Palette.green)
            case .notInstalled, .unavailable:
                FormRow("Install the resolute command", help: installHelp) {
                    FormRowButton("Install…") { Task { await model.install() } }
                        .disabled(model.isWorking || model.status == .unavailable)
                }
            case .occupied(let path):
                FormRow("Another resolute is installed", help: "\(path) isn’t Resolute’s, so Resolute leaves it alone.") {
                    EmptyView()
                }
                .symbol(.exclamationmarkTriangleFill, color: Palette.orange)
            }
        }
        .confirmationDialog("Uninstall the resolute command?", isPresented: $isConfirmingRemoval) {
            Button("Uninstall") { Task { await model.uninstall() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Terminal, scripts and agents can’t use resolute until you install it again. Resolute itself keeps working.")
        }
    }

    private var installHelp: String {
        model.status == .unavailable
            ? "Available when Resolute runs from its app in Applications."
            : "Links resolute into /usr/local/bin for Terminal, scripts and agents."
    }
}

/// Teach your agent: what to give Claude Code, Codex or any agent, the commands it starts
/// with, and the two ways to hand it over.
struct TeachYourAgent: View {
    var copyInstructions: () -> Void
    var installSkill: () -> Void

    var body: some View {
        GroupedSection(insets: Metrics.Settings.Teach.insets, spacing: Metrics.Settings.Teach.spacing) {
            Text("Give Claude Code, Codex or any agent the commands, the JSON keys and the hidden-mode rule.")
                .textStyle(.callout)
                .foregroundStyle(Palette.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Metrics.Settings.Teach.codeLineSpacing) {
                ForEach(AgentInstructions.exampleCommands, id: \.self) { command in
                    Text(command)
                        .textBox(.mono)
                        .foregroundStyle(Palette.labelPrimary)
                }
            }
            .textSelection(.enabled)
            .padding(Metrics.Settings.Teach.codeInsets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Palette.surfaceTrack,
                in: RoundedRectangle(cornerRadius: Metrics.Settings.Teach.codeCornerRadius, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Example commands")
            .accessibilityValue(AgentInstructions.exampleCommands.joined(separator: ", "))
            HStack(spacing: Metrics.Settings.Teach.buttonSpacing) {
                Button("Copy Agent Instructions", action: copyInstructions)
                    .accessibilityHint("Copies the commands, the JSON keys and the hidden-mode rule.")
                Button("Install Claude Code Skill…", action: installSkill)
            }
        }
    }
}

/// Resolute's pages on GitHub.
enum ResoluteLinks {
    case repository
    case changelog
    case newIssue
    case jsonReference

    static let base = "https://github.com/omar-hanafy/Resolute"

    var url: URL? {
        switch self {
        case .repository: URL(string: Self.base)
        case .changelog: URL(string: Self.base + "/blob/main/CHANGELOG.md")
        case .newIssue: URL(string: Self.base + "/issues/new")
        case .jsonReference: URL(string: Self.base + "/blob/main/docs/json.md")
        }
    }

    @MainActor
    func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Puts text on the general pasteboard.
@MainActor
enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
