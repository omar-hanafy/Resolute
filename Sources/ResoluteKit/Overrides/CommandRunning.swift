import Foundation

/// Runs a shell script, possibly with administrator rights.
public protocol CommandRunning: Sendable {
    func run(_ script: String) async throws
}

/// Runs scripts with `/bin/sh` as the current user (or as root under `sudo`).
public struct ShellCommandRunner: CommandRunning {
    public init() {}

    public func run(_ script: String) async throws {
        try await Subprocess.run("/bin/sh", arguments: ["-c", script])
    }
}

/// Runs scripts as root after macOS asks for an administrator's password.
public struct AdminCommandRunner: CommandRunning {
    /// What the password dialog says; without it macOS names osascript.
    public var prompt: String
    /// False only in tests, which run the same AppleScript without a password prompt.
    let withAdministratorPrivileges: Bool

    public init(prompt: String = "Resolute wants to change a display override in /Library/Displays.") {
        self.init(prompt: prompt, withAdministratorPrivileges: true)
    }

    init(prompt: String, withAdministratorPrivileges: Bool) {
        self.prompt = prompt
        self.withAdministratorPrivileges = withAdministratorPrivileges
    }

    public func run(_ script: String) async throws {
        let source = AppleScript.doShellScript(
            script, withAdministratorPrivileges: withAdministratorPrivileges, prompt: withAdministratorPrivileges ? prompt : nil
        )
        do {
            try await Subprocess.run("/usr/bin/osascript", arguments: ["-e", source])
        } catch ResoluteError.commandFailed(let status, let message) {
            if Self.isCancellation(message) { throw ResoluteError.cancelled }
            // osascript exits with 1 whatever the script did; the script's own status and
            // message are in its report.
            guard let failure = AppleScript.executionError(in: message) else {
                throw ResoluteError.commandFailed(status: status, message: message)
            }
            throw ResoluteError.commandFailed(status: failure.status, message: failure.message)
        }
    }

    /// True for osascript's report that the password prompt was cancelled:
    /// "execution error: User canceled. (-128)". The code always ends the message.
    static func isCancellation(_ message: String) -> Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("(-128)")
    }
}

/// Quoting for `/bin/sh`.
public enum Shell {
    /// Wraps `text` in single quotes, escaping any single quotes inside it.
    public static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

/// Building AppleScript source.
public enum AppleScript {
    /// A `do shell script` statement that runs `script`, with `prompt` as the password
    /// dialog's message.
    public static func doShellScript(_ script: String, withAdministratorPrivileges: Bool, prompt: String? = nil) -> String {
        var statement = "do shell script " + string(script)
        if let prompt { statement += " with prompt " + string(prompt) }
        if withAdministratorPrivileges { statement += " with administrator privileges" }
        return statement
    }

    /// A failed `do shell script`, as osascript reports it.
    public struct ExecutionError: Equatable, Sendable {
        public var message: String
        public var status: Int32
    }

    /// Reads osascript's report of a failed script, "0:47: execution error: <message>
    /// (<status>)", where the status is the script's exit status.
    public static func executionError(in report: String) -> ExecutionError? {
        let text = report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = text.range(of: "execution error: "), text.hasSuffix(")"),
              let open = text.range(of: " (", options: .backwards), open.lowerBound >= marker.upperBound,
              let status = Int32(text[open.upperBound..<text.index(before: text.endIndex)])
        else { return nil }
        return ExecutionError(message: String(text[marker.upperBound..<open.lowerBound]), status: status)
    }

    /// An AppleScript string literal.
    static func string(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

/// Runs a program and waits for it.
enum Subprocess {
    /// Waits on a thread of its own. A password prompt can stay open for minutes, and
    /// blocking one of the Swift concurrency pool's few threads that long starves other
    /// tasks and, once the pool is full, GCD's global queues too.
    static func run(_ executable: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Thread.detachNewThread {
                continuation.resume(with: Result { try runAndWait(executable, arguments: arguments) })
            }
        }
    }

    /// Throws `ResoluteError.commandFailed` with the program's error output when it fails.
    static func runAndWait(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let errorOutput = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ResoluteError.commandFailed(status: process.terminationStatus, message: message)
        }
    }
}
