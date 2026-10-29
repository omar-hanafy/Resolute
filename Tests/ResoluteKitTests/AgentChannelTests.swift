import Darwin
import Foundation
import Testing
@testable import ResoluteKit

// MARK: - Protocol

@Suite struct AgentProtocolTests {
    let request = ConfirmHiddenModeRequest(
        display: .init(name: "DELL U2723QE", id: 3, vendorID: 0x10AC, productID: 0x41BB, serialNumber: 0),
        mode: "2880 × 1620", modeID: 90, previousMode: "2560 × 1440", previousModeID: 1, trialSeconds: 15,
        requester: Requester(agent: "Claude Code", app: "Terminal")
    )

    func object(_ line: [UInt8]) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
    }

    @Test func writesEachMessageAsOneVersionedLine() throws {
        let messages: [any Encodable] = [
            AgentChannel.CommandMessage.hello, AgentChannel.CommandMessage.confirmHiddenMode(request),
            AgentChannel.CommandMessage.dismiss(.interrupted), AgentChannel.AppMessage.answer(.keptByPerson),
            AgentChannel.AppMessage.ready(.init(appVersion: "0.3.0", trialSeconds: 15)),
            AgentChannel.AppMessage.error(.init(.busy, "Try again shortly.")),
        ]
        for message in messages {
            let line = try AgentChannel.line(message)
            #expect(line.last == UInt8(ascii: "\n"))
            #expect(line.dropLast().contains(UInt8(ascii: "\n")) == false)
            let fields = try object(Array(line.dropLast()))
            #expect(fields["version"] as? Int == 1)
            #expect(fields["type"] is String)
        }
    }

    /// The fields the app reads to show the dialog on the right display.
    @Test func spellsOutTheRequestTheDialogShows() throws {
        let fields = try object(Array(try AgentChannel.line(AgentChannel.CommandMessage.confirmHiddenMode(request)).dropLast()))
        #expect(Set(fields.keys) == [
            "version", "type", "display", "mode", "modeID", "previousMode", "previousModeID", "trialSeconds", "requester",
        ])
        #expect(fields["type"] as? String == "confirmHiddenMode")
        #expect(fields["mode"] as? String == "2880 × 1620")
        #expect(fields["previousMode"] as? String == "2560 × 1440")
        #expect(fields["trialSeconds"] as? Int == 15)
        let display = try #require(fields["display"] as? [String: Any])
        #expect(Set(display.keys) == ["name", "id", "vendorID", "productID", "serialNumber"])
        #expect(display["name"] as? String == "DELL U2723QE")
        let requester = try #require(fields["requester"] as? [String: Any])
        #expect(requester["agent"] as? String == "Claude Code")
        #expect(requester["app"] as? String == "Terminal")
    }

    @Test func readsBackWhatItWrites() throws {
        let commands: [AgentChannel.CommandMessage] = [.hello, .confirmHiddenMode(request), .dismiss(.stoppedWaiting)]
        for message in commands {
            let line = try AgentChannel.line(message)
            #expect(try AgentChannel.decode(AgentChannel.CommandMessage.self, from: Array(line.dropLast())) == message)
        }
        let replies: [AgentChannel.AppMessage] = [
            .ready(.init(appVersion: "0.3.0", trialSeconds: 30)), .answer(.keptByPerson), .answer(.revertedByPerson),
            .answer(.noAnswer(after: 15)), .answer(.reverted(because: "The display is asleep.")),
            .error(.init(.badRequest, "The request is not valid.")),
        ]
        for message in replies {
            let line = try AgentChannel.line(message)
            #expect(try AgentChannel.decode(AgentChannel.AppMessage.self, from: Array(line.dropLast())) == message)
        }
    }

    @Test func saysWhyEachRevertHappened() {
        #expect(ConfirmHiddenModeResponse.revertedByPerson.reason == "reverted by person")
        #expect(ConfirmHiddenModeResponse.revertedByPerson.by == .person)
        #expect(ConfirmHiddenModeResponse.noAnswer(after: 15).reason == "no answer in 15 s")
        #expect(ConfirmHiddenModeResponse.noAnswer(after: 15).by == nil)
        #expect(ConfirmHiddenModeResponse.keptByPerson.reason == nil)
    }

    @Test(arguments: [0, 2])
    func namesAnotherVersionRatherThanGuessing(version: Int) {
        let json = Array(#"{"version":\#(version),"type":"confirmHiddenMode"}"#.utf8)
        #expect(throws: AgentChannelError.unsupportedVersion(version)) {
            try AgentChannel.decode(AgentChannel.CommandMessage.self, from: json)
        }
        #expect(throws: AgentChannelError.unsupportedVersion(version)) {
            try AgentChannel.decode(AgentChannel.AppMessage.self, from: json)
        }
    }

    @Test(arguments: [
        "not json", #"{"type":"hello"}"#, #"{"version":1,"type":"launch"}"#, #"{"version":1,"type":"confirmHiddenMode","mode":"x"}"#,
        #"{"version":"1","type":"hello"}"#,
    ])
    func refusesWhatItCannotRead(json: String) {
        do {
            let message = try AgentChannel.decode(AgentChannel.CommandMessage.self, from: Array(json.utf8))
            Issue.record("Read \(message) from \(json)")
        } catch AgentChannelError.unreadableMessage {
        } catch {
            Issue.record("Expected an unreadable message, got \(error)")
        }
    }

    /// Only a person can keep a hidden mode, so a keep from anyone else is not believed.
    @Test(arguments: [
        #"{"version":1,"type":"answer","answer":"keep","by":null,"reason":null}"#,
        #"{"version":1,"type":"answer","answer":"keep"}"#,
        #"{"version":1,"type":"answer","answer":"keep","by":"agent"}"#,
    ])
    func trustsAKeepOnlyFromAPerson(json: String) throws {
        #expect(throws: AgentChannelError.self) {
            try AgentChannel.decode(AgentChannel.AppMessage.self, from: Array(json.utf8))
        }
        let person = #"{"version":1,"type":"answer","answer":"keep","by":"person","reason":null}"#
        #expect(try AgentChannel.decode(AgentChannel.AppMessage.self, from: Array(person.utf8)) == .answer(.keptByPerson))
    }

    @Test func dismissesForAReasonItDoesNotKnow() throws {
        let json = #"{"version":1,"type":"dismiss","reason":"bored"}"#
        #expect(try AgentChannel.decode(AgentChannel.CommandMessage.self, from: Array(json.utf8)) == .dismiss(.stoppedWaiting))
    }

    @Test func refusesATrialLengthOutOfBounds() {
        let json = #"{"version":1,"type":"ready","app":"0.3.0","trialSeconds":0}"#
        #expect(throws: AgentChannelError.self) {
            try AgentChannel.decode(AgentChannel.AppMessage.self, from: Array(json.utf8))
        }
    }

    @Test func checksARequestBeforeItGoesOut() throws {
        try request.validate()
        var changed = request
        changed.trialSeconds = 0
        #expect(throws: AgentChannelError.invalidRequest("a trial of 0 seconds is out of bounds")) { try changed.validate() }
        changed.trialSeconds = 601
        #expect(throws: AgentChannelError.self) { try changed.validate() }
        changed = request
        changed.display.name = " "
        #expect(throws: AgentChannelError.invalidRequest("the display name is empty")) { try changed.validate() }
        changed = request
        changed.requester.agent = String(repeating: "a", count: 201)
        #expect(throws: AgentChannelError.self) { try changed.validate() }
    }

    @Test func splitsLinesAndRefusesOnesTooLong() {
        var buffer = LineBuffer(limit: 8)
        buffer.append(Array("abc\nde".utf8))
        #expect(buffer.next() == .line(Array("abc".utf8)))
        #expect(buffer.next() == .incomplete)
        buffer.append(Array("fghi".utf8))
        // "defghi" and its newline would be 7 bytes, still within the limit, but no newline came.
        #expect(buffer.next() == .incomplete)
        buffer.append(Array("jk".utf8))
        #expect(buffer.next() == .tooLong)
        var exact = LineBuffer(limit: 4)
        exact.append(Array("abc\n".utf8))
        #expect(exact.next() == .line(Array("abc".utf8)))
        exact.append(Array("abcd\n".utf8))
        #expect(exact.next() == .tooLong)
    }
}

