import Darwin
import Foundation

/// The app's side of the agent channel. It listens at the socket, replies to `hello` at
/// once, and hands each `confirmHiddenMode` to `handler`, which shows the dialog on the
/// display being tried and returns the person's answer.
///
/// Each request's handler runs in a task of its own. The handler counts down
/// `request.trialSeconds`, the length the command asked for and waits for. When the command
/// dismisses the request, or its connection closes, the task is cancelled: the handler
/// closes its dialog and returns, and `abandoned` hears why. A command that vanished without
/// a word (`.disconnected`) puts nothing back, so the app may restore the previous mode.
///
/// The server's state lives on one serial queue, which makes it safe to share between
/// threads; `abandoned` is called on that queue. `start()`, `stop()` and `isListening` wait
/// for the queue, so none of them may be called from `abandoned`.
public final class AgentChannelServer: @unchecked Sendable {
    public typealias Handler = @Sendable (ConfirmHiddenModeRequest) async -> ConfirmHiddenModeResponse
    public typealias AbandonmentHandler = @Sendable (ConfirmHiddenModeRequest, AgentChannel.Abandonment) -> Void

    /// Bounds on what one connection may hold up.
    public struct Limits: Sendable {
        /// How long a connection may take to send its request.
        public var requestTimeout: Duration
        /// How many connections may be open at once; more are turned away as busy.
        public var maximumConnections: Int
        /// How long after its trial a handler may still answer, before the request is
        /// answered as unanswered and the handler cancelled.
        public var answerGrace: Duration

        public init(requestTimeout: Duration = .seconds(5), maximumConnections: Int = 8, answerGrace: Duration = .seconds(30)) {
            self.requestTimeout = requestTimeout
            self.maximumConnections = maximumConnections
            self.answerGrace = answerGrace
        }
    }

    /// One connection, between its accept and its close.
    private final class Connection {
        enum State {
            case awaitingRequest
            case answering(ConfirmHiddenModeRequest, Task<Void, Never>)
        }

        let descriptor: Int32
        let source: DispatchSourceRead
        var buffer = LineBuffer()
        var state = State.awaitingRequest
        var timer: DispatchSourceTimer?

        init(descriptor: Int32, source: DispatchSourceRead) {
            self.descriptor = descriptor
            self.source = source
        }
    }

    public let socket: URL
    private let appVersion: String
    private let trialSeconds: @Sendable () -> Int
    private let refusal: @Sendable () -> String?
    private let limits: Limits
    private let handler: Handler
    private let abandoned: AbandonmentHandler?
    private let queue = DispatchQueue(label: "com.omarhanafy.Resolute.agent-channel")

    // Only touched on `queue`.
    private var listener: DispatchSourceRead?
    /// Set while accepting is paused because the process ran out of descriptors.
    private var isPausingAccepts = false
    private var connections: [Int: Connection] = [:]
    private var nextConnectionID = 0
    /// The socket file this server made, so `stop()` never removes another server's.
    private var socketFile: (device: dev_t, inode: ino_t)?

    /// `trialSeconds` gives the app's trial length, for `hello`; `refusal`, why the person
    /// doesn't allow hidden modes from the command line, or nil when they do, so `hello`
    /// turns the command away before it changes anything, and a request is turned away too.
    /// Both are called on the server's queue, so they must be safe to call from any thread.
    public init(
        socket: URL,
        appVersion: String = ResoluteVersion.string,
        trialSeconds: @escaping @Sendable () -> Int = { AgentChannel.defaultTrialSeconds },
        refusal: @escaping @Sendable () -> String? = { nil },
        limits: Limits = Limits(),
        handler: @escaping Handler,
        abandoned: AbandonmentHandler? = nil
    ) {
        self.socket = socket
        self.appVersion = appVersion
        self.trialSeconds = trialSeconds
        self.refusal = refusal
        self.limits = limits
        self.handler = handler
        self.abandoned = abandoned
    }

    deinit {
        // Nothing else can reach the server any more, so its state is safe to touch here.
        if isPausingAccepts { listener?.resume() }
        listener?.cancel()
        for connection in connections.values {
            if case .answering(_, let task) = connection.state { task.cancel() }
            connection.timer?.cancel()
            connection.source.cancel()
        }
        removeSocketFile()
    }

    public var isListening: Bool {
        queue.sync { listener != nil }
    }

