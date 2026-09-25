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
        let mirroring = service.displays().contains(where: \.isInMirrorSet)
        let enable: Bool
        switch state {
        case .status:
            context.write(mirroring ? "Mirroring is on." : "Mirroring is off.")
            return
        case .on: enable = true
        case .off: enable = false
        case .toggle: enable = !mirroring
        }
        try service.setMirroring(enable)
        context.write(enable ? "Mirroring is on." : "Mirroring is off.")
    }
}
