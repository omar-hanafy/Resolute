import ArgumentParser
import Foundation
import ResoluteKit

struct SetCommand: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Switch a display to another mode.",
        discussion: """
            Examples:
              resolute set 1496x967          keep the refresh rate, pick the resolution
              resolute set 1920x1200@1x      a low-resolution (1×) mode
              resolute set --refresh 60      keep the resolution, change the refresh rate
              resolute set --mode-id 55      an exact mode from `resolute modes --raw`
              resolute set --default         the display's default mode
            """
    )

    @Argument(help: "WIDTHxHEIGHT in points, optionally followed by @2x or @1x and @<Hz>.")
    var resolution: String?

    @OptionGroup var target: DisplayOptions

    // Read as text, so that only plain decimal numbers count: "0x3c" is not 60 Hz.
    @Option(help: "2 for HiDPI, 1 for low resolution.")
    var scale: String?

    @Option(help: "Refresh rate in Hz, for example 60 or 59.94.")
    var refresh: String?

    @Option(name: .customLong("mode-id"), help: "An exact mode ID.")
    var modeID: Int32?

    @Flag(name: .customLong("default"), help: "Switch to the display's default mode.")
    var useDefault = false

    @Flag(help: "Change the mode until you log out instead of permanently.")
    var session = false

    @Flag(help: ArgumentHelp(
        "Allow hidden modes that macOS does not list.",
        discussion: """
            A person must keep a hidden mode before its trial ends, or the previous mode comes back. When the \
            Resolute app is running, it asks on the display; otherwise type y in an interactive terminal within \
            15 seconds. A kept hidden mode lasts until you log out.
            """
    ))
    var allowHidden = false

    @Flag(help: "Show what would change without changing it.")
    var dryRun = false

    @Flag(help: "Print JSON.")
    var json = false

    func validate() throws {
        if let refresh, !(ModeQuery.decimal(refresh).map(ModeQuery.isPlausible(refreshRate:)) ?? false) {
            throw ValidationError("--refresh takes a rate in hertz, for example 60 or 59.94.")
        }
        if let scale, !(ModeQuery.decimal(scale).map(ModeQuery.isPlausible(scale:)) ?? false) {
            throw ValidationError("--scale takes 2 for HiDPI or 1 for low resolution.")
        }
        if modeID != nil, resolution != nil || scale != nil || refresh != nil || useDefault {
            throw ValidationError("--mode-id names one exact mode; leave out the resolution, --scale, --refresh and --default.")
        }
        if useDefault, resolution != nil || scale != nil || refresh != nil {
            throw ValidationError("--default picks the display's default mode; leave out the resolution, --scale and --refresh.")
        }
        // Only something shaped like a size is checked here: a bare word or number is more
        // likely the value of a mistyped option, which ArgumentParser reports after this.
        if let resolution, Output.looksLikeSize(resolution) {
            let parsed: ModeQuery
            do {
                parsed = try ModeQuery(resolution: resolution)
            } catch {
                throw ValidationError(error.localizedDescription)
            }
            if parsed.scale != nil, scale != nil {
                throw ValidationError("Give the scale once, either as @2x or @1x in the resolution or with --scale.")
            }
            if parsed.refreshRate != nil, refresh != nil {
                throw ValidationError("Give the refresh rate once, either as @60 in the resolution or with --refresh.")
            }
        }
    }

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        // Checked here rather than in validate(): ArgumentParser validates before it
        // reports unknown options, so this message would hide a mistyped one.
        guard resolution != nil || scale != nil || refresh != nil || modeID != nil || useDefault else {
            throw ResoluteError.usage("Give a resolution, --refresh, --scale, --mode-id or --default.")
        }
        let service = context.service
        let display = try target.resolve(in: service.displays())
        var query: ModeQuery
        do {
            query = try resolution.map { try ModeQuery(resolution: $0) } ?? ModeQuery()
        } catch ResoluteError.invalidResolution(let text) {
            if refresh == nil, let rate = ModeQuery.decimal(text), ModeQuery.isPlausible(refreshRate: rate), rate <= 1_000 {
                throw ResoluteError.usage("“\(text)” is not a resolution. To change only the refresh rate, use --refresh \(text).")
            }
            throw ResoluteError.usage(ResoluteError.invalidResolution(text).localizedDescription)
        } catch let error as ResoluteError {
            throw ResoluteError.usage(error.localizedDescription)
        }
        if let scale = scale.flatMap(ModeQuery.decimal) { query.scale = scale }
        if let refresh = refresh.flatMap(ModeQuery.decimal) { query.refreshRate = refresh }
        query.modeID = modeID
        query.useDefault = useDefault
        query.allowHidden = allowHidden

        let mode = try query.resolve(on: display)
        guard mode.modeID != display.currentModeID else {
            var summary = Summary(display: display, mode: mode)
            summary.result = .applied
            try say(summary, or: "\(display.name) is already at \(Output.describe(mode)).", in: context)
            return
        }
        guard !dryRun else {
            try say(Summary(display: display, mode: mode), or: "Would switch \(display.name) to \(Output.describe(mode)).", in: context)
            return
        }
        // A person keeps a hidden mode: at the display when the app is there to ask, else in
        // this terminal. With nobody to ask, nothing changes.
        let asker = mode.origin == .hidden ? try Self.asker(in: context) : nil
        // Hidden modes are tried for the session, and a person keeps one until logout at
        // most; --session only limits how long a listed mode lasts.
        let trial = session || mode.origin == .hidden
        let switcher = ModeSwitcher(service: service)
        // History lists the change once it has ended, however it ended.
        let history = context.history
        var isRecorded = false
        do {
            // Until the trial is over, Ctrl-C answers it rather than leaving the mode in place.
            try context.interrupts.catchingControlC {
                var request: ConfirmHiddenModeRequest?
                if case .app(_, let trialSeconds) = asker {
                    let asked = ConfirmHiddenModeRequest(
                        display: display, trying: mode, previous: display.currentMode, trialSeconds: trialSeconds,
                        requester: context.requester()
                    )
                    context.writeError("Trying \(asked.mode) on \(display.name) (hidden mode).")
                    request = asked
                }
                var answer: Answer?
                let outcome = try switcher.apply(modeID: mode.modeID, to: display.id, trial: trial) {
                    guard let asker else { return .keepForSession }
                    let given = Self.ask(asker, about: request, in: context)
                    answer = given
                    return given.decision
                }
                isRecorded = history.record(
                    outcome, switching: display, to: mode, revertReason: answer?.revertReason ?? .unspecified
                ) != nil
                try report(outcome, answer: answer, of: mode, on: display, with: switcher, in: context) {
                    isRecorded = history.recordSwitch(of: display, to: mode, outcome: .reverted(.displayWentDark)) != nil
                }
            }
        } catch {
            if !isRecorded {
                history.record(error, switching: display, to: mode)
            }
            throw error
        }
    }

    /// Prints `summary` with --json, else `text`.
    private func say(_ summary: Summary, or text: String, in context: CommandContext) throws {
        context.write(json ? try Output.json(summary) : text)
    }

    /// Says how the switch ended, waiting first for a display that went away mid-trial;
    /// `restored` runs once such a display is back in its previous mode.
    private func report(
        _ outcome: ModeSwitcher.Outcome, answer: Answer?, of mode: DisplayMode, on display: Display, with switcher: ModeSwitcher,
        in context: CommandContext, restored: () -> Void
    ) throws {
        let service = context.service
        var summary = Summary(display: display, mode: mode)
        // The app's reasons say what happened at the display; the terminal's are the
        // person's own doing.
        let because = answer.flatMap { $0.isToldInText ? $0.reason : nil }.map { " (\($0))" } ?? ""
        switch outcome {
        case .alreadyCurrent:
            summary.result = .applied
            try say(summary, or: "\(display.name) is already at \(Output.describe(mode)).", in: context)
        case .applied, .kept, .keptForSession:
            summary.result = answer?.keptBy == nil ? .applied : .kept
            summary.keptBy = answer?.keptBy
            summary.until = outcome == .keptForSession ? "logout" : nil
            // The full snapshot, since CoreGraphics may not name a hidden mode in use.
            guard switcher.currentModeID(of: display.id) == mode.modeID else {
                let isGone = !service.displays().contains { $0.id == display.id }
                context.writeError(isGone
                    ? "warning: \(display.name) went away, so its new mode could not be checked."
                    : "warning: macOS accepted the change but reports a different mode now.")
                if json { context.write(try Output.json(summary)) }
                return
            }
            let until = outcome == .keptForSession ? " (until you log out)" : ""
            try say(summary, or: "\(display.name): \(Output.describe(mode))\(until)", in: context)
        case .reverted(let modeID):
            let restored = display.modes.first { $0.modeID == modeID }
            summary.revert(answer, restored: restored)
            try say(summary, or: "Kept the previous mode: \(restored.map(Output.describe) ?? "mode \(modeID)")\(because).", in: context)
        case .leftAlone(let current):
            let shown = display.modes.first { $0.modeID == current }
            summary.revert(answer, restored: shown)
            let text = "\(display.name) was showing \(shown.map(Output.describe) ?? "mode \(current)"), when you answered, so it was left as it is."
            try say(summary, or: text, in: context)
        case .restorePending(let pending):
            let back = try Self.finishRestore(pending, with: switcher, on: display, in: context, json: json)
            restored()
            summary.revert(answer, restored: back)
            if json { context.write(try Output.json(summary)) }
        }
    }

    /// Waits for a display that went away during a trial to come back, undoes the trial
    /// and says how the display came back, returning the mode it is back in. A command gets
    /// no display notifications, so it looks every `restorePollInterval` until
    /// `restoreTimeout`, also after a failed try: a display that has only just come back may
    /// not take a mode yet. With `json`, standard output is left for the JSON, so how the
    /// wait ended goes to standard error with the rest.
    @discardableResult
    static func finishRestore(
        _ pending: ModeSwitcher.PendingRestore, with switcher: ModeSwitcher, on display: Display, in context: CommandContext,
        json: Bool = false
    ) throws -> DisplayMode? {
        let say = json ? context.writeError : context.write
        let waitingMessage = pending.resolveDisplay(in: context.service.displays()) != nil
            ? "\(pending.displayName) could not restore the previous mode yet. Waiting for it to accept the change…"
            : "\(pending.displayName) went away. Waiting for it to come back to restore the previous mode…"
        context.writeError(waitingMessage)
        let deadline = ContinuousClock.now + .seconds(context.restoreTimeout)
        var progress = ModeSwitcher.RestoreProgress.waiting
        // The failure from the last try, while the display is back; one that went away again
        // clears it. Only the first failure is logged.
        var lastError: (any Error)?
        var hasFailed = false
        while progress == .waiting {
            do {
                progress = try switcher.finish(pending, logsFailures: !hasFailed)
                lastError = nil
            } catch {
                lastError = error
                hasFailed = true
            }
            guard progress == .waiting else { break }
            guard ContinuousClock.now < deadline else {
                switcher.giveUp(on: pending, after: .seconds(context.restoreTimeout))
                context.writeError(Self.wayBack(pending, on: display))
                throw lastError ?? ResoluteError.displayDidNotReturn(display: pending.displayName)
            }
            guard context.interrupts.wait(context.restorePollInterval) != .interrupted else {
                // Stopped with Ctrl-C: one last look, then the way back.
                if let last = try? switcher.finish(pending, logsFailures: !hasFailed), last != .waiting {
                    progress = last
                    break
                }
                ResoluteLog.modes.notice("Stopped waiting for \(pending.displayName, privacy: .public): interrupted")
                context.writeError(Self.wayBack(pending, on: display))
                throw ResoluteError.cancelled
            }
        }
        let returned = pending.resolveDisplay(in: context.service.displays())
        func mode(_ modeID: Int32) -> DisplayMode? {
            (returned ?? display).modes.first { $0.modeID == modeID }
        }
        func describe(_ modeID: Int32) -> String {
            mode(modeID).map(Output.describe) ?? "mode \(modeID)"
        }
        func isPrevious(_ modeID: Int32) -> Bool {
            if let fingerprint = pending.previousMode, let mode = returned?.modes.first(where: { $0.modeID == modeID }) {
                return fingerprint == ModeSwitcher.ModeFingerprint(mode)
            }
            return modeID == pending.modeID
        }
        var back: DisplayMode?
        switch progress {
        case .restored(let modeID):
            back = mode(modeID)
            let which = isPrevious(modeID) ? "the previous mode" : "its default mode"
            say("\(pending.displayName) is back. Restored \(which): \(describe(modeID)).")
        case .leftAlone(let current) where isPrevious(current):
            back = mode(current)
            say("\(pending.displayName) is back with the previous mode: \(describe(current)).")
        case .leftAlone(let current):
            back = mode(current)
            say("\(pending.displayName) is back with \(describe(current)), so it was left as it is.")
        case .waiting:
            break
        }
        // A mode that never showed is an error whether or not the display went away, once
        // the display's state is told.
        if let failure = pending.failure { throw failure }
        return back
    }

    /// Numeric display and mode IDs may change on reconnect. Do not hand out a stale
    /// command that could now select another display or mode.
    static func wayBack(_ pending: ModeSwitcher.PendingRestore, on display: Display) -> String {
        let previous = display.modes.first { $0.modeID == pending.modeID }
        let size = previous.map {
            let rate = RefreshRate.format($0.refreshRate)
            return $0.sizeText + (rate.isEmpty ? " (refresh unknown)" : " @ \(rate)")
        } ?? "the previous mode"
        return "To restore \(pending.displayName) to \(size), reconnect it and run resolute displays, then resolute modes -d <current-display>. "
            + "Use the current display and mode IDs with resolute set --mode-id <current-mode> -d <current-display> --session. "
            + "Do not reuse IDs from before the reconnect; add --all and --allow-hidden if the previous mode was hidden."
    }

    /// Reads a complete answer within one deadline. Reading bytes from the polled file
    /// descriptor avoids readLine() blocking past the deadline after partial input. The
    /// prompt goes to `output`.
    static func askToKeep(
        seconds: Int = 15, input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO, isTerminal: Bool? = nil,
        interrupts: Interrupts = .process
    ) -> ModeSwitcher.Decision {
        guard isTerminal ?? (isatty(input) != 0) else {
            return .revert
        }
        // A terminal signal can flush input between poll and read. Nonblocking reads
        // keep that race inside the same deadline instead of waiting for another line.
        let originalFlags = fcntl(input, F_GETFL)
        guard originalFlags >= 0, fcntl(input, F_SETFL, originalFlags | O_NONBLOCK) == 0 else { return .revert }
        defer { _ = fcntl(input, F_SETFL, originalFlags) }
        let prompt = FileHandle(fileDescriptor: output, closeOnDealloc: false)
        prompt.write(Data("Keep this display mode? Type y and press Return within \(seconds) seconds; anything else reverts: ".utf8))
        // Ctrl-C is "no": the trial must be undone, which ending the process would not do.
        let deadline = ContinuousClock.now + .seconds(seconds)
        var bytes: [UInt8] = []
        while ContinuousClock.now < deadline {
            let left = (deadline - ContinuousClock.now).components
            let remaining = Double(left.seconds) + Double(left.attoseconds) / 1e18
            guard interrupts.wait(remaining, orFor: input) == .input else { break }
            var byte: UInt8 = 0
            let count = read(input, &byte, 1)
            if count < 0, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
            guard count == 1 else { break }
            if byte == 10 || byte == 13 {
                guard ContinuousClock.now < deadline else { break }
                let answer = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces).lowercased()
                return answer == "y" || answer == "yes" ? .keep : .revert
            }
            guard bytes.count < 128 else { break }
            bytes.append(byte)
        }
        prompt.write(Data("\n".utf8))
        return .revert
    }
}