    /// Starts listening. The socket's folder is made private (0700) and the socket the
    /// person's alone (0600); a socket left by an app that is no longer running is replaced.
    /// Throws `alreadyListening` when another Resolute listens there.
    public func start() throws {
        try queue.sync { try listen() }
    }

    /// Stops listening and drops the requests under way: their handlers are cancelled and
    /// their commands, which see the connection close, put the previous mode back. Removes
    /// the socket.
    public func stop() {
        queue.sync { shutDown() }
    }

    // MARK: - Listening

    private var path: String { socket.path(percentEncoded: false) }

    private func listen() throws {
        dispatchPrecondition(condition: .onQueue(queue))
        guard listener == nil else { return }
        // Checked first, so a path that can never work creates no folder.
        let address = try UnixSocket.address(of: socket)
        try Self.preparePrivateFolder(socket.deletingLastPathComponent())
        try removeStaleSocket()
        let descriptor = try UnixSocket.makeSocket()
        var isBound = false
        do {
            guard UnixSocket.withAddress(address, { bind(descriptor, $0, $1) }) == 0 else {
                throw errno == EADDRINUSE
                    ? AgentChannelError.alreadyListening(path)
                    : AgentChannelError.system("listen at \(path)", code: errno)
            }
            isBound = true
            var info = stat()
            // Only the person can connect. The private folder keeps everyone else out
            // until then.
            guard chmod(path, 0o600) == 0, Darwin.listen(descriptor, 16) == 0, lstat(path, &info) == 0 else {
                throw AgentChannelError.system("listen at \(path)", code: errno)
            }
            socketFile = (info.st_dev, info.st_ino)
        } catch {
            close(descriptor)
            if isBound { unlink(path) }
            throw error
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnections(on: descriptor) }
        source.setCancelHandler { close(descriptor) }
        listener = source
        source.resume()
        AgentChannel.log.notice("Listening for agent requests at \(self.path, privacy: .public)")
    }

