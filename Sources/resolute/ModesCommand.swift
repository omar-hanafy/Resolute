import ArgumentParser
import ResoluteKit

struct ModesCommand: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "modes",
        abstract: "List a display's modes.",
        discussion: "Resolutions are grouped with their refresh rates; * marks the current mode."
    )

    @OptionGroup var target: DisplayOptions

    @Flag(help: "Include hidden modes that only the private SkyLight API lists.")
    var all = false

    @Flag(help: "One line per mode, with mode IDs and flags.")
    var raw = false

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let display = try target.resolve(in: context.service.displays())
        let modes = display.modes.filter { all || $0.origin == .system }
        if json {
            context.write(try Output.json(modes))
            return
        }
        context.write("\(display.name): \(modes.count) modes\(Self.hiddenNote(for: display, all: all))")
        if raw {
            context.write(Self.rawTable(modes, currentModeID: display.currentModeID))
            return
        }
        let currentKey = ModeCatalog.currentKey(for: display)
        for section in ModeCatalog.sections(for: display, includeLowResolution: true, includeHidden: all) {
            context.write("  \(section.kind.title)")
            let rows = section.groups.map { group -> [String] in
                let isCurrent = group.key == currentKey
                let rates = group.refreshRates.filter { $0 > 0 }.map { rate -> String in
                    let number = RefreshRate.format(rate).replacingOccurrences(of: " Hz", with: "")
                    return isCurrent && RefreshRate.key(rate) == display.currentMode?.refreshKey ? number + "*" : number
                }
                var notes: [String] = []
                if group.isDefault { notes.append("default") }
                if group.isNative { notes.append("native") }
                return [
                    isCurrent ? "*" : " ",
                    group.sizeText,
                    group.isHiDPI ? "\(group.pixelSizeText) px" : "",
                    rates.isEmpty ? "" : rates.joined(separator: ", ") + " Hz",
                    notes.joined(separator: ", "),
                ]
            }
            context.write(Output.table(rows, indent: "  "))
        }
    }

    static func hiddenNote(for display: Display, all: Bool) -> String {
        switch display.privateModes {
        case .trusted:
            display.hiddenModeCount > 0 && !all ? " (+\(display.hiddenModeCount) hidden; add --all)" : ""
        case .untrusted(let reason):
            all ? " (hidden modes ignored: \(reason))" : ""
        case .unavailable:
            all ? " (hidden modes are unavailable on this system)" : ""
        }
    }

    static func rawTable(_ modes: [DisplayMode], currentModeID: Int32?) -> String {
        let sorted = modes.sorted {
            ($0.width, $0.height, $0.pixelWidth, $0.refreshKey) > ($1.width, $1.height, $1.pixelWidth, $1.refreshKey)
        }
        return Output.table(sorted.map { mode in
            [
                mode.modeID == currentModeID ? "*" : " ",
                "\(mode.modeID)",
                mode.sizeText,
                "\(mode.pixelSizeText) px",
                String(format: "%gx", mode.scale),
                RefreshRate.format(mode.refreshRate),
                mode.bitsPerSample.map { "\($0)-bit" } ?? "",
                String(format: "0x%08x", mode.ioFlags),
                mode.origin == .hidden ? "hidden" : "",
            ]
        }, indent: "  ")
    }
}
