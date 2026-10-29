import ArgumentParser
import Darwin
import Foundation
import ResoluteKit
import Testing
@testable import resolute

/// When the app is running, `set` asks the person at the display to keep a hidden mode, in
/// the app's dialog, instead of the terminal. It still switches and recovers by itself.
@Suite struct AgentConfirmationTests {
    /// 2560 × 1440 is hidden on the sample monitor, which is at 1920 × 1080.
    let arguments = ["set", "2560x1440", "--allow-hidden", "-d", "dell"]
    let trying = "Trying 2560 × 1440 on DELL P2419H (hidden mode)."
    let waiting = "Waiting up to 15 s for someone at the display to keep it…"
    let documentedKeys: Set<String> = ["display", "mode", "hidden", "result", "keptBy", "until", "reason", "restored"]

    /// A context with no terminal unless there is one, a known requester, and short
    /// waits for a display to come back.
    private func context(
        _ transcript: Transcript, on service: any DisplayControlling, app: AgentChannelClient?, terminal: Bool = false,
        prompts: Prompts = Prompts(answer: .revert)
    ) -> CommandContext {
        var context = transcript.context(service: service, isRoot: false, decision: .revert)
        context.app = app
        context.canConfirmHiddenMode = terminal
        context.confirmHiddenMode = { prompts.ask() }
        context.requester = { Requester(agent: "Claude Code", app: "Terminal") }
        context.restoreTimeout = 0.2
        context.restorePollInterval = 0.001
        return context
    }

