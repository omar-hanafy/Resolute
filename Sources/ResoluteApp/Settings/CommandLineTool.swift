import Foundation
import Observation
import ResoluteKit

/// The `resolute` command as Settings › Command Line & Agents and Welcome install it: a link
/// at /usr/local/bin/resolute to the copy inside Resolute.app, so the command and the app
/// are always the same version and updating the app updates the command.
struct CommandLineTool: Equatable, Sendable {
    /// Where Terminal, scripts and agents find the command: on every Mac's default PATH.
    static let standardLink = URL(filePath: "/usr/local/bin/resolute")
    /// Where an app bundle keeps the command (Scripts/build-app.sh puts it there).
    static let helperPath = "Contents/Helpers/resolute"

    enum Status: Equatable, Sendable {
        /// Resolute isn't running from its app, so there's no command to link.
        case unavailable
        /// Nothing is at the link's path, or a link to a Resolute that is gone.
        case notInstalled
        /// The link points at a Resolute app's command: "resolute 0.4.0 is installed",
        /// "/usr/local/bin/resolute → Resolute.app/Contents/Helpers/resolute".
        case installed(version: String, detail: String)
        /// Something that isn't Resolute's is at the link's path, which Resolute leaves alone.
        case occupied(path: String)
    }

    /// The link to make.
    var link: URL
    /// The command inside this app; nil when Resolute isn't running from an app bundle.
    var bundled: URL?

    /// This app's command, linked at /usr/local/bin.
    static func live(bundle: Bundle = .main) -> CommandLineTool {
        let bundled = bundle.bundleURL.pathExtension == "app"
            ? bundle.bundleURL.appending(path: helperPath, directoryHint: .notDirectory)
            : nil
        return CommandLineTool(link: standardLink, bundled: bundled)
    }

    /// What is at the link's path now.
    func status(fileManager: FileManager = .default) -> Status {
        let linkPath = link.path(percentEncoded: false)
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: linkPath) else {
            // Not a link: nothing there, or a file of someone else's.
            if fileManager.fileExists(atPath: linkPath) { return .occupied(path: linkPath) }
            return bundled == nil ? .unavailable : .notInstalled
        }
        let target = URL(filePath: destination, relativeTo: link.deletingLastPathComponent()).standardizedFileURL
        guard Self.isResoluteHelper(target.path(percentEncoded: false)) else { return .occupied(path: linkPath) }
        guard fileManager.fileExists(atPath: target.path(percentEncoded: false)) else {
            // The app it pointed at was moved or deleted; installing replaces the link.
            return bundled == nil ? .unavailable : .notInstalled
        }
        let app = target.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return .installed(version: Self.version(ofAppAt: app) ?? ResoluteVersion.string, detail: Self.detail(link: link, target: target))
    }

    /// Links the command, as root or as the user. Refuses to replace anything that isn't a
    /// link to a Resolute app's command, so it never deletes another tool of the same name.
    var installScript: String? {
        guard let bundled else { return nil }
        let target = Shell.quote(bundled.path(percentEncoded: false))
        let link = Shell.quote(link.path(percentEncoded: false))
        let folder = Shell.quote((self.link.path(percentEncoded: false) as NSString).deletingLastPathComponent)
        return """
            set -e
            [ -x \(target) ] || { echo "The resolute command is missing from Resolute.app." >&2; exit 1; }
            mkdir -p \(folder)
            if [ -L \(link) ]; then
              case "$(readlink \(link))" in
                */\(Self.helperPath)) ;;
                *) echo \(Shell.quote("\(self.link.path(percentEncoded: false)) belongs to another app. Resolute left it alone.")) >&2; exit 1 ;;
              esac
            elif [ -e \(link) ]; then
              echo \(Shell.quote("\(self.link.path(percentEncoded: false)) is not Resolute’s. Resolute left it alone.")) >&2; exit 1
            fi
            ln -sfn \(target) \(link)
            """
    }

    /// Removes the link, only when it is a link to a Resolute app's command.
    var removeScript: String {
        let link = Shell.quote(link.path(percentEncoded: false))
        return """
            set -e
            if [ -L \(link) ]; then
              case "$(readlink \(link))" in
                */\(Self.helperPath)) rm -f \(link) ;;
                *) echo \(Shell.quote("\(self.link.path(percentEncoded: false)) belongs to another app. Resolute left it alone.")) >&2; exit 1 ;;
              esac
            fi
            """
    }

    /// Whether changing the link needs an administrator: the folder (or the folder it would
    /// be made in) isn't the user's to write.
    func needsAdministrator(fileManager: FileManager = .default) -> Bool {
        var folder = link.deletingLastPathComponent()
        while !fileManager.fileExists(atPath: folder.path(percentEncoded: false)), folder.pathComponents.count > 1 {
            folder = folder.deletingLastPathComponent()
        }
        return !fileManager.isWritableFile(atPath: folder.path(percentEncoded: false))
    }

    /// "/usr/local/bin/resolute → Resolute.app/Contents/Helpers/resolute": the link and its
    /// target from the app on, which says where the command comes from without the folder.
    static func detail(link: URL, target: URL) -> String {
        let components = target.pathComponents
        let fromApp = components.lastIndex { $0.hasSuffix(".app") }.map { components[$0...].joined(separator: "/") }
        return "\(link.path(percentEncoded: false)) → \(fromApp ?? target.path(percentEncoded: false))"
    }

    static func isResoluteHelper(_ path: String) -> Bool {
        path.hasSuffix("/" + helperPath)
    }

    /// The app's version, from its Info.plist.
    static func version(ofAppAt app: URL) -> String? {
        Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }
}