/// The dialog says "DELL is trying 2880 × 1620 … switches back to 2560 × 1440".
@Suite struct HiddenModeWordingTests {
    func mode(_ id: Int32, _ width: Int, _ height: Int, scale: Int = 1, hz: Double = 60) -> DisplayMode {
        DisplayMode(
            modeID: id, width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale, refreshRate: hz,
            origin: .hidden
        )
    }

    @Test func namesTheSizeAlone() {
        #expect(ConfirmHiddenModeRequest.describe(mode(90, 2880, 1620), distinctFrom: mode(1, 2560, 1440)) == "2880 × 1620")
        #expect(ConfirmHiddenModeRequest.describe(mode(90, 2880, 1620), distinctFrom: nil) == "2880 × 1620")
    }

    /// The same size twice would read as no change at all.
    @Test func tellsModesOfTheSameSizeApart() {
        #expect(ConfirmHiddenModeRequest.describe(mode(90, 1920, 1080, hz: 75), distinctFrom: mode(1, 1920, 1080)) == "1920 × 1080 @ 75 Hz")
        #expect(ConfirmHiddenModeRequest.describe(mode(90, 1920, 1080, scale: 2), distinctFrom: mode(1, 1920, 1080)) == "1920 × 1080 HiDPI")
        #expect(ConfirmHiddenModeRequest.describe(mode(1, 1920, 1080), distinctFrom: mode(90, 1920, 1080, scale: 2)) == "1920 × 1080 1×")
    }

