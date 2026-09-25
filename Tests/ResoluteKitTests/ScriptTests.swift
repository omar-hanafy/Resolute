import Foundation
import Testing

/// Checks the install/uninstall scripts: syntax, shellcheck, and the shared
/// quit-and-wait logic in Scripts/lib.sh. The quit-and-wait tests stub osascript, so
/// nothing here ever asks a real application to quit.
@Suite struct ScriptTests {
    /// Tests/ResoluteKitTests/ScriptTests.swift -> Tests/ResoluteKitTests -> Tests -> repo root.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var scriptsDir: URL { repoRoot.appending(path: "Scripts") }
    static var libPath: String { scriptsDir.appending(path: "lib.sh").path }

    static var shellScripts: [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: scriptsDir, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.pathExtension == "sh" }.sorted { $0.path < $1.path }
    }

    /// Homebrew's shellcheck on Apple silicon or on Intel.
    static let shellcheckPath = ["/opt/homebrew/bin/shellcheck", "/usr/local/bin/shellcheck"]
        .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/shellcheck"
    static var shellcheckInstalled: Bool { FileManager.default.isExecutableFile(atPath: shellcheckPath) }

    // MARK: - Process running

    /// Runs a program synchronously, combining its stdout and stderr.
    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Sources lib.sh with `osascript` replaced by `stub`, sets a fake BUNDLE_ID plus any
    /// `env` overrides, calls `quit_and_wait`, and returns its exit status. `osascript` is
    /// always a stub and BUNDLE_ID is always fake, so this never touches a real app.
    private static func quitAndWaitStatus(stub: String, env: [String: String] = [:]) throws -> Int32 {
        var script = "source \(shellQuote(libPath))\n"
        script += stub + "\n"
        script += "BUNDLE_ID=\(shellQuote("com.example.NotResolute"))\n"
        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            script += "\(key)=\(shellQuote(value))\n"
        }
        script += """
        rc=0
        quit_and_wait || rc=$?
        echo "$rc"
        """
        let result = try run("/bin/bash", ["-c", script])
        // The status is the last line; quit_and_wait prints what it is waiting for first.
        let lastLine = result.output.split(separator: "\n").last.map(String.init) ?? ""
        let status = Int32(lastLine.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(status != nil, "test harness did not print a status: \(result.output)")
        return status ?? -1
    }

    // MARK: - Syntax and lint

    @Test(arguments: shellScripts) func hasValidSyntax(script: URL) throws {
        let result = try Self.run("/bin/bash", ["-n", script.path])
        #expect(result.status == 0, "bash -n \(script.lastPathComponent):\n\(result.output)")
    }

    @Test(.enabled(if: shellcheckInstalled)) func scriptsPassShellcheck() throws {
        let result = try Self.run(Self.shellcheckPath, Self.shellScripts.map(\.path))
        #expect(result.status == 0, "\(result.output)")
    }

    // MARK: - unregister_login_item

    /// A fake Resolute.app whose "binary" records the arguments it was run with.
    private static func fakeApp(version: String?, in folder: URL) throws -> (app: URL, marker: URL) {
        let app = folder.appending(path: "Resolute.app")
        let executable = app.appending(path: "Contents/MacOS/Resolute")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": "com.example.NotResolute"]
        if let version { info["CFBundleShortVersionString"] = version }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        let marker = folder.appending(path: "ran")
        try Data("#!/bin/sh\necho \"$@\" > \(shellQuote(marker.path))\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (app, marker)
    }

    @discardableResult
    private static func unregister(_ app: URL, timeout: Int = 5) throws -> String {
        let script = "source \(shellQuote(libPath))\nRESOLUTE_UNREGISTER_TIMEOUT=\(timeout)\nunregister_login_item \(shellQuote(app.path))"
        let result = try run("/bin/bash", ["-c", script])
        #expect(result.status == 0, "\(result.output)")
        return result.output
    }

    /// A fake Resolute.app 0.2.0 whose "binary" runs `body`.
    private static func fakeApp(running body: String, in folder: URL) throws -> URL {
        let (app, _) = try fakeApp(version: "0.2.0", in: folder)
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: app.appending(path: "Contents/MacOS/Resolute"))
        return app
    }

    /// A build labelled 0.2 from before the flag existed starts the menu-bar app instead;
    /// it must not keep the uninstaller waiting.
    @Test func stopsABuildThatStartsTheAppInstead() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let pidFile = folder.appending(path: "pid")
        let app = try Self.fakeApp(running: "echo $$ > \(Self.shellQuote(pidFile.path)); exec sleep 30", in: folder)
        let started = Date()
        let output = try Self.unregister(app, timeout: 1)
        #expect(Date().timeIntervalSince(started) < 4)
        #expect(output.contains("Turn it off in System Settings > General > Login Items."))
        let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(pid, 0) != 0, "the stand-in app is still running")
    }

    @Test func saysWhenLaunchAtLoginCannotBeTurnedOff() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = try Self.fakeApp(running: "echo 'Operation not permitted' >&2; exit 1", in: folder)
        let output = try Self.unregister(app)
        #expect(output.contains("Could not turn off Launch at Login: Operation not permitted"))
        #expect(output.contains("Turn it off in System Settings > General > Login Items."))
    }

    /// 0.1 builds start the whole menu-bar app for a flag they don't know, which would
    /// leave the uninstaller waiting on it for ever, so only 0.2 and later are asked.
    @Test(arguments: [("0.1.0", false), (nil, false), ("0.2.0", true), ("1.4.2", true)])
    func asksOnlyBuildsThatKnowTheFlag(version: String?, runs: Bool) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let (app, marker) = try Self.fakeApp(version: version, in: folder)
        try Self.unregister(app)
        let ran = try? String(contentsOf: marker, encoding: .utf8)
        #expect((ran != nil) == runs)
        if runs { #expect(ran == "--unregister-login-item\n") }
    }

    // MARK: - quit_and_wait

    /// The app may be asking about unsaved changes when it is asked to quit; osascript
    /// must not wait (up to two minutes) for that answer before the timed wait begins.
    @Test func asksTheAppToQuitWithoutWaitingForItsAnswer() throws {
        let calls = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-calls-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: calls) }
        let stub = """
        polls=0
        osascript() {
          echo "$*" >> \(Self.shellQuote(calls.path))
          if [[ "$*" == *"to quit"* ]]; then return 0; fi
          if [[ -s \(Self.shellQuote(calls.path)) && $(wc -l < \(Self.shellQuote(calls.path))) -gt 2 ]]; then echo false; else echo true; fi
        }
        """
        #expect(try Self.quitAndWaitStatus(stub: stub, env: ["RESOLUTE_QUIT_POLL_INTERVAL": "0.05"]) == 0)
        let sent = try String(contentsOf: calls, encoding: .utf8)
        #expect(sent.contains("ignoring application responses"))
    }

    @Test func quitAndWaitSucceedsAtOnceWhenNothingIsRunning() throws {
        let stub = """
        osascript() {
          if [[ "$*" == *"to quit"* ]]; then return 0; fi
          echo "false"
        }
        """
        #expect(try Self.quitAndWaitStatus(stub: stub) == 0)
    }

    @Test func quitAndWaitPollsThenSucceedsOnceTheAppStops() throws {
        // Reports the app running for the first three "is it running" polls, then stopped.
        // The counter lives in a file, not a shell variable: app_is_running captures
        // osascript's output with $(...), which runs the stub in a subshell, so a plain
        // variable assignment would not survive between calls.
        let stub = """
        polls="$(mktemp)"
        trap 'rm -f "$polls"' EXIT
        echo 0 > "$polls"
        osascript() {
          if [[ "$*" == *"to quit"* ]]; then return 0; fi
          local n; n="$(cat "$polls")"
          if (( n < 3 )); then
            echo $((n + 1)) > "$polls"
            echo "true"
          else
            echo "false"
          fi
        }
        """
        let status = try Self.quitAndWaitStatus(stub: stub, env: ["RESOLUTE_QUIT_POLL_INTERVAL": "0.05"])
        #expect(status == 0)
    }

    @Test func quitAndWaitGivesUpWhenTheAppNeverStops() throws {
        let stub = """
        osascript() {
          if [[ "$*" == *"to quit"* ]]; then return 0; fi
          echo "true"
        }
        """
        let status = try Self.quitAndWaitStatus(
            stub: stub,
            env: ["RESOLUTE_QUIT_TIMEOUT": "1", "RESOLUTE_QUIT_POLL_INTERVAL": "0.2"]
        )
        #expect(status == 1)
    }

    // MARK: - install.sh and uninstall.sh

    private static let fakeBundleID = "com.example.ResoluteScriptTests"

    /// Runs a program with `env` merged onto the current environment, combining stdout
    /// and stderr.
    @discardableResult
    private static func run(_ executable: String, _ arguments: [String], env: [String: String]) throws
        -> (status: Int32, output: String)
    {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env { environment[key] = value }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// A throwaway "repo" with Scripts/{install,uninstall,lib}.sh copied from the real
    /// ones and a fake dist/Resolute.app, so install.sh never reaches build-app.sh.
    /// `Contents/MacOS/Resolute` records its arguments to CALLS_LOG (an environment
    /// variable `makeSandbox` sets) and prints "Launch at Login is off." for
    /// `--unregister-login-item`, like a build that knows the flag.
    private static func makeFakeRepo(in folder: URL, version: String) throws -> URL {
        let repo = folder.appending(path: "repo")
        let scripts = repo.appending(path: "Scripts")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        for name in ["install.sh", "uninstall.sh", "lib.sh"] {
            try FileManager.default.copyItem(at: scriptsDir.appending(path: name), to: scripts.appending(path: name))
        }

        let contents = repo.appending(path: "dist/Resolute.app/Contents")
        try FileManager.default.createDirectory(at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appending(path: "Helpers"), withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": fakeBundleID,
            "CFBundleShortVersionString": version,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))

        let binary = """
        #!/bin/sh
        echo "Resolute $*" >> "$CALLS_LOG"
        if [ "$1" = "--unregister-login-item" ]; then
          echo "Launch at Login is off."
        fi
        """
        let binaryPath = contents.appending(path: "MacOS/Resolute")
        try Data(binary.utf8).write(to: binaryPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)

        let cliPath = contents.appending(path: "Helpers/resolute")
        try Data("#!/bin/sh\necho \"fake resolute cli $*\"\n".utf8).write(to: cliPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliPath.path)

        return repo
    }

    /// A bin directory with stand-ins for `osascript`, `open` and `defaults`, meant to be
    /// put ahead of the real ones on PATH. Each appends its name and arguments to
    /// CALLS_LOG and never calls the real tool. `osascript` answers the is-running query
    /// from RUNNING_FILE ("true" or "false") and, when asked to quit and QUITS_FILE says
    /// "yes", sets RUNNING_FILE to "false" so the poll in quit_and_wait sees it stop.
    private static func makeStubBin(in folder: URL) throws -> URL {
        let bin = folder.appending(path: "stubbin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let osascript = """
        #!/bin/sh
        echo "osascript $*" >> "$CALLS_LOG"
        case "$*" in
          *"to quit"*)
            if [ "$(cat "$QUITS_FILE" 2>/dev/null)" = "yes" ]; then
              echo "false" > "$RUNNING_FILE"
            fi
            exit 0
            ;;
        esac
        cat "$RUNNING_FILE"
        """
        let open = """
        #!/bin/sh
        echo "open $*" >> "$CALLS_LOG"
        """
        let defaultsStub = """
        #!/bin/sh
        echo "defaults $*" >> "$CALLS_LOG"
        """

        for (name, body) in ["osascript": osascript, "open": open, "defaults": defaultsStub] {
            let url = bin.appending(path: name)
            try Data(body.utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return bin
    }

    /// A sandbox for install.sh/uninstall.sh: `makeFakeRepo` plus `makeStubBin` ahead of
    /// the real tools on PATH, fake RESOLUTE_APP_DIR/RESOLUTE_BIN_DIR folders, the fake
    /// bundle ID, and short timeouts, all as an environment ready for `run(_:_:env:)`.
    private static func makeSandbox(
        in folder: URL, running: Bool, quitsWhenAsked: Bool = true, version: String = "0.3.0"
    ) throws -> (repo: URL, appDir: URL, binDir: URL, callsLog: URL, env: [String: String]) {
        let repo = try makeFakeRepo(in: folder, version: version)
        let stubBin = try makeStubBin(in: folder)
        let appDir = folder.appending(path: "Applications")
        let binDir = folder.appending(path: "bin")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let callsLog = folder.appending(path: "calls.log")
        let runningFile = folder.appending(path: "running")
        let quitsFile = folder.appending(path: "quits")
        try Data().write(to: callsLog)
        try Data((running ? "true" : "false").utf8).write(to: runningFile)
        try Data((quitsWhenAsked ? "yes" : "no").utf8).write(to: quitsFile)

        var path = stubBin.path
        if let existing = ProcessInfo.processInfo.environment["PATH"] { path += ":\(existing)" }
        let env = [
            "PATH": path,
            "CALLS_LOG": callsLog.path,
            "RUNNING_FILE": runningFile.path,
            "QUITS_FILE": quitsFile.path,
            "RESOLUTE_APP_DIR": appDir.path,
            "RESOLUTE_BIN_DIR": binDir.path,
            "RESOLUTE_BUNDLE_ID": fakeBundleID,
            "RESOLUTE_QUIT_TIMEOUT": "1",
            "RESOLUTE_QUIT_POLL_INTERVAL": "0.05",
            "RESOLUTE_UNREGISTER_TIMEOUT": "2",
        ]
        return (repo, appDir, binDir, callsLog, env)
    }

    /// The non-blank lines `makeStubBin`'s stand-ins and the fake Resolute binary
    /// recorded, in the order they were called.
    private static func calls(_ log: URL) throws -> [String] {
        try String(contentsOf: log, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    @Test func installCopiesLinksAndOpensTheAppLastAfterTheQuitCheck() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sandbox = try Self.makeSandbox(in: folder, running: false)

        let result = try Self.run("/bin/bash", [sandbox.repo.appending(path: "Scripts/install.sh").path], env: sandbox.env)
        #expect(result.status == 0, "\(result.output)")

        let installedApp = sandbox.appDir.appending(path: "Resolute.app")
        #expect(FileManager.default.fileExists(atPath: installedApp.appending(path: "Contents/Info.plist").path))
        let link = sandbox.binDir.appending(path: "resolute")
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        #expect(target == installedApp.appending(path: "Contents/Helpers/resolute").path)

        let calls = try Self.calls(sandbox.callsLog)
        let quitCheckIndex = try #require(calls.firstIndex { $0.hasPrefix("osascript") })
        let openIndex = try #require(calls.firstIndex { $0.hasPrefix("open ") })
        #expect(quitCheckIndex < openIndex)
        #expect(openIndex == calls.count - 1, "open should be the last call: \(calls)")
        #expect(calls[openIndex].contains(installedApp.path))
    }

    @Test func installReplacesAnExistingCopy() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sandbox = try Self.makeSandbox(in: folder, running: false)

        let installedApp = sandbox.appDir.appending(path: "Resolute.app")
        try FileManager.default.createDirectory(at: installedApp.appending(path: "Contents"), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: installedApp.appending(path: "Contents/marker"))

        let result = try Self.run("/bin/bash", [sandbox.repo.appending(path: "Scripts/install.sh").path], env: sandbox.env)
        #expect(result.status == 0, "\(result.output)")

        #expect(!FileManager.default.fileExists(atPath: installedApp.appending(path: "Contents/marker").path))
        let plist = try String(contentsOf: installedApp.appending(path: "Contents/Info.plist"), encoding: .utf8)
        #expect(plist.contains("0.3.0"))
    }

    @Test func installStopsAndChangesNothingWhenTheAppNeverQuits() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sandbox = try Self.makeSandbox(in: folder, running: true, quitsWhenAsked: false)

        let installedApp = sandbox.appDir.appending(path: "Resolute.app")
        try FileManager.default.createDirectory(at: installedApp.appending(path: "Contents"), withIntermediateDirectories: true)
        try Data("previous".utf8).write(to: installedApp.appending(path: "Contents/marker"))

        let result = try Self.run("/bin/bash", [sandbox.repo.appending(path: "Scripts/install.sh").path], env: sandbox.env)
        #expect(result.status == 1)
        #expect(result.output.contains("Resolute is still running"))

        #expect(try String(contentsOf: installedApp.appending(path: "Contents/marker"), encoding: .utf8) == "previous")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: sandbox.binDir.appending(path: "resolute").path)) == nil)
        let calls = try Self.calls(sandbox.callsLog)
        #expect(!calls.contains { $0.hasPrefix("open ") })
    }

    @Test func uninstallQuitsTurnsOffLoginItemThenRemovesThenDeletesPreferences() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sandbox = try Self.makeSandbox(in: folder, running: true, quitsWhenAsked: true)

        let installedApp = sandbox.appDir.appending(path: "Resolute.app")
        try FileManager.default.copyItem(at: sandbox.repo.appending(path: "dist/Resolute.app"), to: installedApp)
        let link = sandbox.binDir.appending(path: "resolute")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: installedApp.appending(path: "Contents/Helpers/resolute"))

        let result = try Self.run("/bin/bash", [sandbox.repo.appending(path: "Scripts/uninstall.sh").path], env: sandbox.env)
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("Removed Resolute."))

        #expect(!FileManager.default.fileExists(atPath: installedApp.path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == nil)

        let calls = try Self.calls(sandbox.callsLog)
        let quitIndex = try #require(calls.firstIndex { $0.hasPrefix("osascript") && $0.contains("to quit") })
        let loginItemIndex = try #require(calls.firstIndex { $0.hasPrefix("Resolute --unregister-login-item") })
        let defaultsIndex = try #require(calls.firstIndex { $0.hasPrefix("defaults delete") })
        #expect(quitIndex < loginItemIndex)
        #expect(loginItemIndex < defaultsIndex)
        #expect(calls[defaultsIndex].contains(Self.fakeBundleID))
    }

    @Test func uninstallLeavesAResoluteLinkThatPointsSomewhereElse() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sandbox = try Self.makeSandbox(in: folder, running: false)

        let installedApp = sandbox.appDir.appending(path: "Resolute.app")
        try FileManager.default.copyItem(at: sandbox.repo.appending(path: "dist/Resolute.app"), to: installedApp)
        let link = sandbox.binDir.appending(path: "resolute")
        let elsewhere = folder.appending(path: "elsewhere")
        try Data("elsewhere".utf8).write(to: elsewhere)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)

        let result = try Self.run("/bin/bash", [sandbox.repo.appending(path: "Scripts/uninstall.sh").path], env: sandbox.env)
        #expect(result.status == 0, "\(result.output)")

        #expect(!FileManager.default.fileExists(atPath: installedApp.path))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == elsewhere.path)
    }

    @Test func uninstallOfAnAppThatIsNotInstalledStillSucceeds() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "ScriptTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sandbox = try Self.makeSandbox(in: folder, running: false)

        let result = try Self.run("/bin/bash", [sandbox.repo.appending(path: "Scripts/uninstall.sh").path], env: sandbox.env)
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("Removed Resolute."))

        let calls = try Self.calls(sandbox.callsLog)
        #expect(!calls.contains { $0.hasPrefix("Resolute --unregister-login-item") })
    }
}