    func object(_ json: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    // MARK: Kept

    @Test func keepsWhatAPersonKeepsAtTheDisplayUntilLogout() async throws {
        let service = FakeDisplays([Sample.monitor])
        let app = try FakeApp { _ in .keptByPerson }
        defer { app.close() }
        let transcript = Transcript()
        let prompts = Prompts(answer: .revert)
        let result = await run(arguments, in: context(transcript, on: service, app: app.client, prompts: prompts))
        #expect(result.code == 0)
        #expect(transcript.output == "DELL P2419H: 2560 × 1440 @ 30 Hz, mode 91, hidden (until you log out)")
        #expect(transcript.errors == trying + "\n" + waiting)
        // Tried for the session, and kept that way: never saved.
        #expect(service.changes == [.init(displayID: 2, modeID: 91, scope: .session)])
        #expect(prompts.count == 0)
    }

    /// The app gets what its dialog says: who asked, from where, and what comes back.
    @Test func asksTheDialogWhileTheModeIsOnTrial() async throws {
        let service = FakeDisplays([Sample.monitor])
        let changesWhenAsked = Recorder<[FakeDisplays.Change]>()
        let app = try FakeApp { _ in
            changesWhenAsked.record(service.changes)
            return .keptByPerson
        }
        defer { app.close() }
        _ = await run(arguments, in: context(Transcript(), on: service, app: app.client))
        let request = try #require(app.log.requests.first)
        #expect(request.display == .init(name: "DELL P2419H", id: 2, vendorID: 0x10AC, productID: 0xA0C4, serialNumber: 0))
        #expect(request.mode == "2560 × 1440")
        #expect(request.modeID == 91)
        #expect(request.previousMode == "1920 × 1080")
        #expect(request.previousModeID == 1)
        #expect(request.trialSeconds == 15)
        #expect(request.requester == Requester(agent: "Claude Code", app: "Terminal"))
        #expect(changesWhenAsked.values == [[.init(displayID: 2, modeID: 91, scope: .session)]])
    }

    @Test func reportsAKeptModeAsJSON() async throws {
        let service = FakeDisplays([Sample.monitor])
        let app = try FakeApp { _ in .keptByPerson }
        defer { app.close() }
        let transcript = Transcript()
        let result = await run(arguments + ["--json"], in: context(transcript, on: service, app: app.client))
        #expect(result.code == 0)
        let summary = try object(transcript.output)
        #expect(Set(summary.keys) == documentedKeys)
        #expect(summary["display"] as? String == "DELL P2419H")
        #expect(summary["mode"] as? String == "2560x1440")
        #expect(summary["hidden"] as? Bool == true)
        #expect(summary["result"] as? String == "kept")
        #expect(summary["keptBy"] as? String == "person")
        #expect(summary["until"] as? String == "logout")
        #expect(summary["reason"] is NSNull)
        #expect(summary["restored"] is NSNull)
        // What the command is doing goes to standard error, leaving the JSON alone.
        #expect(transcript.errors == trying + "\n" + waiting)
    }

    // MARK: Reverted

    @Test func revertsWhenThePersonRevertsAtTheDisplay() async throws {
        let service = FakeDisplays([Sample.monitor])
        let app = try FakeApp { _ in .revertedByPerson }
        defer { app.close() }
        let transcript = Transcript()
        let result = await run(arguments, in: context(transcript, on: service, app: app.client))
        #expect(result.code == 0)
        #expect(transcript.output == "Kept the previous mode: 1920 × 1080 @ 60 Hz, mode 1 (reverted by person).")
        #expect(service.changes == [
            .init(displayID: 2, modeID: 91, scope: .session), .init(displayID: 2, modeID: 1, scope: .session),
        ])
    }

    @Test(arguments: [
        (ConfirmHiddenModeResponse.revertedByPerson, "reverted by person", HistoryEntry.RevertReason.declined),
        (.noAnswer(after: 15), "no answer in 15 s", .noAnswer),
        (.reverted(because: "the display is asleep"), "the display is asleep", .unspecified),
    ])
    func saysWhyAModeWasRevertedInJSON(
        response: ConfirmHiddenModeResponse, reason: String, recorded: HistoryEntry.RevertReason
    ) async throws {
        let service = FakeDisplays([Sample.monitor])
        let app = try FakeApp { _ in response }
        defer { app.close() }
        let transcript = Transcript()
        let result = await run(arguments + ["--json"], in: context(transcript, on: service, app: app.client))
        #expect(result.code == 0)
        let summary = try object(transcript.output)
        #expect(Set(summary.keys) == documentedKeys)
        #expect(summary["result"] as? String == "reverted")
        #expect(summary["reason"] as? String == reason)
        #expect(summary["restored"] as? String == "1920x1080")
        #expect(summary["keptBy"] is NSNull)
        #expect(summary["until"] is NSNull)
        #expect(service.changes.last == .init(displayID: 2, modeID: 1, scope: .session))
        // History says why, and who asked.
        let entries = try HistoryStore(locations: transcript.support).entries()
        #expect(entries.map(\.outcome) == [.reverted(recorded)])
        #expect(entries.first?.source == .agent(name: "Claude Code", app: "Terminal"))
    }

    /// A dialog that never answers can't hold the mode: the command stops waiting after the
    /// trial and a little more, puts the previous mode back, and closes the dialog.
    @Test func stopsWaitingForADialogThatNeverAnswers() async throws {
        let service = FakeDisplays([Sample.monitor])
        let app = try FakeApp(trialSeconds: 1) { _ in await waitUntilCancelled() }
        defer { app.close() }
        let transcript = Transcript()
        let started = ContinuousClock.now
        let result = await run(arguments + ["--json"], in: context(transcript, on: service, app: app.client))
        #expect(result.code == 0)
        // The reason and the dismissal below show the command's own deadline ended the wait;
        // this only catches a wait far beyond it, since a busy runner can be seconds late.
        #expect(ContinuousClock.now - started < .seconds(30))
        #expect(transcript.errors.hasSuffix("Waiting up to 1 s for someone at the display to keep it…"))
        let summary = try object(transcript.output)
        #expect(summary["result"] as? String == "reverted")
        #expect(summary["reason"] as? String == "no answer in 1 s")
        #expect(service.changes == [
            .init(displayID: 2, modeID: 91, scope: .session), .init(displayID: 2, modeID: 1, scope: .session),
        ])
        #expect(await eventually { app.log.abandonments == [.dismissed(.stoppedWaiting)] && app.log.closedDialogs == 1 })
    }

    /// Ctrl-C, a hangup or a request to terminate undoes the trial, as at the terminal
    /// prompt, and the app closes its dialog.
    @Test func revertsAndClosesTheDialogAtControlC() async throws {
        let service = FakeDisplays([Sample.monitor])
        let interrupts = Interrupts()
        let app = try FakeApp { _ in
            interrupts.interrupt()
            return await waitUntilCancelled()
        }
        defer { app.close() }
        let transcript = Transcript()
        var interruptible = context(transcript, on: service, app: app.client)
        interruptible.interrupts = interrupts
        let result = await run(arguments, in: interruptible)
        #expect(result.code == 0)
        #expect(transcript.output == "Kept the previous mode: 1920 × 1080 @ 60 Hz, mode 1 (interrupted).")
        #expect(service.changes == [
            .init(displayID: 2, modeID: 91, scope: .session), .init(displayID: 2, modeID: 1, scope: .session),
        ])
        #expect(await eventually { app.log.abandonments == [.dismissed(.interrupted)] && app.log.closedDialogs == 1 })
    }

    /// The app quitting while its dialog is up is no answer.
    @Test func revertsWhenTheAppGoesAwayWithoutAnAnswer() async throws {
        let service = FakeDisplays([Sample.monitor])
        let quit = Recorder<AgentChannelServer>()
        let app = try FakeApp { _ in
            quit.values.first?.stop()
            return await waitUntilCancelled()
        }
        quit.record(app.server)
        defer { app.close() }
        let transcript = Transcript()
        let result = await run(arguments + ["--json"], in: context(transcript, on: service, app: app.client))
        #expect(result.code == 0)
        let summary = try object(transcript.output)
        #expect(summary["result"] as? String == "reverted")
        #expect(summary["reason"] as? String == "the Resolute app closed without an answer")
        #expect(service.changes.last == .init(displayID: 2, modeID: 1, scope: .session))
    }

    /// Only a person can keep a hidden mode: a keep from anything else listening at the
    /// socket is not believed.
    @Test func believesOnlyAPersonsKeep() async throws {
        let service = FakeDisplays([Sample.monitor])
        let forger = try ForgingApp()
        defer { forger.close() }
        let transcript = Transcript()
        let result = await run(arguments + ["--json"], in: context(transcript, on: service, app: forger.client))
        #expect(result.code == 0)
        let summary = try object(transcript.output)
        #expect(summary["result"] as? String == "reverted")
        #expect(summary["keptBy"] is NSNull)
        #expect(summary["reason"] as? String == "the Resolute app's answer could not be read")
        #expect(service.changes == [
            .init(displayID: 2, modeID: 91, scope: .session), .init(displayID: 2, modeID: 1, scope: .session),
        ])
    }

    /// A display that drops while the dialog is up is waited for, as at the terminal.
    @Test func waitsForADisplayThatDropsDuringTheDialog() async throws {
        let base = FakeDisplays([Sample.monitor])
        let service = ReconnectingDisplays(base, displayID: 2)
        let app = try FakeApp { _ in
            service.disconnect(forSnapshots: 3)
            return .revertedByPerson
        }
        defer { app.close() }
        let transcript = Transcript()
        let result = await run(arguments + ["--json"], in: context(transcript, on: service, app: app.client))
        #expect(result.code == 0)
        let summary = try object(transcript.output)
        #expect(summary["result"] as? String == "reverted")
        #expect(summary["reason"] as? String == "reverted by person")
        #expect(summary["restored"] as? String == "1920x1080")
        #expect(transcript.errors == [
            trying, waiting, "DELL P2419H went away. Waiting for it to come back to restore the previous mode…",
            "DELL P2419H is back. Restored the previous mode: 1920 × 1080 @ 60 Hz, mode 1.",
        ].joined(separator: "\n"))
        #expect(base.changes == [
            .init(displayID: 2, modeID: 91, scope: .session), .init(displayID: 2, modeID: 1, scope: .session),
        ])
    }

    // MARK: Without the app

    @Test func asksInTheTerminalWhenTheAppIsNotRunning() async throws {
        let service = FakeDisplays([Sample.monitor])
        let nothing = AgentChannelClient(socket: shortFolder().appending(path: "agent.sock"))
        let prompts = Prompts(answer: .keep)
        let transcript = Transcript()
        let result = await run(arguments, in: context(transcript, on: service, app: nothing, terminal: true, prompts: prompts))
        #expect(result.code == 0)
        #expect(prompts.count == 1)
        #expect(transcript.errors.isEmpty)
        #expect(transcript.output == "DELL P2419H: 2560 × 1440 @ 30 Hz, mode 91, hidden (until you log out)")
        #expect(service.changes == [.init(displayID: 2, modeID: 91, scope: .session)])
    }

    /// The terminal's answer is the person's own: the text says no more than before.
    @Test func reportsATerminalRevertAsBefore() async throws {
        let nothing = AgentChannelClient(socket: shortFolder().appending(path: "agent.sock"))
        let text = Transcript()
        _ = await run(arguments, in: context(text, on: FakeDisplays([Sample.monitor]), app: nothing, terminal: true))
        #expect(text.output == "Kept the previous mode: 1920 × 1080 @ 60 Hz, mode 1.")
        let json = Transcript()
        _ = await run(arguments + ["--json"], in: context(json, on: FakeDisplays([Sample.monitor]), app: nothing, terminal: true))
        let summary = try object(json.output)
        #expect(summary["result"] as? String == "reverted")
        #expect(summary["reason"] as? String == "not kept")
    }

    /// With no app and no terminal, nobody could keep the mode, so nothing changes.
    /// The person's Don't Allow in Resolute holds in a terminal too: nothing switches.
    @Test func changesNothingWhenThePersonDoesNotAllowIt() async throws {
        let service = FakeDisplays([Sample.monitor])
        let app = try FakeApp(refusal: "Resolute’s Settings don’t allow hidden modes asked for from the command line.") { _ in .keptByPerson }
        defer { app.close() }
        let transcript = Transcript()
        let result = await run(arguments, in: context(transcript, on: service, app: app.client, terminal: true))
        #expect(result.code == 64)
        #expect(result.message?.contains("don’t allow hidden modes asked for from the command line. No display settings changed.") == true)
        #expect(service.changes.isEmpty)
        #expect(app.log.requests.isEmpty)
    }

    @Test func changesNothingWithNeitherTheAppNorATerminal() async {
        let service = FakeDisplays([Sample.monitor])
        let nothing = AgentChannelClient(socket: shortFolder().appending(path: "agent.sock"))
        let prompts = Prompts(answer: .keep)
        let result = await run(arguments + ["--json"], in: context(Transcript(), on: service, app: nothing, prompts: prompts))
        #expect(result.code == 64)
        #expect(result.message?.hasPrefix(
            "Error: A person must keep a hidden mode: open the Resolute app, which asks on the display, or run the command in an interactive terminal. No display settings changed."
        ) == true)
        #expect(service.changes.isEmpty)
        #expect(prompts.count == 0)
    }

    @Test func changesNothingWhenTheAppCannotAskAndThereIsNoTerminal() async throws {
        let service = FakeDisplays([Sample.monitor])
        let hung = try HungApp()
        defer { hung.close() }
        let result = await run(arguments, in: context(Transcript(), on: service, app: hung.client))
        #expect(result.code == 64)
        #expect(result.message?.hasPrefix(
            "Error: A person must keep a hidden mode, but the Resolute app can't ask right now: Resolute did not reply in time. "
                + "Run the command in an interactive terminal instead. No display settings changed."
        ) == true)
        #expect(service.changes.isEmpty)
    }

    @Test func asksInTheTerminalWhenTheAppCannotAsk() async throws {
        let service = FakeDisplays([Sample.monitor])
        let hung = try HungApp()
        defer { hung.close() }
        let prompts = Prompts(answer: .keep)
        let transcript = Transcript()
        let result = await run(arguments, in: context(transcript, on: service, app: hung.client, terminal: true, prompts: prompts))
        #expect(result.code == 0)
        #expect(transcript.errors == "The Resolute app can't ask right now: Resolute did not reply in time. Asking here instead.")
        #expect(prompts.count == 1)
        #expect(service.changes == [.init(displayID: 2, modeID: 91, scope: .session)])
    }

    // MARK: Listed modes and previews

    /// Only hidden modes need a person; the app is not even asked about others.
    @Test func reportsAListedModeAsAppliedWithoutAskingTheApp() async throws {
        let hung = try HungApp()
        defer { hung.close() }
        let saved = Transcript()
        let result = await run(["set", "1496x967", "--json"], in: context(saved, on: FakeDisplays([Sample.builtIn]), app: hung.client))
        #expect(result.code == 0)
        let summary = try object(saved.output)
        #expect(Set(summary.keys) == documentedKeys)
        #expect(summary["result"] as? String == "applied")
        #expect(summary["hidden"] as? Bool == false)
        #expect(summary["mode"] as? String == "1496x967")
        #expect(summary["until"] is NSNull)
        #expect(summary["keptBy"] is NSNull)
        let session = Transcript()
        _ = await run(["set", "1496x967", "--session", "--json"], in: context(session, on: FakeDisplays([Sample.builtIn]), app: hung.client))
        #expect(try object(session.output)["until"] as? String == "logout")
        #expect(try object(session.output)["result"] as? String == "applied")
        #expect(!hung.wasAsked)
    }

    @Test func reportsAPreviewAndAModeAlreadyInUseInJSON() async throws {
        let service = FakeDisplays([Sample.monitor])
        let hung = try HungApp()
        defer { hung.close() }
        let preview = Transcript()
        let result = await run(arguments + ["--dry-run", "--json"], in: context(preview, on: service, app: hung.client))
        #expect(result.code == 0)
        let previewed = try object(preview.output)
        #expect(Set(previewed.keys) == documentedKeys)
        #expect(previewed["result"] is NSNull)
        #expect(previewed["hidden"] as? Bool == true)
        #expect(service.changes.isEmpty)
        #expect(!hung.wasAsked)
        let current = Transcript()
        _ = await run(["set", "--mode-id", "1", "-d", "dell", "--json"], in: context(current, on: service, app: hung.client))
        #expect(try object(current.output)["result"] as? String == "applied")
        #expect(service.changes.isEmpty)
    }

    /// With standard output piped, as for --json, the terminal prompt must not land in the
    /// JSON.
    @Test func writesThePromptWhereItIsTold() throws {
        var input: [Int32] = [-1, -1]
        var output: [Int32] = [-1, -1]
        try #require(pipe(&input) == 0 && pipe(&output) == 0)
        defer { (input + output).forEach { close($0) } }
        let answer = Array("y\n".utf8)
        try #require(answer.withUnsafeBytes { write(input[1], $0.baseAddress, $0.count) } == answer.count)
        let decision = SetCommand.askToKeep(seconds: 1, input: input[0], output: output[1], isTerminal: true, interrupts: Interrupts())
        #expect(decision == .keep)
        var prompt = [UInt8](repeating: 0, count: 256)
        let count = read(output[0], &prompt, prompt.count)
        #expect(String(decoding: prompt.prefix(max(count, 0)), as: UTF8.self)
            == "Keep this display mode? Type y and press Return within 1 seconds; anything else reverts: ")
    }
}