    @Test func fillsTheRequestFromTheDisplay() {
        let display = Display(
            id: 3, name: "DELL U2723QE", vendorID: 0x10AC, productID: 0x41BB, serialNumber: 7, currentModeID: 1,
            modes: [mode(1, 2560, 1440), mode(90, 2880, 1620)]
        )
        let request = ConfirmHiddenModeRequest(
            display: display, trying: display.modes[1], previous: display.currentMode, trialSeconds: 15,
            requester: Requester(agent: "Claude Code", app: "Terminal")
        )
        #expect(request.display == .init(name: "DELL U2723QE", id: 3, vendorID: 0x10AC, productID: 0x41BB, serialNumber: 7))
        #expect(request.mode == "2880 × 1620")
        #expect(request.modeID == 90)
        #expect(request.previousMode == "2560 × 1440")
        #expect(request.previousModeID == 1)
    }
}

// MARK: - Server and client

/// A real server and client on a real socket.
@Suite struct AgentChannelServerTests {
    let request = ConfirmHiddenModeRequest(
        display: .init(name: "DELL U2723QE", id: 3, vendorID: 0x10AC, productID: 0x41BB, serialNumber: 0),
        mode: "2880 × 1620", modeID: 90, previousMode: "2560 × 1440", previousModeID: 1, trialSeconds: 15,
        requester: Requester(agent: "Claude Code", app: "Terminal")
    )

