import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Records a shortcut that works from anywhere: the panel's in Settings, a preset's on the
/// Presets page. Nil means no shortcut.
///
/// At rest it shows the shortcut as Figma writes it (Settings › General draws "⌃⌥R" as a
/// form row's value). Clicking it records: the next key pressed with Control, Option or
/// Command becomes the shortcut, Esc cancels and Delete clears. A shortcut the panel or
/// another preset has is refused with a line that says which. While it records, the
/// shortcuts that work from anywhere are paused, so pressing one records it instead of
/// running it.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    /// How the shortcut is drawn at rest.
    var style: ShortcutLabel.Style
    /// What already uses a shortcut, said in a sentence; nil when it is free.
    var conflict: (KeyShortcut) -> String?
    /// Called when recording ends, with a new shortcut or without.
    var onFinish: (() -> Void)?

    @State private var isRecording: Bool
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    @State private var message: String?

    init(
        shortcut: Binding<KeyShortcut?>,
        style: ShortcutLabel.Style = .formRow,
        startsRecording: Bool = false,
        conflict: @escaping (KeyShortcut) -> String? = { _ in nil },
        onFinish: (() -> Void)? = nil
    ) {
        self.init(
            shortcut: shortcut, style: style, startsRecording: startsRecording, message: nil,
            conflict: conflict, onFinish: onFinish
        )
    }

    /// For the gallery: a recorder already recording, with the line it shows after a refusal.
    init(
        shortcut: Binding<KeyShortcut?>,
        style: ShortcutLabel.Style,
        startsRecording: Bool,
        message: String?,
        conflict: @escaping (KeyShortcut) -> String? = { _ in nil },
        onFinish: (() -> Void)? = nil
    ) {
        _shortcut = shortcut
        self.style = style
        self.conflict = conflict
        self.onFinish = onFinish
        _isRecording = State(initialValue: startsRecording)
        _message = State(initialValue: message)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Metrics.Spacing.xSmall) {
            Button(action: toggleRecording) {
                label
            }
            .buttonStyle(.plain)
            .background {
                KeyCatcher(
                    isActive: isRecording,
                    onKey: handle,
                    onModifiers: { heldModifiers = $0.intersection(ShortcutCapture.shortcutModifiers) },
                    onResign: { finish() }
                )
            }
            .help(isRecording ? Self.recordingHelp : Self.restingHelp)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isRecording ? Self.recordingHelp : Self.restingHelp)
            .accessibilityAction(named: "Clear Shortcut") {
                shortcut = nil
                finish()
            }
            if isRecording, let message {
                Text(message)
                    .textStyle(.footnote)
                    .foregroundStyle(Palette.warningText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onChange(of: isRecording) { _, recording in
            ShortcutRecording.post(recording ? ShortcutRecording.didBegin : ShortcutRecording.didEnd)
        }
        .onAppear {
            if isRecording { ShortcutRecording.post(ShortcutRecording.didBegin) }
        }
        .onDisappear {
            if isRecording { ShortcutRecording.post(ShortcutRecording.didEnd) }
        }
    }

    @ViewBuilder private var label: some View {
        if isRecording {
            Text(heldModifiers.isEmpty ? Self.prompt : ShortcutLabel.text(key: "", modifiers: heldModifiers))
                .textStyle(style == .chip ? .footnoteEmphasized : .body)
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
                .padding(.horizontal, Metrics.ShortcutChip.horizontalPadding)
                .padding(.vertical, Metrics.ShortcutChip.verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.ShortcutChip.cornerRadius, style: .continuous)
                        .fill(Palette.surfaceAccentTint)
                )
        } else if let shortcut {
            ShortcutLabel(shortcut.displayText, style: style)
                .contentShape(Rectangle())
        } else {
            Text(Self.none)
                .textStyle(style == .chip ? .footnoteEmphasized : .body)
                .foregroundStyle(Palette.labelTertiary)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
    }

    /// "Shortcut, Control-Option-R", "Shortcut, none", "Recording shortcut".
    private var accessibilityLabel: String {
        if isRecording { return "Recording shortcut" }
        return "Shortcut, " + (shortcut?.spokenText ?? "none")
    }

    private func toggleRecording() {
        if isRecording {
            finish()
        } else {
            message = nil
            heldModifiers = []
            isRecording = true
        }
    }

    private func handle(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        switch ShortcutCapture.handle(keyCode: keyCode, modifierFlags: modifierFlags, conflict: conflict) {
        case .record(let recorded):
            shortcut = recorded
            finish()
        case .cancel:
            finish()
        case .clear:
            shortcut = nil
            finish()
        case .refuse(let reason):
            message = reason
        }
    }

    private func finish() {
        guard isRecording else { return }
        isRecording = false
        message = nil
        heldModifiers = []
        onFinish?()
    }

    static let prompt = "Type Shortcut"
    static let none = "None"
    static let restingHelp = "Click to record a new shortcut."
    static let recordingHelp = "Press keys with Control, Option or Command. Esc cancels; Delete removes the shortcut."
}

/// Tells the shortcuts that work from anywhere to pause while a recorder records, so a key
/// pressed into the recorder isn't taken by one of them.
enum ShortcutRecording {
    static let didBegin = Notification.Name("ResoluteShortcutRecordingDidBegin")
    static let didEnd = Notification.Name("ResoluteShortcutRecordingDidEnd")

    static func post(_ name: Notification.Name, center: NotificationCenter = .default) {
        center.post(name: name, object: nil)
    }
}

/// The view that takes the keyboard while the recorder records: every key goes to it,
/// key equivalents such as ⌘Q included, so a shortcut can use ⌘.
private struct KeyCatcher: NSViewRepresentable {
    var isActive: Bool
    var onKey: (UInt16, NSEvent.ModifierFlags) -> Void
    var onModifiers: (NSEvent.ModifierFlags) -> Void
    var onResign: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        KeyCatcherView()
    }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.onKey = onKey
        view.onModifiers = onModifiers
        view.onResign = onResign
        guard view.isActive != isActive else { return }
        view.isActive = isActive
        if isActive {
            // The view may not be in its window yet, and SwiftUI may be moving focus to the
            // button that was clicked; take the keyboard after both.
            Task { @MainActor [weak view] in
                guard let view, view.isActive, let window = view.window else { return }
                // A popover's window takes the keyboard only once it is key.
                if NSApp.isActive, window.canBecomeKey, !window.isKeyWindow { window.makeKey() }
                window.makeFirstResponder(view)
            }
        } else if view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }
}

final class KeyCatcherView: NSView {
    var isActive = false
    var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onModifiers: ((NSEvent.ModifierFlags) -> Void)?
    var onResign: (() -> Void)?

    override var acceptsFirstResponder: Bool { isActive }

    override func keyDown(with event: NSEvent) {
        guard isActive else { return super.keyDown(with: event) }
        if !event.isARepeat { onKey?(event.keyCode, event.modifierFlags) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isActive, window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        if !event.isARepeat { onKey?(event.keyCode, event.modifierFlags) }
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        if isActive { onModifiers?(event.modifierFlags) }
        super.flagsChanged(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, isActive {
            // Clicking elsewhere ends recording, as Esc does.
            isActive = false
            onResign?()
        }
        return resigned
    }
}
