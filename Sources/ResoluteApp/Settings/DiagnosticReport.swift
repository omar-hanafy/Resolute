import Foundation
import ResoluteKit

/// Settings › Command Line & Agents › Diagnostic report: "Runs resolute doctor: versions,
/// displays, modes and overrides, ready for a bug report." `resolute doctor` only reads, so
/// it runs without asking; Copy Report puts what it prints on the clipboard.
enum DiagnosticReport {
    /// The command to run: the app's own, else the one built next to the app's executable
    /// (`swift build` puts both in one folder).
    static func command(bundle: Bundle = .main, fileManager: FileManager = .default) -> URL? {
        var candidates: [URL] = []
        if bundle.bundleURL.pathExtension == "app" {
            candidates.append(bundle.bundleURL.appending(path: CommandLineTool.helperPath, directoryHint: .notDirectory))
        }
        if let executable = bundle.executableURL {
            candidates.append(executable.deletingLastPathComponent().appending(path: "resolute", directoryHint: .notDirectory))
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path(percentEncoded: false)) }
    }

    /// What `resolute doctor` prints.
    static func run(_ command: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            // Waits on a thread of its own, off the Swift concurrency pool.
            Thread.detachNewThread {
                continuation.resume(with: Result { try runAndWait(command, arguments: ["doctor"]) })
            }
        }
    }

    /// Copy Report: runs `resolute doctor` and copies its report.
    @MainActor
    static func copy(showError: @escaping @MainActor (any Error, String) -> Void) async {
        guard let command = command() else {
            showError(ResoluteError.commandFailed(status: 1, message: "The resolute command is missing from Resolute.app."), "The report could not be made")
            return
        }
        do {
            Clipboard.copy(try await run(command))
        } catch {
            showError(error, "The report could not be made")
        }
    }

    private static func runAndWait(_ command: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = command
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // The error output is read on another thread while this one reads the report, so
        // neither pipe can fill up and stall the command.
        let errorOutput = ErrorOutput()
        let errorRead = DispatchGroup()
        errorRead.enter()
        DispatchQueue.global().async {
            errorOutput.data = errors.fileHandleForReading.readDataToEndOfFile()
            errorRead.leave()
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        errorRead.wait()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorOutput.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ResoluteError.commandFailed(status: process.terminationStatus, message: message)
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}

/// The command's error output, written by the thread that reads it before the group it
/// leaves lets the reader go on.
private final class ErrorOutput: @unchecked Sendable {
    var data = Data()
}
