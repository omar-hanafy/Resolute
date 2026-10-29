import ArgumentParser
import ResoluteKit

struct MirrorCommand: ParsableCommand, ContextCommand {
    enum State: String, ExpressibleByArgument, CaseIterable {
        case on, off, toggle, status
    }

    static let configuration = CommandConfiguration(
        commandName: "mirror",
        abstract: "Mirror every display to the main display, or stop mirroring."
    )

    @Argument(help: "on, off, toggle or status.")
    var state: State = .status

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let service = context.service
        let displays = service.displays()
        let mirroring = displays.contains(where: \.isInMirrorSet)
        let enable: Bool
        switch state {
        case .status:
            context.write(mirroring ? "Mirroring is on." : "Mirroring is off.")
            return
        case .on: enable = true
        case .off: enable = false
        case .toggle: enable = !mirroring
        }
        do {
            try service.setMirroring(enable)
        } catch {
            // As the app records a mirroring change that failed.
            context.history.recordMirroring(enable, displays: displays, failedWith: error)
            throw error
        }
        if enable != mirroring {
            context.history.recordMirroring(enable, displays: displays)
        }
        context.write(enable ? "Mirroring is on." : "Mirroring is off.")
    }
}
