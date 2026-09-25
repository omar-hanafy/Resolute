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

    static let shellcheckPath = "/opt/homebrew/bin/shellcheck"
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
        let status = Int32(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
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

    // MARK: - quit_and_wait

    @Test func quitAndWaitSucceedsAtOnceWhenNothingIsRunning() throws {
        let stub = """
        osascript() {
          if [[ "$2" == *"tell application"* ]]; then return 0; fi
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
          if [[ "$2" == *"tell application"* ]]; then return 0; fi
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
          if [[ "$2" == *"tell application"* ]]; then return 0; fi
          echo "true"
        }
        """
        let status = try Self.quitAndWaitStatus(
            stub: stub,
            env: ["RESOLUTE_QUIT_TIMEOUT": "1", "RESOLUTE_QUIT_POLL_INTERVAL": "0.2"]
        )
        #expect(status == 1)
    }
}