    private func shutDown() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let listener else { return }
        // A suspended source runs its cancel handler, which closes the socket, only once resumed.
        if isPausingAccepts {
            isPausingAccepts = false
            listener.resume()
        }
        listener.cancel()
        self.listener = nil
        for id in Array(connections.keys) {
            if case .answering(_, let task)? = connections[id]?.state { task.cancel() }
            finish(id)
        }
        removeSocketFile()
        AgentChannel.log.notice("Stopped listening for agent requests")
    }

    private func removeSocketFile() {
        var info = stat()
        if let socketFile, lstat(path, &info) == 0, info.st_dev == socketFile.device, info.st_ino == socketFile.inode {
            unlink(path)
        }
        socketFile = nil
    }

    /// Makes `folder` the person's alone, creating it when it is missing. It must be a real
    /// folder that belongs to them.
    static func preparePrivateFolder(_ folder: URL) throws {
        let path = folder.path(percentEncoded: false)
        do {
            try FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw AgentChannelError.unsafeLocation("Could not create \(path): \(error.localizedDescription)")
        }
        var info = stat()
        guard lstat(path, &info) == 0 else { throw AgentChannelError.system("look at \(path)", code: errno) }
        guard info.st_mode & S_IFMT == S_IFDIR else {
            throw AgentChannelError.unsafeLocation("\(path) is not a folder, so Resolute can't listen there.")
        }
        guard info.st_uid == geteuid() else {
            throw AgentChannelError.unsafeLocation("\(path) belongs to another user, so Resolute can't listen there.")
        }
        if info.st_mode & 0o077 != 0, chmod(path, 0o700) != 0 {
            throw AgentChannelError.system("make \(path) private", code: errno)
        }
    }

    /// Removes a socket left by an app that is no longer running. A socket someone listens
    /// on means another Resolute; anything that is not a socket is left for the person.
    private func removeStaleSocket() throws {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            guard errno == ENOENT else { throw AgentChannelError.system("look at \(path)", code: errno) }
            return
        }
        guard info.st_mode & S_IFMT == S_IFSOCK else {
            throw AgentChannelError.unsafeLocation("\(path) is not a socket, so Resolute left it as it is. Remove it to let Resolute listen.")
        }
        do {
            close(try UnixSocket.connect(to: socket, until: .now + .milliseconds(500)))
        } catch AgentChannelError.appNotRunning {
            guard unlink(path) == 0 || errno == ENOENT else {
                throw AgentChannelError.system("remove the old socket \(path)", code: errno)
            }
            AgentChannel.log.notice("Removed a socket left at \(self.path, privacy: .public)")
            return
        }
        throw AgentChannelError.alreadyListening(path)
    }

    // MARK: - Connections

    private func acceptConnections(on listening: Int32) {
        dispatchPrecondition(condition: .onQueue(queue))
        while true {
            let descriptor = accept(listening, nil, nil)
            guard descriptor >= 0 else {
                let code = errno
                if code == EINTR || code == ECONNABORTED { continue }
                if code != EAGAIN { pauseAccepting(because: code) }
                return
            }
            guard (try? UnixSocket.configure(descriptor)) != nil else {
                close(descriptor)
                continue
            }
            // Only the person, or root for `sudo resolute`, may ask.
            let user = UnixSocket.peerUserID(of: descriptor)
            guard let user, user == geteuid() || user == 0 else {
                AgentChannel.log.error("Turned away an agent connection from user \(user.map(String.init) ?? "unknown", privacy: .public)")
                close(descriptor)
                continue
            }
            guard connections.count < limits.maximumConnections else {
                let problem = AgentChannel.Problem(.busy, "Resolute is answering as many requests as it takes at once. Try again shortly.")
                reply(.error(problem), to: descriptor)
                close(descriptor)
                continue
            }
            open(descriptor)
        }
    }

    /// The waiting connection stays queued after a failed accept, so the listener would fire
    /// again at once; it rests for a second instead of spinning.
    private func pauseAccepting(because code: Int32) {
        guard let listener, !isPausingAccepts else { return }
        AgentChannel.log.error("Could not accept an agent connection: \(String(cString: strerror(code)), privacy: .public)")
        isPausingAccepts = true
        listener.suspend()
        // Only its identity goes into the closure: a source isn't Sendable in older SDKs.
        let paused = ObjectIdentifier(listener)
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.isPausingAccepts, let listener = self.listener, ObjectIdentifier(listener) == paused else {
                return
            }
            self.isPausingAccepts = false
            listener.resume()
        }
    }

    private func open(_ descriptor: Int32) {
        let id = nextConnectionID
        nextConnectionID += 1
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        let connection = Connection(descriptor: descriptor, source: source)
        source.setEventHandler { [weak self] in self?.receive(on: id) }
        source.setCancelHandler { close(descriptor) }
        connection.timer = schedule(after: limits.requestTimeout) { [weak self] in
            // A connection that never asks only holds a slot.
            guard case .awaitingRequest? = self?.connections[id]?.state else { return }
            self?.finish(id)
        }
        connections[id] = connection
        source.resume()
    }

    private func receive(on id: Int) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let connection = connections[id] else { return }
        let read = UnixSocket.read(from: connection.descriptor, into: &connection.buffer)
        process(id, isOpen: read == .open)
    }

    /// Acts on what `id` has sent so far; `isOpen` is false once it can send no more.
    private func process(_ id: Int, isOpen: Bool) {
        guard let connection = connections[id] else { return }
        switch connection.state {
        case .awaitingRequest:
            switch connection.buffer.next() {
            case .line(let line):
                handle(line, on: id)
                // A dismissal can come right behind its request.
                if connections[id] != nil, connection.buffer.count > 0 || !isOpen { process(id, isOpen: isOpen) }
            case .tooLong:
                refuse(id, AgentChannel.Problem(.badRequest, "The request is longer than \(connection.buffer.limit) bytes."))
            case .incomplete:
                if !isOpen { finish(id) }
            }
        case .answering(let request, let task):
            // After the request only a dismissal may come; anything else, or the end of the
            // connection, means the command is gone.
            let abandonment: AgentChannel.Abandonment
            switch connection.buffer.next() {
            case .line(let line):
                if case .dismiss(let reason)? = try? AgentChannel.decode(AgentChannel.CommandMessage.self, from: line) {
                    abandonment = .dismissed(reason)
                } else {
                    abandonment = .disconnected
                }
            case .tooLong:
                abandonment = .disconnected
            case .incomplete:
                guard !isOpen else { return }
                abandonment = .disconnected
            }
            task.cancel()
            finish(id)
            let why = switch abandonment {
            case .dismissed(let reason): "dismissed, \(reason.rawValue)"
            case .disconnected: "the command disconnected"
            }
            AgentChannel.log.notice("""
                The request for \(request.display.name, privacy: .public) ended without an answer: \(why, privacy: .public)
                """)
            abandoned?(request, abandonment)
        }
    }

    private func handle(_ line: [UInt8], on id: Int) {
        guard let connection = connections[id] else { return }
        let message: AgentChannel.CommandMessage
        do {
            message = try AgentChannel.decode(AgentChannel.CommandMessage.self, from: line)
        } catch AgentChannelError.unsupportedVersion(let version) {
            refuse(id, AgentChannel.Problem(
                .unsupportedVersion,
                "This Resolute speaks version \(AgentChannel.version) of the agent channel, not version \(version). Use the resolute command that came with the app."
            ))
            return
        } catch {
            refuse(id, AgentChannel.Problem(.badRequest, error.localizedDescription))
            return
        }
        switch message {
        case .hello:
            if let reason = refusal() {
                refuse(id, AgentChannel.Problem(.refused, reason))
                return
            }
            let seconds = min(max(trialSeconds(), AgentChannel.trialSecondsRange.lowerBound), AgentChannel.trialSecondsRange.upperBound)
            reply(.ready(AgentChannel.Ready(appVersion: appVersion, trialSeconds: seconds)), to: connection.descriptor)
            finish(id)
        case .dismiss:
            finish(id)
        case .confirmHiddenMode(let request):
            // Also for a command that skipped `hello`, or asked after the setting changed:
            // it puts the previous mode back itself.
            if let reason = refusal() {
                refuse(id, AgentChannel.Problem(.refused, reason))
                return
            }
            do {
                try request.validate()
            } catch {
                refuse(id, AgentChannel.Problem(.badRequest, error.localizedDescription))
                return
            }
            AgentChannel.log.notice("""
                \(request.requester.name, privacy: .public) asks to keep mode \(request.modeID) \
                on \(request.display.name, privacy: .public)
                """)
            connection.timer?.cancel()
            connection.timer = schedule(after: .seconds(request.trialSeconds) + limits.answerGrace) { [weak self] in
                self?.answerTimedOut(id)
            }
            let handler = handler
            let task = Task { [weak self] in
                let response = await handler(request)
                self?.queue.async { [weak self] in self?.deliver(response, on: id) }
            }
            connection.state = .answering(request, task)
        }
    }

    private func deliver(_ response: ConfirmHiddenModeResponse, on id: Int) {
        // A request dismissed meanwhile has no one to answer.
        guard let connection = connections[id], case .answering(let request, _) = connection.state else { return }
        AgentChannel.log.notice("""
            Answered \(response.answer.rawValue, privacy: .public) for \(request.display.name, privacy: .public)\
            \(response.reason.map { ": " + $0 } ?? "", privacy: .public)
            """)
        reply(.answer(response), to: connection.descriptor)
        finish(id)
    }

    /// The handler took too long: whatever it shows can no longer be kept.
    private func answerTimedOut(_ id: Int) {
        guard let connection = connections[id], case .answering(let request, let task) = connection.state else { return }
        task.cancel()
        AgentChannel.log.error("The dialog for \(request.display.name, privacy: .public) did not answer in time")
        reply(.answer(.noAnswer(after: request.trialSeconds)), to: connection.descriptor)
        finish(id)
    }

    private func refuse(_ id: Int, _ problem: AgentChannel.Problem) {
        if let connection = connections[id] { reply(.error(problem), to: connection.descriptor) }
        AgentChannel.log.error("Refused an agent request: \(problem.message, privacy: .public)")
        finish(id)
    }

    /// Sends `message`, giving a slow reader a second.
    private func reply(_ message: AgentChannel.AppMessage, to descriptor: Int32) {
        guard let line = try? AgentChannel.line(message) else { return }
        try? UnixSocket.write(line, to: descriptor, until: .now + .seconds(1))
    }

    private func finish(_ id: Int) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.timer?.cancel()
        connection.source.cancel()
    }

    private func schedule(after delay: Duration, _ action: @escaping @Sendable () -> Void) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + UnixSocket.interval(delay))
        timer.setEventHandler(handler: action)
        timer.resume()
        return timer
    }
}
