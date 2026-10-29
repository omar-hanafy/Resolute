import AppKit
import Observation
import os
import ResoluteKit

/// Answers `resolute`'s requests to keep a hidden mode (Figma 28:82): listens on the agent
/// channel and shows the Keep/Revert dialog, naming who asked, on the display being tried.
///
/// The command has already switched and puts the previous mode back itself unless a person
/// keeps the new one, and it writes History, so the app only asks. One request is up at a
/// time, never while the app's own trial question is; while one is up the app model starts
/// no trial of its own (it checks `isAsking`).
@MainActor
@Observable
final class AgentRequests {
    /// Why a request was turned down, in the words the command reports.
    enum Refusal {
        static let busy = "Resolute is already asking about another display setting"
        static let appTrial = "Resolute is already asking about a display setting chosen in the app"
        static let withdrawn = "the request was withdrawn"
        static let quitting = "Resolute is quitting"
        /// Settings › Command Line & Agents › Hidden modes asked for from the command line is
        /// Don't Allow: `hello` turns the command away, so nothing changes, and a request
        /// that comes anyway is answered Revert.
        static let notAllowed = "Resolute’s Settings don’t allow hidden modes asked for from the command line."
    }

    /// The request whose dialog is up; nil while none is.
    private(set) var current: ConfirmHiddenModeRequest?
    var isAsking: Bool { current != nil }

    @ObservationIgnored private let socket: URL
    @ObservationIgnored private let trialSeconds: @MainActor () -> Int
    @ObservationIgnored private let allowsHiddenModes: @MainActor () -> Bool
    @ObservationIgnored private let isAppTrialUp: @MainActor () -> Bool
    @ObservationIgnored private let present: @MainActor (TrialDialogModel) -> @MainActor () -> Void
    @ObservationIgnored private let showOutcome: @MainActor (TrialOutcome, TrialQuestion) -> Void
    @ObservationIgnored private let restore: @MainActor (ConfirmHiddenModeRequest) -> Void
    @ObservationIgnored private let clock: @MainActor () -> @MainActor () -> Date
    @ObservationIgnored private var server: AgentChannelServer?
    /// The trial length as the server's queue reads it for `hello`, kept up to date from
    /// `trialSeconds` on the main thread.
    @ObservationIgnored private let advertisedTrialSeconds = OSAllocatedUnfairLock(initialState: AgentChannel.defaultTrialSeconds)
    /// Whether the person allows hidden modes from the command line, as the server's queue
    /// reads it for `hello`, kept up to date from `allowsHiddenModes` on the main thread.
    @ObservationIgnored private let advertisedAllowance = OSAllocatedUnfairLock(initialState: true)
    @ObservationIgnored private var trialLengthObservation: ObservationLoop?
    /// The last request a person kept, so a command that vanishes right after is not undone;
    /// nil again once the same request comes again.
    @ObservationIgnored private var lastKept: ConfirmHiddenModeRequest?

    private static let log = Logger(subsystem: ResoluteLog.subsystem, category: "agents")

    /// - Parameters:
    ///   - trialSeconds: the app's trial length, which `hello` tells the command; read again
    ///     when what it reads changes.
    ///   - allowsHiddenModes: whether the person allows hidden modes from the command line;
    ///     when not, `hello` turns the command away before it changes anything.
    ///   - isAppTrialUp: whether the app's own Keep/Revert question is up.
    ///   - present: shows a dialog and returns what closes it (`TrialDialog.present`).
    ///   - showOutcome: the notice after a person answered (`TrialNotice.show`).
    ///   - restore: puts the previous mode back after a command vanished without a word.
    ///   - clock: makes the countdown's clock for each request.
    init(
        socket: URL,
        trialSeconds: @escaping @MainActor () -> Int,
        allowsHiddenModes: @escaping @MainActor () -> Bool = { true },
        isAppTrialUp: @escaping @MainActor () -> Bool,
        present: @escaping @MainActor (TrialDialogModel) -> @MainActor () -> Void = { TrialDialog.present($0) },
        showOutcome: @escaping @MainActor (TrialOutcome, TrialQuestion) -> Void = { TrialNotice.show($0, $1) },
        restore: @escaping @MainActor (ConfirmHiddenModeRequest) -> Void = { _ in },
        clock: @escaping @MainActor () -> @MainActor () -> Date = { TrialClock.monotonic() }
    ) {
        self.socket = socket
        self.trialSeconds = trialSeconds
        self.allowsHiddenModes = allowsHiddenModes
        self.isAppTrialUp = isAppTrialUp
        self.present = present
        self.showOutcome = showOutcome
        self.restore = restore
        self.clock = clock
    }