// MARK: - Asking a person

extension SetCommand {
    /// Who keeps or reverts a hidden mode on trial.
    enum Asker {
        /// The app's dialog on the display being tried, which counts down `trialSeconds`.
        case app(AgentChannelClient, trialSeconds: Int)
        /// The prompt in this terminal.
        case terminal
    }

    /// How a hidden mode on trial was answered.
    struct Answer {
        var decision: ModeSwitcher.Decision
        /// "person" when a person kept the mode.
        var keptBy: String?
        /// Why the mode was reverted, in words: "no answer in 15 s".
        var reason: String?
        /// Whether the text output tells the reason: what happened at the display is news
        /// to whoever runs the command, an answer typed here is not.
        var isToldInText = true
        /// Why History says the mode was put back. The terminal can't tell a "no" from no
        /// answer; the app's dialog can.
        var revertReason: HistoryEntry.RevertReason = .unspecified

        /// A kept hidden mode lasts until logout at most, so that is how long it is kept.
        static let keptByPerson = Answer(decision: .keepForSession, keptBy: "person")

        static func reverted(_ reason: String, because revertReason: HistoryEntry.RevertReason = .unspecified) -> Answer {
            Answer(decision: .revert, reason: reason, revertReason: revertReason)
        }
    }

    /// Finds who can keep a hidden mode, before anything changes: the app when it says
    /// hello, else the terminal. Throws when there is neither.
    static func asker(in context: CommandContext) throws -> Asker {
        var appProblem: String?
        if let app = context.app {
            switch app.checkApp() {
            case .ready(let ready): return .app(app, trialSeconds: ready.trialSeconds)
            case .notRunning: break
            case .unavailable(let reason): appProblem = reason
            case .refused(let reason):
                // The person's choice in Resolute holds in a terminal too.
                throw ResoluteError.usage("\(reason) No display settings changed.")
            }
        }
        guard context.canConfirmHiddenMode else {
            throw ResoluteError.usage(appProblem.map {
                "A person must keep a hidden mode, but the Resolute app can't ask right now: \($0) "
                    + "Run the command in an interactive terminal instead. No display settings changed."
            } ?? "A person must keep a hidden mode: open the Resolute app, which asks on the display, "
                + "or run the command in an interactive terminal. No display settings changed.")
        }
        if let appProblem {
            context.writeError("The Resolute app can't ask right now: \(appProblem) Asking here instead.")
        }
        return .terminal
    }