    @Test func saysHelloWithItsVersionAndTrialLength() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = AgentChannelServer(socket: socket(in: folder), appVersion: "9.9", trialSeconds: { 20 }) { _ in .revertedByPerson }
        try server.start()
        defer { server.stop() }
        let status = await onOwnThread { client(folder).checkApp() }
        #expect(status == .ready(.init(appVersion: "9.9", trialSeconds: 20)))
    }

    /// The person doesn't allow hidden modes from the command line: `hello` says so, before
    /// the command changes anything.
    @Test func turnsTheCommandAwayWhenThePersonDoesNotAllowIt() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = AgentChannelServer(socket: socket(in: folder), refusal: { "Not from the command line." }) { _ in
            .keptByPerson
        }
        try server.start()
        defer { server.stop() }
        let status = await onOwnThread { client(folder).checkApp() }
        #expect(status == .refused("Not from the command line."))
    }

    /// A command that asks without `hello`, or after the setting changed, is turned away
    /// too, and no dialog is shown: the command puts the previous mode back itself.
    @Test func turnsARequestAwayWhenThePersonDoesNotAllowIt() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let server = AgentChannelServer(socket: socket(in: folder), refusal: { "Not from the command line." }) { request in
            log.received(request)
            return .keptByPerson
        }
        try server.start()
        defer { server.stop() }
        let request = request
        let progress = await onOwnThread {
            Result { try client(folder).ask(request).waitForAnswer(until: .now + .seconds(30)) }
        }
        #expect(try progress.get() == .failed(.refused(AgentChannel.Problem(.refused, "Not from the command line."))))
        #expect(log.requests.isEmpty)
    }

    @Test func handsTheRequestToTheDialogAndReturnsItsAnswer() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let server = AgentChannelServer(socket: socket(in: folder)) { request in
            log.received(request)
            return .keptByPerson
        }
        try server.start()
        defer { server.stop() }
        let request = request
        let progress = await onOwnThread {
            Result { try client(folder).ask(request).waitForAnswer(until: .now + .seconds(30)) }
        }
        #expect(try progress.get() == .answered(.keptByPerson))
        #expect(log.requests == [request])
    }

    @Test func keepsTheSocketToThePerson() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A folder others can read is made private.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let server = AgentChannelServer(socket: socket(in: folder)) { _ in .revertedByPerson }
        try server.start()
        defer { server.stop() }
        var info = stat()
        #expect(lstat(folder.path(percentEncoded: false), &info) == 0)
        #expect(info.st_mode & 0o777 == 0o700)
        #expect(lstat(socket(in: folder).path(percentEncoded: false), &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_mode & 0o777 == 0o600)
        #expect(info.st_uid == geteuid())
    }

    @Test func findsNoAppWhereNothingListens() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(await onOwnThread { client(folder).checkApp() } == .notRunning)
        // An app that crashed leaves its socket behind.
        try leaveStaleSocket(at: socket(in: folder))
        #expect(await onOwnThread { client(folder).checkApp() } == .notRunning)
        let request = request
        let asked = await onOwnThread { Result { _ = try client(folder).ask(request) } }
        #expect(throws: AgentChannelError.appNotRunning) { try asked.get() }
    }

    @Test func replacesASocketLeftBehind() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try leaveStaleSocket(at: socket(in: folder))
        let server = AgentChannelServer(socket: socket(in: folder)) { _ in .revertedByPerson }
        try server.start()
        defer { server.stop() }
        guard case .ready = await onOwnThread({ client(folder).checkApp() }) else {
            Issue.record("The server did not answer after replacing the old socket")
            return
        }
    }

    @Test func leavesAnotherListeningAppAlone() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = AgentChannelServer(socket: socket(in: folder), appVersion: "first") { _ in .revertedByPerson }
        try first.start()
        defer { first.stop() }
        let second = AgentChannelServer(socket: socket(in: folder), appVersion: "second") { _ in .revertedByPerson }
        #expect(throws: AgentChannelError.alreadyListening(socket(in: folder).path(percentEncoded: false))) { try second.start() }
        second.stop()
        #expect(await onOwnThread { client(folder).checkApp() } == .ready(.init(appVersion: "first", trialSeconds: 15)))
    }

    @Test func leavesAFileThatIsNotASocket() throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("notes".utf8).write(to: socket(in: folder))
        let server = AgentChannelServer(socket: socket(in: folder)) { _ in .revertedByPerson }
        #expect(throws: AgentChannelError.self) { try server.start() }
        #expect(try Data(contentsOf: socket(in: folder)) == Data("notes".utf8))
    }

    @Test func removesItsSocketWhenItStops() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = AgentChannelServer(socket: socket(in: folder)) { _ in .revertedByPerson }
        try server.start()
        #expect(server.isListening)
        server.stop()
        #expect(!server.isListening)
        #expect(!FileManager.default.fileExists(atPath: socket(in: folder).path(percentEncoded: false)))
        #expect(await onOwnThread { client(folder).checkApp() } == .notRunning)
        // It can listen again.
        try server.start()
        defer { server.stop() }
        #expect(server.isListening)
    }

    @Test func refusesAPathTooLongForASocket() {
        let long = URL(filePath: "/tmp/" + String(repeating: "a", count: 120) + "/agent.sock")
        let server = AgentChannelServer(socket: long) { _ in .revertedByPerson }
        #expect(throws: AgentChannelError.pathTooLong(long.path(percentEncoded: false))) { try server.start() }
        #expect(AgentChannelClient(socket: long).checkApp() != .notRunning)
    }

    /// Ctrl-C in the command closes the dialog.
    @Test func cancelsTheDialogWhenTheCommandDismissesIt() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let server = log.server(at: socket(in: folder)) { _ in await waitUntilCancelled() }
        try server.start()
        defer { server.stop() }
        let request = request
        let asked = await onOwnThread {
            Result {
                let pending = try client(folder).ask(request)
                guard blockUntil({ log.requests.count == 1 }) else { throw AgentChannelError.timedOut }
                pending.dismiss(.interrupted)
            }
        }
        try asked.get()
        #expect(await eventually { log.abandonments == [.dismissed(.interrupted)] && log.cancelledDialogs == 1 })
    }

    /// A command that is killed says nothing; its connection closing is enough.
    @Test func cancelsTheDialogWhenTheCommandDisappears() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let server = log.server(at: socket(in: folder)) { _ in await waitUntilCancelled() }
        try server.start()
        defer { server.stop() }
        let request = request
        let asked = await onOwnThread {
            Result {
                let pending = try client(folder).ask(request)
                guard blockUntil({ log.requests.count == 1 }) else { throw AgentChannelError.timedOut }
                pending.close()
            }
        }
        try asked.get()
        #expect(await eventually { log.abandonments == [.disconnected] && log.cancelledDialogs == 1 })
    }

    /// A dismissal can arrive in the same read as its request.
    @Test func dismissesARequestFollowedAtOnceByItsDismissal() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let server = log.server(at: socket(in: folder)) { _ in await waitUntilCancelled() }
        try server.start()
        defer { server.stop() }
        let descriptor = try UnixSocket.connect(to: socket(in: folder), until: .now + .seconds(2))
        defer { close(descriptor) }
        let both = try AgentChannel.line(AgentChannel.CommandMessage.confirmHiddenMode(request))
            + AgentChannel.line(AgentChannel.CommandMessage.dismiss(.interrupted))
        try UnixSocket.write(both, to: descriptor, until: .now + .seconds(2))
        #expect(await eventually { log.abandonments == [.dismissed(.interrupted)] })
    }

    @Test func dropsRequestsUnderWayWhenItStops() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let server = log.server(at: socket(in: folder)) { _ in await waitUntilCancelled() }
        try server.start()
        let request = request
        let progress = await onOwnThread {
            Result {
                let pending = try client(folder).ask(request)
                guard blockUntil({ log.requests.count == 1 }) else { throw AgentChannelError.timedOut }
                server.stop()
                return pending.waitForAnswer(until: .now + .seconds(30))
            }
        }
        #expect(try progress.get() == .failed(.closedWithoutAnswer))
        #expect(await eventually { log.cancelledDialogs == 1 })
    }

    /// A dialog that hangs can't hold the command forever: the server answers for it.
    @Test func answersForADialogThatTakesTooLong() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let limits = AgentChannelServer.Limits(answerGrace: .milliseconds(100))
        let server = log.server(at: socket(in: folder), limits: limits) { _ in await waitUntilCancelled() }
        try server.start()
        defer { server.stop() }
        var oneSecond = request
        oneSecond.trialSeconds = 1
        let short = oneSecond
        // Timed on its own thread: getting back to this task can take seconds on a busy runner.
        let (progress, took) = await onOwnThread {
            let started = ContinuousClock.now
            let progress = Result { try client(folder).ask(short).waitForAnswer(until: .now + .seconds(10)) }
            return (progress, ContinuousClock.now - started)
        }
        #expect(try progress.get() == .answered(.noAnswer(after: 1)))
        #expect(took < .seconds(5))
        #expect(await eventually { log.cancelledDialogs == 1 })
    }

    @Test func turnsAwayConnectionsBeyondItsLimit() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let server = log.server(at: socket(in: folder), limits: .init(maximumConnections: 1)) { _ in await waitUntilCancelled() }
        try server.start()
        defer { server.stop() }
        let request = request
        let status = await onOwnThread {
            Result {
                let pending = try client(folder).ask(request)
                defer { pending.close() }
                guard blockUntil({ log.requests.count == 1 }) else { throw AgentChannelError.timedOut }
                return client(folder).checkApp()
            }
        }
        #expect(try status.get() == .unavailable("Resolute is answering as many requests as it takes at once. Try again shortly."))
    }

    /// An app that turns a connection away closes it at once, and may do so before the
    /// command's message goes out; the reason it sent first still reaches the command.
    @Test func keepsTheReasonOfAnAppThatClosedFirst() throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let listening = try listenWithoutAnswering(at: socket(in: folder))
        defer { close(listening) }
        let descriptor = try UnixSocket.connect(to: socket(in: folder), until: .now + .seconds(2))
        defer { close(descriptor) }
        let app = accept(listening, nil, nil)
        try #require(app >= 0)
        let busy = AgentChannel.Problem(.busy, "Try again shortly.")
        try UnixSocket.write(try AgentChannel.line(AgentChannel.AppMessage.error(busy)), to: app, until: .now + .seconds(2))
        close(app)
        #expect(throws: AgentChannelError.refused(busy)) {
            try AgentChannelClient.send(.hello, on: descriptor, until: .now + .seconds(2))
        }
    }

    @Test func closesAConnectionThatNeverAsks() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = AgentChannelServer(socket: socket(in: folder), limits: .init(requestTimeout: .milliseconds(100))) { _ in
            .revertedByPerson
        }
        try server.start()
        defer { server.stop() }
        let descriptor = try UnixSocket.connect(to: socket(in: folder), until: .now + .seconds(2))
        defer { close(descriptor) }
        let closed = await onOwnThread { () -> Bool in
            var buffer = LineBuffer()
            guard UnixSocket.waitUntilReadable(descriptor, until: .now + .seconds(5)) else { return false }
            return UnixSocket.read(from: descriptor, into: &buffer) == .endOfFile
        }
        #expect(closed)
    }

    @Test(arguments: [
        (#"{"version":2,"type":"hello"}"#, AgentChannel.Problem.Code.unsupportedVersion),
        (#"{"version":1,"type":"launch"}"#, .badRequest),
        (#"{"version":1,"type":"confirmHiddenMode","display":{"name":"","id":1,"vendorID":1,"productID":1,"serialNumber":0},"mode":"1 × 1","modeID":1,"trialSeconds":15,"requester":{}}"#, .badRequest),
    ])
    func explainsARequestItTurnsDown(json: String, code: AgentChannel.Problem.Code) async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ServerLog()
        let server = log.server(at: socket(in: folder)) { _ in .keptByPerson }
        try server.start()
        defer { server.stop() }
        let reply = try await onOwnThread { () -> Result<AgentChannel.AppMessage, any Error> in
            Result {
                let descriptor = try UnixSocket.connect(to: socket(in: folder), until: .now + .seconds(2))
                defer { close(descriptor) }
                try UnixSocket.write(Array((json + "\n").utf8), to: descriptor, until: .now + .seconds(2))
                var buffer = LineBuffer()
                return try AgentChannelClient.reply(on: descriptor, into: &buffer, until: .now + .seconds(5))
            }
        }.get()
        guard case .error(let problem) = reply else {
            Issue.record("Expected an error, got \(reply)")
            return
        }
        #expect(problem.code == code)
        #expect(log.requests.isEmpty)
    }

    /// The server stops reading at the limit and closes, so the rest of a flood may not even
    /// go out; the refusal is still there to read.
    @Test(arguments: [AgentChannel.maximumMessageSize, AgentChannel.maximumMessageSize * 4])
    func turnsDownALineLongerThanTheLimit(length: Int) async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = AgentChannelServer(socket: socket(in: folder)) { _ in .keptByPerson }
        try server.start()
        defer { server.stop() }
        let reply = try await onOwnThread { () -> Result<AgentChannel.AppMessage, any Error> in
            Result {
                let descriptor = try UnixSocket.connect(to: socket(in: folder), until: .now + .seconds(2))
                defer { close(descriptor) }
                let flood = [UInt8](repeating: UInt8(ascii: "a"), count: length)
                try? UnixSocket.write(flood, to: descriptor, until: .now + .seconds(2))
                var buffer = LineBuffer()
                return try AgentChannelClient.reply(on: descriptor, into: &buffer, until: .now + .seconds(5))
            }
        }.get()
        #expect(reply == .error(.init(.badRequest, "The request is longer than \(AgentChannel.maximumMessageSize) bytes.")))
    }

    /// An app that hangs before replying looks like one that can't ask, in good time.
    @Test func givesUpOnAnAppThatDoesNotReply() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let silent = try listenWithoutAnswering(at: socket(in: folder))
        defer { close(silent) }
        // Timed on its own thread: getting back to this task can take seconds on a busy runner.
        let (status, took) = await onOwnThread {
            let started = ContinuousClock.now
            let status = AgentChannelClient(socket: socket(in: folder), responseTimeout: .milliseconds(200)).checkApp()
            return (status, ContinuousClock.now - started)
        }
        #expect(status == .unavailable(AgentChannelError.timedOut.localizedDescription))
        #expect(took < .seconds(2))
    }

    /// The command checks the answer itself too: a forged keep from something that is not
    /// the app's dialog is not believed.
    @Test func doesNotBelieveAKeepFromAnyoneButAPerson() async throws {
        let folder = try socketFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let listening = try listenWithoutAnswering(at: socket(in: folder))
        defer { close(listening) }
        let request = request
        let progress = await onOwnThread { () -> Result<PendingAnswer.Progress, any Error> in
            Result {
                let pending = try AgentChannelClient(socket: socket(in: folder)).ask(request)
                let app = accept(listening, nil, nil)
                guard app >= 0 else { throw AgentChannelError.system("accept", code: errno) }
                defer { close(app) }
                let forged = #"{"version":1,"type":"answer","answer":"keep","by":null,"reason":null}"# + "\n"
                try UnixSocket.write(Array(forged.utf8), to: app, until: .now + .seconds(2))
                return pending.waitForAnswer(until: .now + .seconds(30))
            }
        }
        #expect(throws: Never.self) { try progress.get() }
        guard case .failed(.unreadableMessage) = try progress.get() else {
            Issue.record("A keep without a person was taken: \(String(describing: try? progress.get()))")
            return
        }
    }

    @Test func expectsTheAppToRunAsThePerson() {
        #expect(AgentChannelClient.expectedAppUserID(environment: [:]) == geteuid())
        if geteuid() != 0 {
            #expect(AgentChannelClient.expectedAppUserID(environment: ["SUDO_UID": "0"]) == geteuid())
        }
    }

    // Helpers

    func socket(in folder: URL) -> URL {
        folder.appending(path: "agent.sock")
    }

    func client(_ folder: URL) -> AgentChannelClient {
        AgentChannelClient(socket: socket(in: folder))
    }
}

