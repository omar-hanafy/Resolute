import ArgumentParser
import Darwin
import Foundation
import ResoluteKit

struct DoctorCommand: ParsableCommand, ContextCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Print what a bug report needs: versions, displays, modes and overrides.",
        discussion: "Read-only. Paste the output into a bug report."
    )

    @OptionGroup var location: LocationOptions

    @Flag(help: "Print JSON.")
    var json = false

    func run() throws {
        try run(in: .live)
    }

    func run(in context: CommandContext) throws {
        let report = DoctorReport(displays: context.service.displays(), store: OverrideStore(locations: location.locations), system: .current)
        context.write(json ? try Output.json(report) : report.text)
    }
}

/// The Mac Resolute runs on.
struct SystemInfo {
    /// "27.0 (26A428)"
    var macOS: String
    /// "Mac14,10"
    var model: String
    var architecture: String
    /// True when an Intel build runs under Rosetta.
    var translated: Bool

    static var current: SystemInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var number = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { number += ".\(version.patchVersion)" }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let isTranslated = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        return SystemInfo(
            macOS: sysctlText("kern.osversion").map { "\(number) (\($0))" } ?? number,
            model: sysctlText("hw.model") ?? "unknown",
            architecture: architecture,
            translated: isTranslated
        )
    }

    private static func sysctlText(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// What `resolute doctor` prints.
struct DoctorReport: Encodable {
    /// Where a display's override stands.
    struct OverrideStatus: Encodable {
        /// "installed", "system" (only the file macOS ships) or "missing"
        let source: String
        let path: String?
        let entries: Int?
        let productName: String?
        let problem: String?

        init(key: OverrideKey, store: OverrideStore) {
            do {
                let file = try store.editableFile(for: key)
                switch file.source {
                case .installed:
                    source = "installed"
                    path = store.locations.userFile(for: key).path(percentEncoded: false)
                case .system:
                    source = "system"
                    path = store.locations.systemFile(for: key).path(percentEncoded: false)
                case .missing:
                    source = "missing"
                    path = nil
                }
                entries = file.override.resolutions.count
                productName = file.override.productName
                problem = nil
            } catch {
                let installed = store.locations.userFile(for: key).path(percentEncoded: false)
                if case ResoluteError.overrideUnreadable(let failed, _) = error, failed != installed {
                    source = "system"
                    path = failed
                } else {
                    source = "installed"
                    path = installed
                }
                entries = nil
                productName = nil
                problem = error.localizedDescription
            }
        }

        var text: String {
            if problem != nil { return contents }
            switch source {
            case "installed": return "installed, \(contents)"
            case "system": return "none installed; macOS ships one with \(contents)"
            default: return "none"
            }
        }

        /// "2 entries, named “Studio”", or why the file can't be read.
        var contents: String {
            if let problem { return problem }
            return (entries.map(Self.entries) ?? "") + (productName.map { ", named “\($0)”" } ?? "")
        }

        static func entries(_ count: Int) -> String {
            count == 1 ? "1 entry" : "\(count) entries"
        }

        enum CodingKeys: String, CodingKey {
            case source, path, entries, problem
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(source, forKey: .source)
            try container.encode(path, forKey: .path)
            try container.encode(entries, forKey: .entries)
            try container.encode(problem, forKey: .problem)
        }
    }

    struct DisplayStatus: Encodable {
        let display: DisplaySummary
        let override: OverrideStatus
        let backups: Int
    }

    /// An installed override whose display is not connected.
    struct OtherOverride: Encodable {
        let vendorID: String
        let productID: String
        let override: OverrideStatus
        let backups: Int

        enum CodingKeys: String, CodingKey {
            case vendorID, productID, path, entries, problem, backups
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(vendorID, forKey: .vendorID)
            try container.encode(productID, forKey: .productID)
            try container.encode(override.path, forKey: .path)
            try container.encode(override.entries, forKey: .entries)
            try container.encode(override.problem, forKey: .problem)
            try container.encode(backups, forKey: .backups)
        }
    }

    let version = ResoluteVersion.string
    let macOS: String
    let model: String
    let architecture: String
    let translated: Bool
    let privateModeFunctions: Bool
    let displays: [DisplayStatus]
    let otherOverrides: [OtherOverride]
    private let details: [Display]

    init(displays: [Display], store: OverrideStore, system: SystemInfo, privateModeFunctions: Bool = SkyLight.shared != nil) {
        macOS = system.macOS
        model = system.model
        architecture = system.architecture
        translated = system.translated
        self.privateModeFunctions = privateModeFunctions
        details = displays
        self.displays = displays.enumerated().map { index, display in
            let key = OverrideKey(display: display)
            return DisplayStatus(
                display: DisplaySummary(index: index, display: display),
                override: OverrideStatus(key: key, store: store),
                backups: store.backups(for: key).count
            )
        }
        let connected = Set(displays.map(OverrideKey.init(display:)))
        otherOverrides = store.installedKeys().filter { !connected.contains($0) }.map { key in
            OtherOverride(
                vendorID: Output.hex(key.vendorID), productID: Output.hex(key.productID),
                override: OverrideStatus(key: key, store: store), backups: store.backups(for: key).count
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case version, macOS, model, architecture, translated, privateModeFunctions, displays, otherOverrides
    }

    var text: String {
        var lines = [
            "Resolute \(version)",
            "macOS \(macOS) on \(model), \(translated ? "\(architecture) under Rosetta" : architecture)",
            "Hidden modes: the private SkyLight functions are \(privateModeFunctions ? "available" : "unavailable").",
            "",
        ]
        for (status, display) in zip(displays, details) {
            var traits = [
                "id \(display.id)", "vendor \(Output.hex(display.vendorID))", "product \(Output.hex(display.productID))",
                "serial \(display.serialNumber)",
            ]
            if display.isMain { traits.append("main") }
            if display.isBuiltin { traits.append("built-in") }
            if display.isInMirrorSet { traits.append("mirrored") }
            lines.append("\(status.display.index)  \(display.name) (\(traits.joined(separator: ", ")))")
            lines.append("   " + (display.currentMode.map(Output.describe) ?? "current mode unknown"))
            let hidden = display.hiddenModeCount == 0 ? "none hidden" : "\(display.hiddenModeCount) hidden"
            lines.append("   \(display.modes.count) modes, \(hidden); hidden modes \(Output.hiddenModes(display))")
            lines.append("   Override: \(status.override.text)\(Self.backups(status.backups))")
        }
        if !otherOverrides.isEmpty {
            lines.append("")
            lines.append("Overrides for displays that are not connected:")
            for other in otherOverrides {
                lines.append("  vendor \(other.vendorID), product \(other.productID): \(other.override.contents)\(Self.backups(other.backups))")
            }
        }
        lines.append("")
        lines.append("Recent activity: log show --last 1h --predicate 'subsystem == \"com.omarhanafy.Resolute\"'")
        return lines.joined(separator: "\n")
    }

    /// ", 2 backups", or nothing.
    static func backups(_ count: Int) -> String {
        count == 0 ? "" : count == 1 ? ", 1 backup" : ", \(count) backups"
    }
}
