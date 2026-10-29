import AppKit
import Foundation
import MachO
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

@MainActor
@Suite struct SettingsPreferencesTests {
    let scratch = ScratchDefaults()

    @Test func commandLineAndAgentSettingsHaveTheDesignsDefaults() {
        let preferences = Preferences(defaults: scratch.defaults)
        #expect(preferences.commandLineHiddenModes == .ask)
        #expect(preferences.showsCommandLineChangesInPanel)
        #expect(!preferences.notifiesAgentChanges)
    }

    @Test func commandLineAndAgentSettingsAreKept() {
        let preferences = Preferences(defaults: scratch.defaults)
        preferences.commandLineHiddenModes = .refuse
        preferences.showsCommandLineChangesInPanel = false
        preferences.notifiesAgentChanges = true

        let reread = Preferences(defaults: scratch.defaults)
        #expect(reread.commandLineHiddenModes == .refuse)
        #expect(!reread.showsCommandLineChangesInPanel)
        #expect(reread.notifiesAgentChanges)
        #expect(scratch.defaults.string(forKey: "CommandLineHiddenModes") == "refuse")
    }

    @Test func anUnknownHiddenModeChoiceReadsAsAskMe() {
        scratch.defaults.set("always", forKey: "CommandLineHiddenModes")
        #expect(Preferences(defaults: scratch.defaults).commandLineHiddenModes == .ask)
    }

    @Test func theHiddenModeChoicesReadAsThePopUpListsThem() {
        #expect(CommandLineHiddenModes.allCases.map(\.title) == ["Ask me", "Don’t allow"])
    }

    /// The help under the pop-up says what the chosen option does.
    @Test func eachHiddenModeChoiceSaysWhatItDoes() {
        #expect(CommandLineHiddenModes.ask.help == "The display shows Keep or Revert; if nobody answers, it switches back.")
        #expect(CommandLineHiddenModes.refuse.help == "The command is turned away before it changes anything.")
    }

    /// `mirror` and the commands that write overrides or Sharp Scaling take no `--json`.
    @Test func theJSONRowPromisesItOnlyForMostCommands() {
        #expect(CommandLineSettings.jsonHelp.hasPrefix("Most commands take --json"))
    }

    /// macOS lets people hide the menu bar item, and Resolute can't read whether they did,
    /// so the row says nothing of whether it shows.
    @Test func theMenuBarRowSaysNothingOfAStateItCantRead() {
        #expect(GeneralSettings.menuBarItemHelp == "macOS controls this in System Settings › Menu Bar.")
    }
}

/// The `resolute` link, read from and planned for a scratch folder; no script is ever run.
@MainActor
@Suite struct CommandLineToolTests {
    let root: URL
    let link: URL
    let app: URL
    let helper: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ResoluteCLITests-\(UUID().uuidString)", directoryHint: .isDirectory)
        link = root.appending(path: "bin/resolute")
        app = root.appending(path: "Applications/Resolute.app", directoryHint: .isDirectory)
        helper = app.appending(path: CommandLineTool.helperPath)
        try FileManager.default.createDirectory(at: root.appending(path: "bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: helper.path, contents: Data("#!/bin/sh\n".utf8))
        let info: [String: Any] = ["CFBundleShortVersionString": "0.4.0", "CFBundleIdentifier": "com.omarhanafy.Resolute.tests"]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: app.appending(path: "Contents/Info.plist"))
    }

    var tool: CommandLineTool { CommandLineTool(link: link, bundled: helper) }

    @Test func nothingAtTheLinkIsNotInstalled() {
        #expect(tool.status() == .notInstalled)
    }

    @Test func withoutTheAppTheCommandIsUnavailable() {
        #expect(CommandLineTool(link: link, bundled: nil).status() == .unavailable)
    }