// MARK: - Helpers

/// What the terminal prompt was asked, answering `answer` each time.
private final class Prompts: @unchecked Sendable {
    private let lock = NSLock()
    private let answer: ModeSwitcher.Decision
    private var asked = 0

    init(answer: ModeSwitcher.Decision) {
        self.answer = answer
    }

    var count: Int { lock.withLock { asked } }

    func ask() -> ModeSwitcher.Decision {
        lock.withLock { asked += 1 }
        return answer
    }
}

/// Values recorded from any thread.
private final class Recorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Value] = []

    var values: [Value] { lock.withLock { recorded } }

    func record(_ value: Value) {
        lock.withLock { recorded.append(value) }
    }
}

/// What the fake app's dialog saw.
private final class DialogLog: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [ConfirmHiddenModeRequest] = []
    private var ended: [AgentChannel.Abandonment] = []
    private var closed = 0

    var requests: [ConfirmHiddenModeRequest] { lock.withLock { received } }
    var abandonments: [AgentChannel.Abandonment] { lock.withLock { ended } }
    var closedDialogs: Int { lock.withLock { closed } }

    func receive(_ request: ConfirmHiddenModeRequest) { lock.withLock { received.append(request) } }
    func end(_ abandonment: AgentChannel.Abandonment) { lock.withLock { ended.append(abandonment) } }
    func closeDialog() { lock.withLock { closed += 1 } }
}