// MARK: - Helpers

/// What a server's dialog saw.
private final class ServerLog: @unchecked Sendable {
    private let lock = NSLock()
    private var receivedRequests: [ConfirmHiddenModeRequest] = []
    private var ended: [AgentChannel.Abandonment] = []
    private var cancelled = 0

    var requests: [ConfirmHiddenModeRequest] { lock.withLock { receivedRequests } }
    var abandonments: [AgentChannel.Abandonment] { lock.withLock { ended } }
    var cancelledDialogs: Int { lock.withLock { cancelled } }

    func received(_ request: ConfirmHiddenModeRequest) {
        lock.withLock { receivedRequests.append(request) }
    }

    /// A server whose dialog runs `dialog`, recorded here.
    func server(
        at socket: URL, limits: AgentChannelServer.Limits = .init(),
        dialog: @escaping @Sendable (ConfirmHiddenModeRequest) async -> ConfirmHiddenModeResponse
    ) -> AgentChannelServer {
        AgentChannelServer(socket: socket, limits: limits, handler: { [self] request in
            received(request)
            let response = await dialog(request)
            if Task.isCancelled { lock.withLock { cancelled += 1 } }
            return response
        }, abandoned: { [self] _, abandonment in
            lock.withLock { ended.append(abandonment) }
        })
    }
}