    @Test func aLinkToResolutesCommandIsInstalledWithThatAppsVersion() throws {
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: helper)
        #expect(tool.status() == .installed(
            version: "0.4.0", detail: "\(link.path) → Resolute.app/Contents/Helpers/resolute"
        ))
    }

    @Test func aLinkToAResoluteThatIsGoneCanBeReplaced() throws {
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: "/Applications/Gone/Resolute.app/Contents/Helpers/resolute"
        )
        #expect(tool.status() == .notInstalled)
    }

    @Test func anotherToolAtThePathIsLeftAlone() throws {
        FileManager.default.createFile(atPath: link.path, contents: Data("other".utf8))
        #expect(tool.status() == .occupied(path: link.path))

        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/opt/homebrew/bin/resolute")
        #expect(tool.status() == .occupied(path: link.path))
    }

    @Test func theInstallScriptLinksTheAppsCommandAndRefusesToReplaceAnythingElse() throws {
        let script = try #require(tool.installScript)
        #expect(script.contains("ln -sfn '\(helper.path)' '\(link.path)'"))
        #expect(script.contains("mkdir -p '\(link.deletingLastPathComponent().path)'"))
        // A link to another app's command, or a file, makes the script stop before `ln`.
        #expect(script.contains("*/Contents/Helpers/resolute) ;;"))
        #expect(script.contains("elif [ -e '\(link.path)' ]; then"))
        let refusal = try #require(script.range(of: "Resolute left it alone."))
        let linking = try #require(script.range(of: "ln -sfn"))
        #expect(refusal.lowerBound < linking.lowerBound)
        #expect(script.hasPrefix("set -e"))
    }

    @Test func pathsAreQuotedForTheShell() throws {
        let odd = CommandLineTool(
            link: URL(filePath: "/usr/local/bin/resolute"),
            bundled: URL(filePath: "/Users/o'neil/My Apps/Resolute.app/Contents/Helpers/resolute")
        )
        let script = try #require(odd.installScript)
        #expect(script.contains(#"'/Users/o'\''neil/My Apps/Resolute.app/Contents/Helpers/resolute'"#))
    }

    @Test func withoutTheAppThereIsNothingToInstall() {
        #expect(CommandLineTool(link: link, bundled: nil).installScript == nil)
    }

    @Test func theRemoveScriptRemovesOnlyALinkToResolutesCommand() {
        let script = tool.removeScript
        #expect(script.contains("if [ -L '\(link.path)' ]; then"))
        #expect(script.contains("*/Contents/Helpers/resolute) rm -f '\(link.path)' ;;"))
        #expect(!script.contains("rm -rf"))
    }

    @Test func aFolderTheUserCanWriteNeedsNoAdministrator() {
        #expect(!tool.needsAdministrator())
        #expect(CommandLineTool(link: URL(filePath: "/System/resolute"), bundled: helper).needsAdministrator())
    }

    @Test func theDetailNamesTheAppNotItsFolder() {
        let detail = CommandLineTool.detail(
            link: URL(filePath: "/usr/local/bin/resolute"),
            target: URL(filePath: "/Applications/Resolute.app/Contents/Helpers/resolute")
        )
        #expect(detail == "/usr/local/bin/resolute → Resolute.app/Contents/Helpers/resolute")
    }
}

/// What the install and remove buttons ask the runner to do.
@MainActor
@Suite struct CommandLineToolModelTests {
    @MainActor
    final class RecordingRunner: CommandRunning, @unchecked Sendable {
        var runs: [(asAdministrator: Bool, prompt: String, script: String)] = []
        var asAdministrator = false
        var prompt = ""
        var failure: (any Error)?

        nonisolated func run(_ script: String) async throws {
            try await MainActor.run {
                runs.append((asAdministrator, prompt, script))
                if let failure { throw failure }
            }
        }
    }

    let runner = RecordingRunner()
    let errors = ShownErrors()

    func model(link: URL = URL(filePath: "/System/resolute")) -> CommandLineToolModel {
        let runner = runner
        let errors = errors
        return CommandLineToolModel(
            tool: CommandLineTool(link: link, bundled: URL(filePath: "/Applications/Resolute.app/Contents/Helpers/resolute")),
            runner: { asAdministrator, prompt in
                runner.asAdministrator = asAdministrator
                runner.prompt = prompt
                return runner
            },
            showError: { _, title in errors.titles.append(title) }
        )
    }

