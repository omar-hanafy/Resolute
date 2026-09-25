import Foundation

/// Runs a shell script, possibly with administrator rights.
public protocol CommandRunning: Sendable {
    func run(_ script: String) async throws
}

/// Runs scripts with `/bin/sh` as the current user (or as root under `sudo`).
public struct ShellCommandRunner: CommandRunning {
    public init() {}

    public func run(_ script: String) async throws {
        try await Task.detached {
            try Subprocess.run("/bin/sh", arguments: ["-c", script])
        }.value
    }
}

/// Runs scripts as root after macOS asks for an administrator's password.
public struct AdminCommandRunner: CommandRunning {
    public init() {}

    public func run(_ script: String) async throws {
        let source = AppleScript.doShellScript(script, withAdministratorPrivileges: true)
        do {
            try await Task.detached {
                try Subprocess.run("/usr/bin/osascript", arguments: ["-e", source])
            }.value
        } catch ResoluteError.commandFailed(_, let message) where Self.isCancellation(message) {
            throw ResoluteError.cancelled
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
    /// A `do shell script` statement that runs `script`.
    public static func doShellScript(_ script: String, withAdministratorPrivileges: Bool) -> String {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\"" + (withAdministratorPrivileges ? " with administrator privileges" : "")
    }
}

/// Runs a program and waits for it.
enum Subprocess {
    /// Throws `ResoluteError.commandFailed` with the program's error output when it fails.
    static func run(_ executable: String, arguments: [String]) throws {
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
