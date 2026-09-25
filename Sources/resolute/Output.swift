import Foundation
import ResoluteKit

/// Text and JSON formatting shared by the commands.
enum Output {
    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// "1728 × 1117 HiDPI (3456 × 2234 px) @ 120 Hz, mode 54"
    static func describe(_ mode: DisplayMode) -> String {
        var text = mode.sizeText
        if mode.isHiDPI { text += " HiDPI (\(mode.pixelSizeText) px)" }
        let rate = RefreshRate.format(mode.refreshRate)
        if !rate.isEmpty { text += " @ \(rate)" }
        text += ", mode \(mode.modeID)"
        if mode.origin == .hidden { text += ", hidden" }
        return text
    }

    /// Left-aligned columns separated by two spaces.
    static func table(_ rows: [[String]], indent: String = "") -> String {
        var widths: [Int] = []
        for row in rows {
            for (column, cell) in row.enumerated() {
                if column < widths.count {
                    widths[column] = max(widths[column], cell.count)
                } else {
                    widths.append(cell.count)
                }
            }
        }
        return rows.map { row in
            var line = indent
            for (column, cell) in row.enumerated() {
                line += cell
                if column < row.count - 1 {
                    line += String(repeating: " ", count: widths[column] - cell.count + 2)
                }
            }
            while line.hasSuffix(" ") { line.removeLast() }
            return line
        }.joined(separator: "\n")
    }

    static func hex(_ value: UInt32) -> String {
        String(value, radix: 16)
    }

    /// True for text shaped like WIDTHxHEIGHT, as opposed to a stray word or number.
    static func looksLikeSize(_ text: String) -> Bool {
        text.lowercased().contains { $0 == "x" || $0 == "×" }
    }

    /// `text`, quoted for a shell when it needs to be.
    static func shellWord(_ text: String) -> String {
        let plain = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:/@"))
        return text.unicodeScalars.allSatisfy(plain.contains) && !text.isEmpty ? text : Shell.quote(text)
    }

    /// Whether hidden modes can be used on `display`, for JSON output.
    static func hiddenModes(_ display: Display) -> String {
        switch display.privateModes {
        case .trusted: "available"
        case .unavailable: "unavailable"
        case .untrusted(let reason): "ignored: \(reason)"
        }
    }
}