    /// The app's requests, at the model's socket, with its trial length.
    convenience init(model: AppModel) {
        self.init(
            socket: model.support.agentSocket,
            trialSeconds: { Int(model.preferences.trialLength.duration) },
            allowsHiddenModes: { model.preferences.commandLineHiddenModes == .ask },
            isAppTrialUp: { model.trial.question != nil },
            restore: { [weak model] request in model.map { AgentRequests.restorePreviousMode(of: request, in: $0) } }
        )
    }

    // MARK: Listening

    var isListening: Bool { server != nil }

    /// Starts listening at the socket. Another Resolute already listening, or a socket
    /// folder that is not safe, is logged and leaves the channel off: the command then asks
    /// in the terminal.
    func start() {
        guard server == nil else { return }
        let lock = advertisedTrialSeconds
        let allowance = advertisedAllowance
        trialLengthObservation = ObservationLoop { [weak self] in
            guard let self else { return }
            let seconds = trialSeconds()
            let allows = allowsHiddenModes()
            lock.withLock { $0 = seconds }
            allowance.withLock { $0 = allows }
        }
        let server = AgentChannelServer(
            socket: socket,
            trialSeconds: { lock.withLock { $0 } },
            refusal: { allowance.withLock { $0 } ? nil : Refusal.notAllowed },
            handler: { [weak self] request in
                let arrived = ContinuousClock.now
                guard let self else { return .reverted(because: Refusal.quitting) }
                return await self.answer(request, arrived: arrived)
            },
            abandoned: { [weak self] request, why in
                guard let self else { return }
                // On the server's queue; the main thread may be in a modal session.
                MainRunLoop.perform { self.abandoned(request, why) }
            }
        )
        do {
            try server.start()
            self.server = server
        } catch {
            Self.log.error("Could not listen for requests from resolute: \(error.localizedDescription, privacy: .public)")
            trialLengthObservation?.cancel()
            trialLengthObservation = nil
        }
    }

    /// Stops listening. A request under way is dropped and its dialog closes; its command
    /// sees the connection close and puts the previous mode back.
    func stop() {
        trialLengthObservation?.cancel()
        trialLengthObservation = nil
        server?.stop()
        server = nil
    }

    // MARK: Answering

