import CoreGraphics
import Foundation

/// How a person names a display on the command line.
public enum DisplaySelector: Hashable, Sendable, CustomStringConvertible {
    case main
    /// A position in the list `resolute displays` prints.
    case index(Int)
    case id(CGDirectDisplayID)
    /// Part of the display's name, case-insensitive.
    case name(String)

    /// Reads "main", "id:<number>", a list index, or anything else as a name.
    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()
        if lowercased == "main" {
            self = .main
        } else if lowercased.hasPrefix("id:"), let id = CGDirectDisplayID(trimmed.dropFirst(3)) {
            self = .id(id)
        } else if let index = Int(trimmed) {
            self = .index(index)
        } else {
            self = .name(trimmed)
        }
    }

    public var description: String {
        switch self {
        case .main: "main"
        case .index(let index): "\(index)"
        case .id(let id): "id:\(id)"
        case .name(let name): name
        }
    }

    public func resolve(in displays: [Display]) throws -> Display {
        guard !displays.isEmpty else { throw ResoluteError.noDisplays }
        switch self {
        case .main:
            return displays.first(where: \.isMain) ?? displays[0]
        case .index(let index):
            guard displays.indices.contains(index) else { throw ResoluteError.displayNotFound(description) }
            return displays[index]
        case .id(let id):
            guard let display = displays.first(where: { $0.id == id }) else {
                throw ResoluteError.displayNotFound(description)
            }
            return display
        case .name(let name):
            if let exact = displays.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                return exact
            }
            let matches = displays.filter { $0.name.localizedCaseInsensitiveContains(name) }
            guard !matches.isEmpty else { throw ResoluteError.displayNotFound(name) }
            guard matches.count == 1 else {
                throw ResoluteError.ambiguousDisplay(name, matches: matches.map(\.name))
            }
            return matches[0]
        }
    }
}