    static func ask(_ asker: Asker, about request: ConfirmHiddenModeRequest?, in context: CommandContext) -> Answer {
        guard case .app(let app, _) = asker, let request else { return askInTerminal(context) }
        return askApp(app, request, in: context)
    }

    static func askInTerminal(_ context: CommandContext) -> Answer {
        switch context.confirmHiddenMode() {
        case .keep, .keepForSession:
            return .keptByPerson
        case .revert:
            var answer = Answer.reverted("not kept")
            answer.isToldInText = false
            return answer
        }
    }

    /// Asks the app to show its dialog on the display, then waits for a person's answer, the
    /// end of the trial or Ctrl-C, whichever comes first. Anything but a person's Keep
    /// reverts; the app is told when its dialog is no longer needed.
    static func askApp(_ app: AgentChannelClient, _ request: ConfirmHiddenModeRequest, in context: CommandContext) -> Answer {
        let noAnswer = "no answer in \(request.trialSeconds) s"
        // Ctrl-C during the switch: the mode goes back without a dialog.
        guard context.interrupts.wait(0) != .interrupted else { return .reverted("interrupted") }
        let pending: PendingAnswer
        do {
            pending = try app.ask(request)
        } catch {
            // The app quit after it said hello.
            guard context.canConfirmHiddenMode else {
                return .reverted("the Resolute app could not ask: \(error.localizedDescription)")
            }
            context.writeError("The Resolute app can't ask right now: \(error.localizedDescription) Asking here instead.")
            return askInTerminal(context)
        }
        defer { pending.close() }
        context.writeError("Waiting up to \(request.trialSeconds) s for someone at the display to keep it…")
        let deadline = ContinuousClock.now + .seconds(request.trialSeconds) + app.answerGrace
        while true {
            let left = deadline - ContinuousClock.now
            guard left > .zero else {
                pending.dismiss(.stoppedWaiting)
                return .reverted(noAnswer, because: .noAnswer)
            }
            let seconds = Double(left.components.seconds) + Double(left.components.attoseconds) / 1e18
            switch context.interrupts.wait(seconds, orFor: pending.fileDescriptor) {
            case .interrupted:
                pending.dismiss(.interrupted)
                return .reverted("interrupted")
            case .timedOut:
                continue
            case .input:
                switch pending.readAnswer() {
                case .waiting:
                    continue
                case .answered(let response) where response.answer == .keep && response.by == .person:
                    return .keptByPerson
                case .answered(let response) where response.by == .person:
                    return .reverted(response.reason ?? "reverted by person", because: .declined)
                case .answered(let response):
                    // The dialog's own countdown ran out, or the app reverted for a reason of its own.
                    let timedOut = response.reason == nil || response.reason == noAnswer
                    return .reverted(response.reason ?? noAnswer, because: timedOut ? .noAnswer : .unspecified)
                case .failed(.refused(let problem)):
                    return .reverted("the Resolute app turned the request down: \(problem.message)")
                case .failed(.closedWithoutAnswer):
                    return .reverted("the Resolute app closed without an answer")
                case .failed:
                    // Such as a keep that does not come from a person.
                    return .reverted("the Resolute app's answer could not be read")
                }
            }
        }
    }
}

