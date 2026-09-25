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
        discussion: "A hidden mode requires an interactive terminal. You have 15 seconds to type y to keep it; otherwise the previous mode comes back."
    ))
    var allowHidden = false

    @Flag(help: "Show what would change without changing it.")
    var dryRun = false

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
            context.write("\(display.name) is already at \(Output.describe(mode)).")
            return
        }
        guard !dryRun else {
            context.write("Would switch \(display.name) to \(Output.describe(mode)).")
            return
        }
        guard mode.origin != .hidden || context.canConfirmHiddenMode else {
            throw ResoluteError.usage("A hidden mode requires an interactive terminal for its Keep/Revert confirmation. No display settings changed.")
        }
        // Hidden modes are tried for the session and kept only when confirmed; --session
        // only limits how long a confirmed mode lasts.
        let trial = session || mode.origin == .hidden
        let switcher = ModeSwitcher(service: service)
        // Until the trial is over, Ctrl-C answers it rather than leaving the mode in place.
        try context.interrupts.catchingControlC {
            let outcome = try switcher.apply(modeID: mode.modeID, to: display.id, trial: trial) {
                guard mode.origin == .hidden else { return .keepForSession }
                let decision = context.confirmHiddenMode()
                return session && decision == .keep ? .keepForSession : decision
            }
            try report(outcome, of: mode, on: display, with: switcher, in: context)
        }
    }

    /// Says how the switch ended, waiting first for a display that went away mid-trial.
    private func report(
        _ outcome: ModeSwitcher.Outcome, of mode: DisplayMode, on display: Display, with switcher: ModeSwitcher,
        in context: CommandContext
    ) throws {
        let service = context.service
        switch outcome {
        case .alreadyCurrent:
            context.write("\(display.name) is already at \(Output.describe(mode)).")
        case .applied, .kept, .keptForSession:
            // The full snapshot, since CoreGraphics may not name a hidden mode in use.
            guard switcher.currentModeID(of: display.id) == mode.modeID else {
                let isGone = !service.displays().contains { $0.id == display.id }
                context.writeError(isGone
                    ? "warning: \(display.name) went away, so its new mode could not be checked."
                    : "warning: macOS accepted the change but reports a different mode now.")
                return
            }
            let until = outcome == .keptForSession ? " (until you log out)" : ""
            context.write("\(display.name): \(Output.describe(mode))\(until)")
        case .reverted(let modeID):
            let restored = display.modes.first { $0.modeID == modeID }
            context.write("Kept the previous mode: \(restored.map(Output.describe) ?? "mode \(modeID)").")
        case .leftAlone(let current):
            let shown = display.modes.first { $0.modeID == current }
            context.write("\(display.name) was showing \(shown.map(Output.describe) ?? "mode \(current)"), when you answered, so it was left as it is.")
        case .restorePending(let pending):
            try Self.finishRestore(pending, with: switcher, on: display, in: context)
        }
    }

    /// Waits for a display that went away during a trial to come back, undoes the trial
    /// and says how the display came back. A command gets no display notifications, so it
    /// looks every `restorePollInterval` until `restoreTimeout`, also after a failed try:
    /// a display that has only just come back may not take a mode yet.
    static func finishRestore(
        _ pending: ModeSwitcher.PendingRestore, with switcher: ModeSwitcher, on display: Display, in context: CommandContext
    ) throws {
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
        func describe(_ modeID: Int32) -> String {
            (returned ?? display).modes.first { $0.modeID == modeID }.map(Output.describe) ?? "mode \(modeID)"
        }
        func isPrevious(_ modeID: Int32) -> Bool {
            if let fingerprint = pending.previousMode, let mode = returned?.modes.first(where: { $0.modeID == modeID }) {
                return fingerprint == ModeSwitcher.ModeFingerprint(mode)
            }
            return modeID == pending.modeID
        }
        switch progress {
        case .restored(let modeID):
            let which = isPrevious(modeID) ? "the previous mode" : "its default mode"
            context.write("\(pending.displayName) is back. Restored \(which): \(describe(modeID)).")
        case .leftAlone(let current) where isPrevious(current):
            context.write("\(pending.displayName) is back with the previous mode: \(describe(current)).")
        case .leftAlone(let current):
            context.write("\(pending.displayName) is back with \(describe(current)), so it was left as it is.")
        case .waiting:
            break
        }
        // A mode that never showed is an error whether or not the display went away, once
        // the display's state is told.
        if let failure = pending.failure { throw failure }
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
    /// descriptor avoids readLine() blocking past the deadline after partial input.
    static func askToKeep(
        seconds: Int = 15, input: Int32 = STDIN_FILENO, isTerminal: Bool? = nil, interrupts: Interrupts = .process
    ) -> ModeSwitcher.Decision {
        guard isTerminal ?? (isatty(input) != 0) else {
            return .revert
        }
        // A terminal signal can flush input between poll and read. Nonblocking reads
        // keep that race inside the same deadline instead of waiting for another line.
        let originalFlags = fcntl(input, F_GETFL)
        guard originalFlags >= 0, fcntl(input, F_SETFL, originalFlags | O_NONBLOCK) == 0 else { return .revert }
        defer { _ = fcntl(input, F_SETFL, originalFlags) }
        let prompt = "Keep this display mode? Type y and press Return within \(seconds) seconds; anything else reverts: "
        FileHandle.standardOutput.write(Data(prompt.utf8))
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
        print("")
        return .revert
    }
}
