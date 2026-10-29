import AppKit
import OSLog
import ResoluteKit

/// Registers shortcuts that work from anywhere with macOS and says when one is pressed.
/// `CarbonHotKeyRegistrar` in the app; a fake in tests, so they never take a key on the Mac
/// they run on.
@MainActor
protocol HotKeyRegistering: AnyObject {
    /// Called with a registered shortcut's ID when it is pressed.
    var onPress: (@MainActor (UInt32) -> Void)? { get set }
    /// Registers `shortcut` under `id`. Throws `HotKeyRefused` when macOS won't, as when
    /// another app has the shortcut.
    func register(_ shortcut: KeyShortcut, id: UInt32) throws
    func unregister(id: UInt32)
}

/// macOS would not register a shortcut.
struct HotKeyRefused: Error, Equatable {
    var shortcut: KeyShortcut
    var status: OSStatus
}

/// The shortcuts that work from anywhere: the panel's (Settings › General › Open the panel)
/// and each preset's. It follows the preferences and the presets file, registering again
/// when either changes, pauses while a shortcut recorder records, and says when macOS
/// refuses one.
@MainActor
final class HotKeyCenter {
    /// A shortcut and what it does.
    struct Assignment: Hashable {
        var shortcut: KeyShortcut
        var owner: ShortcutOwner
    }

    /// The shortcuts registered now, by ID.
    private(set) var registered: [UInt32: Assignment] = [:]
    /// The shortcuts macOS refused, which do nothing until changed.
    private(set) var refused: [Assignment] = []
    /// Whether a recorder is recording, so nothing is registered.
    var isPaused: Bool { pauses > 0 }

    /// What a pressed shortcut does: opens the panel or applies a preset.
    var perform: @MainActor (ShortcutOwner) -> Void = { _ in }
    /// Told about shortcuts macOS refused that weren't refused before. Not told at launch,
    /// when nobody has just chosen one: those are only logged.
    var onRefused: @MainActor ([Assignment]) -> Void = { _ in }

    private let registrar: any HotKeyRegistering
    private var assignments: [Assignment] = []
    private var nextID: UInt32 = 1
    private var pauses = 0
    private var hasRegistered = false
    private var observation: ObservationLoop?
    private var recordingTokens: [NotificationToken] = []
    private static let log = Logger(subsystem: ResoluteLog.subsystem, category: "shortcuts")

    init(registrar: any HotKeyRegistering, notificationCenter: NotificationCenter = .default) {
        self.registrar = registrar
        registrar.onPress = { [weak self] id in self?.pressed(id) }
        recordingTokens = [
            NotificationToken(center: notificationCenter, name: ShortcutRecording.didBegin) { [weak self] in
                self?.pause()
            },
            NotificationToken(center: notificationCenter, name: ShortcutRecording.didEnd) { [weak self] in
                self?.resume()
            },
        ]
    }

    /// Follows `model`: its panel shortcut opens the panel, each preset's applies it, and a
    /// refused shortcut is shown as an error. Registered now and again whenever they change.
    func start(model: AppModel) {
        perform = { [weak model] owner in
            guard let model else { return }
            switch owner {
            case .panel:
                model.openPanel()
            case .preset(let id):
                guard let preset = model.presets.first(where: { $0.id == id }) else { return }
                model.applyPreset(preset, from: .keyboard)
            }
        }
        onRefused = { [weak model] refused in
            guard let model else { return }
            for assignment in refused {
                model.showError(
                    HotKeyUnavailable(assignment: assignment, presetName: model.presetName(for: assignment.owner)),
                    "\(assignment.shortcut.displayText) can’t be used as a shortcut"
                )
            }
        }
        observation = ObservationLoop { [weak self, weak model] in
            guard let model else { return }
            let assignments = model.shortcutAssignments.map { Assignment(shortcut: $0.shortcut, owner: $0.owner) }
            // Registering reads nothing observable, but it can show an alert: after this pass.
            MainRunLoop.perform { [weak self] in self?.update(assignments) }
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        update([])
    }

    /// Registers `assignments` in place of the ones before. A shortcut that two of them have
    /// goes to the first. Shortcuts that stay the same stay registered; refused ones are
    /// tried again.
    func update(_ assignments: [Assignment]) {
        var seen = Set<KeyShortcut>()
        self.assignments = assignments.filter { seen.insert($0.shortcut).inserted }
        guard !isPaused else { return }
        register()
    }

    /// What pressing the shortcut registered under `id` does.
    func pressed(_ id: UInt32) {
        guard !isPaused, let assignment = registered[id] else { return }
        perform(assignment.owner)
    }

    func pause() {
        pauses += 1
        guard pauses == 1 else { return }
        for id in registered.keys { registrar.unregister(id: id) }
        registered = [:]
    }

    func resume() {
        guard pauses > 0 else { return }
        pauses -= 1
        if pauses == 0 { register() }
    }

    private func register() {
        let wanted = Set(assignments)
        for (id, assignment) in registered where !wanted.contains(assignment) {
            registrar.unregister(id: id)
            registered[id] = nil
        }
        let current = Set(registered.values)
        var refusedNow: [Assignment] = []
        for assignment in assignments where !current.contains(assignment) {
            let id = nextID
            nextID &+= 1
            do {
                try registrar.register(assignment.shortcut, id: id)
                registered[id] = assignment
            } catch {
                refusedNow.append(assignment)
            }
        }
        let newlyRefused = refusedNow.filter { !refused.contains($0) }
        refused = refusedNow
        for assignment in newlyRefused {
            Self.log.error("macOS refused the shortcut \(assignment.shortcut.spec, privacy: .public)")
        }
        if hasRegistered, !newlyRefused.isEmpty { onRefused(newlyRefused) }
        hasRegistered = true
    }
}

/// A shortcut macOS would not register, as the error alert says it.
struct HotKeyUnavailable: LocalizedError {
    var assignment: HotKeyCenter.Assignment
    /// The preset's name, for a preset's shortcut.
    var presetName: String?

    var errorDescription: String? {
        let keys = assignment.shortcut.displayText
        switch assignment.owner {
        case .panel:
            return "Another app or macOS already uses \(keys). Choose another shortcut to open the panel in Settings."
        case .preset:
            let name = presetName.map { " for “\($0)”" } ?? ""
            return "Another app or macOS already uses \(keys). Choose another shortcut\(name) in Presets."
        }
    }
}

extension AppModel {
    /// The name of the preset a shortcut belongs to; nil for the panel's.
    func presetName(for owner: ShortcutOwner) -> String? {
        guard case .preset(let id) = owner else { return nil }
        return presets.first { $0.id == id }?.name
    }
}