/// A dialog nobody answers: it closes only when cancelled.
private func waitUntilCancelled() async -> ConfirmHiddenModeResponse {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
    }
    return .revertedByPerson
}

/// Runs blocking `body` on a thread of its own, as the command runs, so a test's wait can
/// never hold a thread the server's dialog needs.
private func onOwnThread<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        Thread { continuation.resume(returning: body()) }.start()
    }
}

/// Waits on this thread until `condition` holds, for at most thirty seconds: a busy runner
/// can take seconds to start the server's handler, and a pass returns at once.
private func blockUntil(_ condition: () -> Bool) -> Bool {
    let deadline = ContinuousClock.now + .seconds(30)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        usleep(5_000)
    }
    return true
}

private func eventually(within timeout: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

/// A fresh folder for a socket, not yet created. A socket address holds 103 bytes of path,
/// so it goes in /tmp when the temporary folder's path is long.
private func socketFolder() throws -> URL {
    let name = "r-" + UUID().uuidString.prefix(8)
    let temporary = FileManager.default.temporaryDirectory
    let fits = temporary.path(percentEncoded: false).utf8.count + name.count + "/agent.sock".count < 100
    return (fits ? temporary : URL(filePath: "/tmp", directoryHint: .isDirectory)).appending(path: name, directoryHint: .isDirectory)
}

/// Leaves a socket nobody listens on, as an app that crashed does.
private func leaveStaleSocket(at url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = try UnixSocket.makeSocket()
    defer { close(descriptor) }
    let address = try UnixSocket.address(of: url)
    let bound = UnixSocket.withAddress(address) { bind(descriptor, $0, $1) }
    try #require(bound == 0)
}

/// A socket that takes connections into its queue but never accepts or replies, like an
/// app that hangs. Close the returned descriptor when done.
private func listenWithoutAnswering(at url: URL) throws -> Int32 {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = try UnixSocket.makeSocket()
    let address = try UnixSocket.address(of: url)
    guard UnixSocket.withAddress(address, { bind(descriptor, $0, $1) }) == 0, listen(descriptor, 4) == 0 else {
        close(descriptor)
        throw AgentChannelError.system("listen", code: errno)
    }
    return descriptor
}