// MARK: - JSON

extension SetCommand {
    /// What `set --json` prints. Every key is always present, null when it does not apply,
    /// as docs/json.md describes.
    struct Summary: Encodable {
        enum Result: String, Encodable {
            /// Switched without a trial, or already in use.
            case applied
            /// A person kept the hidden mode on trial.
            case kept
            /// The previous mode is back.
            case reverted
        }

        var display: String
        var mode: String
        var hidden: Bool
        /// Nil on a dry run, which changes nothing.
        var result: Result?
        var keptBy: String?
        var until: String?
        var reason: String?
        var restored: String?

        init(display: Display, mode: DisplayMode) {
            self.display = display.name
            self.mode = Self.size(of: mode)
            hidden = mode.origin == .hidden
        }

        /// "2880x1620", as `resolute set` takes it.
        static func size(of mode: DisplayMode) -> String {
            "\(mode.width)x\(mode.height)"
        }

        /// Records a trial that was undone, leaving the display in `restored`.
        mutating func revert(_ answer: Answer?, restored: DisplayMode?) {
            result = .reverted
            reason = answer?.reason
            self.restored = restored.map(Self.size(of:))
        }

        enum CodingKeys: String, CodingKey {
            case display, mode, hidden, result, keptBy, until, reason, restored
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(display, forKey: .display)
            try container.encode(mode, forKey: .mode)
            try container.encode(hidden, forKey: .hidden)
            try container.encode(result, forKey: .result)
            try container.encode(keptBy, forKey: .keptBy)
            try container.encode(until, forKey: .until)
            try container.encode(reason, forKey: .reason)
            try container.encode(restored, forKey: .restored)
        }
    }
}
