import Foundation

/// Turns Sharp Scaling on and off through an `OverrideInstaller`, which backs up the file it
/// replaces. Each change reads the override afresh and is installed only if the file still
/// holds what was read, so an edit made in between is never lost: the installer throws
/// `ResoluteError.overrideChanged` instead.
public struct SharpScalingWriter: Sendable {
    public var store: OverrideStore
    public var installer: OverrideInstaller

    public init(store: OverrideStore, installer: OverrideInstaller) {
        self.store = store
        self.installer = installer
    }

    /// What turning Sharp Scaling on for `display` with `sizes` would write, without writing.
    /// When `hasChanges` is false there is nothing to write, and no password to ask for.
    public func setup(for display: Display, sizes: [SharpSize], switchTo: SharpSize?) throws -> SharpScalingSetup {
        try setup(from: store.editableFile(for: OverrideKey(display: display)), for: display, sizes: sizes, switchTo: switchTo)
    }

    /// Writes `sizes` as `display`'s sharp sizes, keeping the override's other entries and
    /// keys; see `SharpScalingSetup`. Writes nothing when the file holds them already.
    @discardableResult
    public func turnOn(for display: Display, sizes: [SharpSize], switchTo: SharpSize?) async throws -> SharpScalingSetup {
        let file = try store.editableFile(for: OverrideKey(display: display))
        let setup = try setup(from: file, for: display, sizes: sizes, switchTo: switchTo)
        guard setup.hasChanges else { return setup }
        try await installer.install(setup.override, expecting: file.installedState)
        return setup
    }

    /// How turning Sharp Scaling off for `key` would go; nil when it isn't on.
    public func removal(for key: OverrideKey) throws -> SharpScalingRemoval? {
        try store.installedOverride(for: key).flatMap { try SharpScalingRemoval.plan(for: $0, in: store) }
    }

    /// Turns Sharp Scaling off for `key`; see `SharpScalingRemoval.plan(for:in:)`. Returns
    /// nil, changing nothing, when it isn't on.
    @discardableResult
    public func turnOff(for key: OverrideKey) async throws -> SharpScalingRemoval? {
        let file = try store.editableFile(for: key)
        guard file.source == .installed, let removal = try SharpScalingRemoval.plan(for: file.override, in: store) else {
            return nil
        }
        switch removal {
        case .restore(_, let contents):
            try await installer.install(contents: contents, for: key, expecting: file.installedState)
        case .remove:
            try await installer.remove(key, expecting: file.installedState)
        case .strip(let override, _):
            try await installer.install(override, expecting: file.installedState)
        }
        return removal
    }

    private func setup(
        from file: OverrideStore.EditableOverride, for display: Display, sizes: [SharpSize], switchTo: SharpSize?
    ) throws -> SharpScalingSetup {
        try SharpScalingSetup(
            file: file,
            sizes: sizes,
            offered: sizes.filter { SharpScalingStatus.isOffered($0, on: display) },
            switchTo: switchTo,
            now: installer.now()
        )
    }
}
