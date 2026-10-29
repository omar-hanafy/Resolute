import Foundation

/// The saved presets, in their order, and the entries of the file that could not be read.
/// Those stay in their place, so writing the file back never loses them. Changes go
/// through `PresetStore.update(_:)`, which reads and writes the file under a lock.
public struct PresetLibrary: Hashable, Sendable {
    /// An entry of the file that is not a preset this version can read.
    public struct Problem: Hashable, Sendable {
        /// Its position among the file's entries, from 0.
        public var index: Int
        /// Its name, when it has one.
        public var name: String?
        /// Why it could not be read: "“displays.0.width” has the wrong type".
        public var reason: String
    }

    enum Entry: Hashable, Sendable {
        case preset(Preset)
        case unreadable(JSONValue, reason: String)

        var readable: Preset? {
            if case .preset(let preset) = self { return preset }
            return nil
        }
    }

    var entries: [Entry]
    /// The format version of the file it was read from. A newer file than this version
    /// writes is read as well as it can be, but never written.
    public private(set) var version: Int

    public init(presets: [Preset] = []) {
        self.init(entries: presets.map(Entry.preset), version: PresetFile.version)
    }

    init(entries: [Entry], version: Int) {
        self.entries = entries
        self.version = version
    }

    /// Reads presets from the contents of a presets file, as the store does; `path` names
    /// the file in errors. For importing a file someone saved elsewhere.
    public init(data: Data, path: String) throws {
        do {
            self = try PresetFile.library(from: data)
        } catch let error as PresetFile.Malformed {
            throw PresetError.unreadableFile(path: path, reason: error.reason)
        }
    }

    /// The contents of a presets file holding these presets, as the store writes it; for
    /// exporting presets to use on another Mac.
    public func data() throws -> Data {
        try PresetFile.data(for: self)
    }

    /// The presets that could be read, in their saved order.
    public var presets: [Preset] {
        entries.compactMap(\.readable)
    }

    public var problems: [Problem] {
        entries.enumerated().compactMap { index, entry in
            guard case .unreadable(let raw, let reason) = entry else { return nil }
            return Problem(index: index, name: raw.name, reason: reason)
        }
    }

    public func preset(named name: String) -> Preset? {
        presets.first { PresetName.same($0.name, name) }
    }

    public func preset(id: UUID) -> Preset? {
        presets.first { $0.id == id }
    }

    /// The preset with this name, ignoring case. Throws `notFound`, with the names close
    /// to it, when there is none.
    public func find(named name: String) throws -> Preset {
        guard let preset = preset(named: name) else {
            throw PresetError.notFound(name, suggestions: PresetName.suggestions(for: name, among: presets.map(\.name)))
        }
        return preset
    }

    /// `base` when no preset has that name, else the first of "base 2", "base 3", … that is
    /// free, with `base` shortened when the number would make the name too long.
    public func availableName(_ base: String) -> String {
        guard preset(named: base) != nil else { return base }
        var number = 2
        while true {
            let suffix = " \(number)"
            let name = base.prefix(PresetName.maximumLength - suffix.count).trimmingCharacters(in: .whitespaces) + suffix
            if preset(named: name) == nil { return name }
            number += 1
        }
    }

    /// Adds `preset` at the end. It keeps its ID unless another preset has it already, as
    /// a preset imported twice does; then it gets a new one.
    @discardableResult
    public mutating func add(_ preset: Preset) throws -> Preset {
        var preset = preset
        preset.name = try PresetName.validated(preset.name)
        guard !preset.displays.isEmpty || preset.mirroring != nil else { throw PresetError.nothingToSave(reasons: []) }
        if let taken = self.preset(named: preset.name) { throw PresetError.nameTaken(taken.name) }
        if let shortcut = preset.shortcut, let other = presets.first(where: { $0.shortcut == shortcut }) {
            throw PresetError.shortcutTaken(shortcut, by: other.name)
        }
        if self.preset(id: preset.id) != nil { preset.id = UUID() }
        entries.append(.preset(preset))
        return preset
    }

    /// Saves `capture` as the preset named `name`. A new preset goes at the end. With
    /// `replacing`, a preset of that name keeps its ID, name, shortcut and place and takes
    /// the captured setup; without it, the name being taken is an error.
    public mutating func save(
        _ capture: PresetCapture, named name: String, replacing: Bool
    ) throws -> (preset: Preset, replaced: Bool) {
        let name = try PresetName.validated(name)
        guard !capture.isEmpty else { throw PresetError.nothingToSave(reasons: capture.leftOut.map(\.message)) }
        guard let existing = preset(named: name) else {
            return (try add(Preset(name: name, displays: capture.displays, mirroring: capture.mirroring)), false)
        }
        guard replacing else { throw PresetError.nameTaken(existing.name) }
        var replaced = existing
        replaced.displays = capture.displays
        replaced.mirroring = capture.mirroring
        return (try update(replaced), true)
    }

    /// Puts `preset` in place of the one with its ID, as the app does after an edit. Its
    /// name must be free, apart from the preset's own, and so must its shortcut.
    @discardableResult
    public mutating func update(_ preset: Preset) throws -> Preset {
        var preset = preset
        guard let index = index(of: preset.id) else { throw PresetError.noLongerExists(preset.id) }
        preset.name = try PresetName.validated(preset.name)
        guard !preset.displays.isEmpty || preset.mirroring != nil else { throw PresetError.nothingToSave(reasons: []) }
        if let other = presets.first(where: { $0.id != preset.id && PresetName.same($0.name, preset.name) }) {
            throw PresetError.nameTaken(other.name)
        }
        if let shortcut = preset.shortcut, let other = presets.first(where: { $0.id != preset.id && $0.shortcut == shortcut }) {
            throw PresetError.shortcutTaken(shortcut, by: other.name)
        }
        entries[index] = .preset(preset)
        return preset
    }

    /// Renames the preset named `name`, ignoring case. Changing only the case is a rename too.
    @discardableResult
    public mutating func rename(_ name: String, to newName: String) throws -> Preset {
        var preset = try find(named: name)
        preset.name = newName
        return try update(preset)
    }

    /// Gives the preset with `id` a shortcut, or takes it away with nil.
    @discardableResult
    public mutating func setShortcut(_ shortcut: KeyShortcut?, forPresetWithID id: UUID) throws -> Preset {
        guard var preset = preset(id: id) else { throw PresetError.noLongerExists(id) }
        preset.shortcut = shortcut
        return try update(preset)
    }

    /// Deletes the preset named `name`, ignoring case, and returns it.
    @discardableResult
    public mutating func delete(named name: String) throws -> Preset {
        let preset = try find(named: name)
        if let index = index(of: preset.id) { entries.remove(at: index) }
        return preset
    }

    /// Deletes the preset with `id` and returns it; nil when there is none, so deleting
    /// twice is not an error.
    @discardableResult
    public mutating func delete(id: UUID) -> Preset? {
        guard let index = index(of: id) else { return nil }
        let preset = entries[index].readable
        entries.remove(at: index)
        return preset
    }

    private func index(of id: UUID) -> Int? {
        entries.firstIndex { $0.readable?.id == id }
    }
}