/// Installs and removes the `resolute` link for Settings and Welcome, asking for an
/// administrator's password when /usr/local/bin isn't the user's to write.
@MainActor
@Observable
final class CommandLineToolModel {
    /// Runs a script, as an administrator when the first argument says so, with the
    /// password dialog's message. Tests record the script instead of running it.
    typealias Runner = @MainActor (_ asAdministrator: Bool, _ prompt: String) -> any CommandRunning

    private(set) var status: CommandLineTool.Status
    /// While a script runs, so the button can't start a second one.
    private(set) var isWorking = false

    @ObservationIgnored let tool: CommandLineTool
    /// False for the gallery's fixed status.
    @ObservationIgnored private let readsLink: Bool
    @ObservationIgnored private let runner: Runner
    @ObservationIgnored private let showError: @MainActor (any Error, String) -> Void

    init(
        tool: CommandLineTool = .live(),
        runner: @escaping Runner = CommandLineToolModel.liveRunner,
        showError: @escaping @MainActor (any Error, String) -> Void
    ) {
        self.tool = tool
        self.runner = runner
        self.showError = showError
        readsLink = true
        status = tool.status()
    }

    /// For the gallery: a status shown as given, never read from the disk.
    init(status: CommandLineTool.Status) {
        tool = CommandLineTool(link: CommandLineTool.standardLink, bundled: nil)
        readsLink = false
        runner = { _, _ in ShellCommandRunner() }
        showError = { _, _ in }
        self.status = status
    }

    static let installPrompt = "Resolute wants to link the resolute command into /usr/local/bin."
    static let removePrompt = "Resolute wants to remove the resolute command from /usr/local/bin."

    static let liveRunner: Runner = { asAdministrator, prompt in
        asAdministrator ? AdminCommandRunner(prompt: prompt) : ShellCommandRunner()
    }

    /// Reads the link again; the command line or another copy of Resolute may have changed it.
    func refresh() {
        guard readsLink else { return }
        let fresh = tool.status()
        if fresh != status { status = fresh }
    }

    /// Install…: links the command.
    func install() async {
        guard let script = tool.installScript else { return }
        await run(script, prompt: Self.installPrompt, failure: "The resolute command could not be installed")
    }

    /// Uninstall…: removes the link.
    func uninstall() async {
        await run(tool.removeScript, prompt: Self.removePrompt, failure: "The resolute command could not be removed")
    }

    private func run(_ script: String, prompt: String, failure: String) async {
        guard readsLink, !isWorking else { return }
        isWorking = true
        defer {
            isWorking = false
            refresh()
        }
        do {
            try await runner(tool.needsAdministrator(), prompt).run(script)
        } catch ResoluteError.cancelled {
            // The person closed the password dialog: nothing changed, nothing to say.
        } catch {
            showError(error, failure)
        }
    }
}