    @Test func installAsksForAnAdministratorWhereTheUserCantWrite() async throws {
        let model = model()
        await model.install()
        let run = try #require(runner.runs.first)
        #expect(run.asAdministrator)
        #expect(run.prompt == "Resolute wants to link the resolute command into /usr/local/bin.")
        #expect(run.script == model.tool.installScript)
        #expect(!model.isWorking)
    }

    @Test func uninstallRunsTheRemoveScript() async throws {
        let model = model()
        await model.uninstall()
        let run = try #require(runner.runs.first)
        #expect(run.prompt == "Resolute wants to remove the resolute command from /usr/local/bin.")
        #expect(run.script == model.tool.removeScript)
    }

    @Test func cancellingThePasswordDialogSaysNothing() async {
        runner.failure = ResoluteError.cancelled
        await model().install()
        #expect(errors.titles.isEmpty)
    }

    @Test func aFailureIsShown() async {
        runner.failure = ResoluteError.commandFailed(status: 1, message: "/usr/local/bin/resolute is not Resolute’s.")
        await model().install()
        #expect(errors.titles == ["The resolute command could not be installed"])
    }

    @Test func theGallerysFixedStatusRunsNothing() async {
        let model = CommandLineToolModel(status: .notInstalled)
        await model.install()
        model.refresh()
        #expect(model.status == .notInstalled)
    }
}

@Suite struct AboutInfoTests {
    @Test func namesTheMacOSReleases() {
        #expect(AboutInfo.systemName(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)) == "macOS 27 Golden Gate")
        #expect(AboutInfo.systemName(OperatingSystemVersion(majorVersion: 15, minorVersion: 6, patchVersion: 0)) == "macOS 15 Sequoia")
        #expect(AboutInfo.systemName(OperatingSystemVersion(majorVersion: 28, minorVersion: 1, patchVersion: 0)) == "macOS 28.1")
    }

    @Test func namesTheArchitecturesTheAppRunsOn() {
        #expect(AboutInfo.architectureNames([Int(CPU_TYPE_ARM64), Int(CPU_TYPE_X86_64)]) == "Apple silicon and Intel")
        #expect(AboutInfo.architectureNames([Int(CPU_TYPE_ARM64)]) == "Apple silicon")
        #expect(AboutInfo.architectureNames([Int(CPU_TYPE_X86_64)]) == "Intel")
    }

    @Test func theVersionLineReadsAsFigmaWritesIt() {
        let info = AboutInfo(version: "0.4.0", system: "macOS 27 Golden Gate", architectures: "Apple silicon and Intel")
        #expect(info.versionLine == "Version 0.4.0 · macOS 27 Golden Gate · Apple silicon and Intel")
    }
}

@Suite struct AgentInstructionsTests {
    @Test func theInstructionsHaveTheCommandsTheJSONRuleAndTheHiddenModeRule() {
        let text = AgentInstructions.text
        for command in ["resolute displays --json", "resolute set", "resolute preset apply", "resolute history --json"] {
            #expect(text.contains(command))
        }
        #expect(text.contains("Every key is always present"))
        #expect(text.contains("only a person at the display can keep one"))
    }

    /// The commands listed take `--json`, all but `mirror`, which `resolute`'s own tests check.
    @Test func theInstructionsSayWhichCommandsTakeJSON() {
        #expect(AgentInstructions.text.contains("All of these but `mirror` take `--json`."))
        #expect(!AgentInstructions.text.contains("Every command takes"))
    }

    @Test func theSkillIsWrittenWhereClaudeCodeFindsIt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ResoluteSkillTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let skill = ClaudeCodeSkill(skillsFolder: folder)
        #expect(!skill.isInstalled)
        try skill.install()
        #expect(skill.isInstalled)
        let written = try String(contentsOf: folder.appending(path: "resolute/SKILL.md"), encoding: .utf8)
        #expect(written.hasPrefix("---\nname: resolute\ndescription: "))
        #expect(written.contains(AgentInstructions.text))
    }
}