    /// Shows the dialog for `request` and waits for its answer: Keep only from a person
    /// before the countdown ends. Turned down while another question is up, and when the
    /// person doesn't allow hidden modes from the command line, which `hello` checked before
    /// the command switched. Cancelling the task (the command dismissed the request or went
    /// away) closes the dialog.
    ///
    /// The countdown starts when the request `arrived`: the main thread may have been busy,
    /// in the app's own trial for one, and the command's wait started then.
    func answer(_ request: ConfirmHiddenModeRequest, arrived: ContinuousClock.Instant? = nil) async -> ConfirmHiddenModeResponse {
        // The same request again means the display was put back since: that Keep is over,
        // also when this one is turned away and its command is killed before it hears so.
        // Another request leaves it, since the Keep may still be on its way to its command.
        if lastKept == request { lastKept = nil }
        guard allowsHiddenModes() else { return .reverted(because: Refusal.notAllowed) }
        guard current == nil else { return .reverted(because: Refusal.busy) }
        guard !isAppTrialUp() else { return .reverted(because: Refusal.appTrial) }
        guard !Task.isCancelled else { return .reverted(because: Refusal.withdrawn) }
        current = request
        defer { current = nil }
        let clock = clock()
        let waited = arrived.map { $0.duration(to: .now).components } ?? (seconds: 0, attoseconds: 0)
        let start = clock().addingTimeInterval(-(Double(waited.seconds) + Double(waited.attoseconds) / 1e18))
        let question = Self.question(for: request, at: start)
        let model = TrialDialogModel(question: question, total: TimeInterval(request.trialSeconds), clock: clock)
        var close: (@MainActor () -> Void)?
        let answer = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<TrialDialogModel.Answer, Never>) in
                model.onAnswer = { [weak self] answer in
                    // Noted as the person clicks, before this resumes: a command killed
                    // meanwhile must not have the mode put back.
                    if answer == .kept { self?.lastKept = request }
                    continuation.resume(returning: answer)
                }
                close = present(model)
            }
        } onCancel: {
            // The run loop's way also works inside a modal session, where work queued on
            // the main actor waits; whichever comes first dismisses.
            MainRunLoop.perform { model.dismiss() }
            Task { @MainActor in model.dismiss() }
        }
        close?()
        switch answer {
        case .kept:
            showOutcome(.kept, question)
            return .keptByPerson
        case .reverted:
            showOutcome(.switchedBack, question)
            return .revertedByPerson
        case .noAnswer:
            return .noAnswer(after: request.trialSeconds)
        case .dismissed:
            return .reverted(because: Refusal.withdrawn)
        }
    }

    /// The question the dialog asks for `request`, counting down from `start`.
    static func question(for request: ConfirmHiddenModeRequest, at start: Date) -> TrialQuestion {
        TrialQuestion(
            displayID: request.display.id, displayName: request.display.name, mode: request.mode,
            previousMode: request.previousMode,
            countdown: RevertCountdown(start: start, duration: TimeInterval(request.trialSeconds)),
            requester: request.requester
        )
    }

    /// A command that was killed or crashed puts nothing back, so the app does, unless a
    /// person kept the mode. A command that said it stopped waiting puts it back itself.
    func abandoned(_ request: ConfirmHiddenModeRequest, _ why: AgentChannel.Abandonment) {
        guard why == .disconnected, lastKept != request else { return }
        Self.log.notice("The command asking about \(request.display.name, privacy: .public) went away; putting the previous mode back")
        restore(request)
    }

    /// Puts `request`'s previous mode back on its display as the command's own revert would:
    /// for the session only (the one before may itself have been kept only until logout),
    /// else the display's default mode, never the mode on trial. A display that shows another
    /// mode was changed since and is left alone; one that is away, maybe because it can't
    /// show the mode on trial, is waited for as the app's own trials are. A switch under way
    /// goes first, since its countdown turns other changes away.
    ///
    /// The command can't record how its trial ended any more, so History says it here.
    static func restorePreviousMode(of request: ConfirmHiddenModeRequest, in model: AppModel) {
        model.modeChanges.afterSwitch { [weak model] in
            guard let model else { return }
            model.refresh()
            let reference = request.display
            guard let display = model.displays.first(where: { $0.id == reference.id }) ?? model.lastSeenDisplays[reference.id],
                  display.vendorID == reference.vendorID, display.productID == reference.productID,
                  display.serialNumber == reference.serialNumber,
                  let trialMode = display.modes.first(where: { $0.modeID == request.modeID }),
                  let restore = ModeSwitcher.restore(undoing: request.modeID, on: display, backTo: request.previousModeID)
            else {
                Self.log.error("Could not put the previous mode back on \(reference.name, privacy: .public): its modes are not known")
                return
            }
            var before = display
            before.currentModeID = request.previousModeID
            let history = model.history(from: request.requester.source)
            switch model.modeChanges.putBack(restore) {
            case .restored?:
                history.recordSwitch(of: before, to: trialMode, outcome: .reverted(.unspecified))
            case .leftAlone?:
                history.recordSwitch(of: before, to: trialMode, outcome: .reverted(.displayChanged))
            case .waiting?:
                model.recordWhenRevertEnds(switching: before, to: trialMode, from: request.requester.source)
            case nil:
                return
            }
            model.refresh()
        }
    }
}
