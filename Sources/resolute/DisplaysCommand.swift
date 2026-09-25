import ArgumentParser
import ResoluteKit

struct DisplaysCommand: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "displays",
        abstract: "List online displays and their current modes."
    )

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let displays = context.service.displays()
        guard !displays.isEmpty else { throw ResoluteError.noDisplays }
        if json {
            context.write(try Output.json(displays.enumerated().map { DisplaySummary(index: $0.offset, display: $0.element) }))
            return
        }
        for (index, display) in displays.enumerated() {
            var traits = ["id \(display.id)", "vendor \(Output.hex(display.vendorID))", "product \(Output.hex(display.productID))"]
            if display.isMain { traits.append("main") }
            if display.isBuiltin { traits.append("built-in") }
            if display.isInMirrorSet { traits.append("mirrored") }
            context.write("\(index)  \(display.name)  (\(traits.joined(separator: ", ")))")
            context.write("   " + (display.currentMode.map(Output.describe) ?? "current mode unknown"))
        }
    }
}

/// A display without its full mode list, for `displays --json`.
struct DisplaySummary: Encodable {
    let index: Int
    let id: UInt32
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let serialNumber: UInt32
    let isMain: Bool
    let isBuiltin: Bool
    let isInMirrorSet: Bool
    let currentMode: DisplayMode?
    let modeCount: Int
    let hiddenModeCount: Int
    let hiddenModes: String

    init(index: Int, display: Display) {
        self.index = index
        id = display.id
        name = display.name
        vendorID = display.vendorID
        productID = display.productID
        serialNumber = display.serialNumber
        isMain = display.isMain
        isBuiltin = display.isBuiltin
        isInMirrorSet = display.isInMirrorSet
        currentMode = display.currentMode
        modeCount = display.modes.count
        hiddenModeCount = display.hiddenModeCount
        switch display.privateModes {
        case .trusted: hiddenModes = "available"
        case .unavailable: hiddenModes = "unavailable"
        case .untrusted(let reason): hiddenModes = "ignored: \(reason)"
        }
    }
}