/// The app as `set` meets it: a real agent channel server on a short socket path, whose
/// dialog answers as the test says.
private final class FakeApp: Sendable {
    let folder: URL
    let server: AgentChannelServer
    let log: DialogLog

    init(
        trialSeconds: Int = 15, refusal: String? = nil,
        dialog: @escaping @Sendable (ConfirmHiddenModeRequest) async -> ConfirmHiddenModeResponse
    ) throws {
        let folder = shortFolder()
        let log = DialogLog()
        self.folder = folder
        self.log = log
        server = AgentChannelServer(
            socket: folder.appending(path: "agent.sock"), appVersion: "test", trialSeconds: { trialSeconds },
            refusal: { refusal },
            handler: { request in
                log.receive(request)
                let response = await dialog(request)
                if Task.isCancelled { log.closeDialog() }
                return response
            },
            abandoned: { _, abandonment in log.end(abandonment) }
        )
        try server.start()
    }

    /// What `set` uses to reach it. It waits a fifth of a second past the trial.
    var client: AgentChannelClient {
        AgentChannelClient(socket: server.socket, answerGrace: .milliseconds(200))
    }

    func close() {
        server.stop()
        try? FileManager.default.removeItem(at: folder)
    }
}

/// An app that hangs: its socket takes connections but nothing ever replies.
private final class HungApp: Sendable {
    let folder: URL
    private let descriptor: Int32

