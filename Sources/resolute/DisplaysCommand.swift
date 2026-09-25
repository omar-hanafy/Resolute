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

/// A display without its full mode list, for `displays --json`. Like every JSON object the
/// commands print, it has every key, with null for a missing value.
struct DisplaySummary: Encodable {
    let index: Int
    let id: UInt32
    let name: String
    /// In hex, as `--vendor`, `--product` and override file names take them.
    let vendorID: String
    let productID: String
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
        vendorID = Output.hex(display.vendorID)
        productID = Output.hex(display.productID)
        serialNumber = display.serialNumber
        isMain = display.isMain
        isBuiltin = display.isBuiltin
        isInMirrorSet = display.isInMirrorSet
        currentMode = display.currentMode
        modeCount = display.modes.count
        hiddenModeCount = display.hiddenModeCount
        hiddenModes = Output.hiddenModes(display)
    }

    enum CodingKeys: String, CodingKey {
        case index, id, name, vendorID, productID, serialNumber, isMain, isBuiltin, isInMirrorSet, currentMode, modeCount,
             hiddenModeCount, hiddenModes
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(vendorID, forKey: .vendorID)
        try container.encode(productID, forKey: .productID)
        try container.encode(serialNumber, forKey: .serialNumber)
        try container.encode(isMain, forKey: .isMain)
        try container.encode(isBuiltin, forKey: .isBuiltin)
        try container.encode(isInMirrorSet, forKey: .isInMirrorSet)
        try container.encode(currentMode, forKey: .currentMode)
        try container.encode(modeCount, forKey: .modeCount)
        try container.encode(hiddenModeCount, forKey: .hiddenModeCount)
        try container.encode(hiddenModes, forKey: .hiddenModes)
    }
}
