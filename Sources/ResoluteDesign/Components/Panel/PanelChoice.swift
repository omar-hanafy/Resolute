/// One option in a panel control: a refresh rate, a stop on the "Larger Text ↔ More Space"
/// strip, a resolution in a pop-up, a tab, a preset. Each choice carries what choosing it
/// does, so the panel never needs the app's types to say which one was picked.
public struct PanelChoice {
    /// What the control shows: "120 Hz", "1728 × 1117", "HiDPI", "Coding".
    public var title: String
    public var isSelected: Bool
    /// What VoiceOver reads, when the title alone doesn't say it. Defaults to the title with
    /// sizes read as "by".
    public var accessibilityLabel: String?
    public var select: () -> Void

    public init(_ title: String, isSelected: Bool = false, accessibilityLabel: String? = nil, select: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.accessibilityLabel = accessibilityLabel
        self.select = select
    }

    /// The label VoiceOver reads for the choice.
    var spokenLabel: String {
        accessibilityLabel ?? PanelSpeech.text(title)
    }
}

extension Array where Element == PanelChoice {
    /// The position of the first selected choice, if any is selected.
    var selectedIndex: Int? {
        firstIndex(where: \.isSelected)
    }
}