    init() throws {
        folder = shortFolder()
        descriptor = try listen(at: folder.appending(path: "agent.sock"))
        // Accepting is how a test sees whether anyone came; the socket must not wait.
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
    }

    var client: AgentChannelClient {
        AgentChannelClient(socket: folder.appending(path: "agent.sock"), responseTimeout: .milliseconds(200))
    }

    /// Whether anyone connected.
    var wasAsked: Bool {
        let connection = accept(descriptor, nil, nil)
        guard connection >= 0 else { return false }
        Darwin.close(connection)
        return true
    }

    func close() {
        Darwin.close(descriptor)
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Something other than Resolute's dialog listening at the socket: it says hello like the
/// app, then answers keep without a person.
private final class ForgingApp: Sendable {
    let folder: URL
    private let descriptor: Int32

    init() throws {
        folder = shortFolder()
        let descriptor = try listen(at: folder.appending(path: "agent.sock"))
        self.descriptor = descriptor
        Thread {
            reply(on: descriptor, with: #"{"version":1,"type":"ready","app":"forged","trialSeconds":15}"#)
            reply(on: descriptor, with: #"{"version":1,"type":"answer","answer":"keep","by":null,"reason":null}"#)
        }.start()
    }

    var client: AgentChannelClient {
        AgentChannelClient(socket: folder.appending(path: "agent.sock"))
    }

    func close() {
        // Ends a wait in accept, if the command never came.
        Darwin.close(descriptor)
        try? FileManager.default.removeItem(at: folder)
    }
}

/// Accepts one connection on `listening`, reads its line and answers `line`.
private func reply(on listening: Int32, with line: String) {
    let connection = accept(listening, nil, nil)
    guard connection >= 0 else { return }
    defer { close(connection) }
    var byte: UInt8 = 0
    while read(connection, &byte, 1) == 1, byte != UInt8(ascii: "\n") {}
    let bytes = Array((line + "\n").utf8)
    _ = bytes.withUnsafeBytes { write(connection, $0.baseAddress, $0.count) }
}

/// A listening socket at `url`, in a folder only this user can open.
private func listen(at url: URL) throws -> Int32 {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
    )
    let path = Array(url.path(percentEncoded: false).utf8)
    var address = sockaddr_un()
    try #require(path.count < MemoryLayout.size(ofValue: address.sun_path))
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    try #require(descriptor >= 0)
    var one: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
    let bound = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    guard bound == 0, Darwin.listen(descriptor, 4) == 0 else {
        close(descriptor)
        throw SocketSetupError(path: url.path(percentEncoded: false))
    }
    return descriptor
}

private struct SocketSetupError: Error {
    var path: String
}

/// A fresh folder for a socket, not yet created. A socket address holds 103 bytes of path,
/// so it goes in /tmp when the temporary folder's path is long.
private func shortFolder() -> URL {
    let name = "r-" + UUID().uuidString.prefix(8)
    let temporary = FileManager.default.temporaryDirectory
    let fits = temporary.path(percentEncoded: false).utf8.count + name.count + "/agent.sock".count < 100
    return (fits ? temporary : URL(filePath: "/tmp", directoryHint: .isDirectory)).appending(path: name, directoryHint: .isDirectory)
}

/// A dialog nobody answers: it closes only when cancelled.
private func waitUntilCancelled() async -> ConfirmHiddenModeResponse {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
    }
    return .revertedByPerson
}

private func eventually(within timeout: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

/// Runs `arguments` as `ResoluteCommand.execute` does, on a thread of its own: `set` blocks
/// while the dialog is up, and must not hold a thread the fake app's dialog needs.
private func run(_ arguments: [String], in context: CommandContext) async -> (message: String?, code: Int32) {
    await withCheckedContinuation { continuation in
        Thread {
            continuation.resume(returning: runNow(arguments, in: context))
        }.start()
    }
}

private func runNow(_ arguments: [String], in context: CommandContext) -> (message: String?, code: Int32) {
    do {
        guard let command = try ResoluteCommand.parseAsRoot(arguments) as? SetCommand else {
            return ("Not a set command: \(arguments)", 1)
        }
        try command.run(in: context)
        return (nil, 0)
    } catch ResoluteError.usage(let message) {
        return (ResoluteCommand.usageMessage(message, for: SetCommand.self), ExitCode.validationFailure.rawValue)
    } catch {
        return (ResoluteCommand.fullMessage(for: error), ResoluteCommand.exitCode(for: error).rawValue)
    }
}
