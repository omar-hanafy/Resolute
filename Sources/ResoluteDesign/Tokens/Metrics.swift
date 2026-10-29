import CoreGraphics

/// Sizes and spacing from Figma's Foundations › Metrics, and the sizes of the shared
/// controls (Components › Shared Controls and the screens that use them).
public enum Metrics {
    /// The 4-point spacing scale. Use these rather than literals between elements.
    public enum Spacing {
        public static let xxSmall: CGFloat = 2
        public static let xSmall: CGFloat = 4
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 8
        public static let large: CGFloat = 12
        public static let xLarge: CGFloat = 16
        public static let xxLarge: CGFloat = 20
        public static let xxxLarge: CGFloat = 28
    }

    public enum MenuBar {
        /// The menu bar of the macOS 27 kit.
        public static let height: CGFloat = 34
        public static let statusItemHeight: CGFloat = 24
    }

    /// The glass panel that opens from the menu bar.
    public enum Panel {
        public static let width: CGFloat = 340
        public static let padding: CGFloat = 12
        public static let cornerRadius: CGFloat = 22
        public static let sectionSpacing: CGFloat = 8
        /// Between the menu bar and the top of the panel.
        public static let menuBarGap: CGFloat = 6
    }

    /// One display's card in the panel.
    public enum DisplayCard {
        public static let cornerRadius: CGFloat = 14
        public static let padding: CGFloat = 12
        public static let thumbnailSize = CGSize(width: 54, height: 35)
        public static let thumbnailSpacing: CGFloat = 6
    }

    /// Rows at the bottom of the panel (Mirror Displays, Settings…, Quit).
    public enum PanelRow {
        public static let height: CGFloat = 26
        public static let cornerRadius: CGFloat = 8
        public static let symbolSize: CGFloat = 16
        public static let textSize: CGFloat = 13
    }

    /// The Resolute window.
    public enum Window {
        public static let defaultSize = CGSize(width: 1040, height: 720)
        public static let minimumSize = CGSize(width: 820, height: 560)
        public static let sidebarWidth: CGFloat = 240
        public static let contentPadding: CGFloat = 28
    }

    /// Grouped forms and tables in the window.
    public enum Group {
        public static let cornerRadius: CGFloat = 12
        public static let rowHeight: CGFloat = 44
        /// A form row with a second line of help text.
        public static let tallRowHeight: CGFloat = 52
        public static let dividerThickness: CGFloat = 1
        public static let horizontalPadding: CGFloat = 14
    }

    /// The Keep/Revert dialog for a hidden mode.
    public enum Trial {
        public static let width: CGFloat = 300
        /// The macOS 27 alert's corner (Figma 28:57 draws its background at 34).
        public static let cornerRadius: CGFloat = 34
        public static let iconSize: CGFloat = 64
    }

    /// The "Switched back" and "Kept" notices.
    public enum HUD {
        public static let size = CGSize(width: 220, height: 190)
        public static let cornerRadius: CGFloat = 22
        public static let symbolSize: CGFloat = 48
        /// Between the symbol, the title and the subtitle.
        public static let spacing: CGFloat = 8
    }

    // MARK: Shared controls

    /// A small capsule label ("Default", "HiDPI", "Unsaved").
    public enum Badge {
        public static let height: CGFloat = 15
        public static let horizontalPadding: CGFloat = 6
    }

    /// One segment of a segmented control, and the capsule track around the segments.
    public enum Segment {
        public static let height: CGFloat = 21
        public static let horizontalPadding: CGFloat = 10
        public static let trackPadding: CGFloat = 2
    }

    /// A small heading over a group ("Presets" in the panel).
    public enum SectionLabel {
        /// The panel's label is inset into its section: 8 above, 4 below, 10 at the sides.
        public static let panelTopPadding: CGFloat = 8
        public static let panelBottomPadding: CGFloat = 4
        public static let panelHorizontalPadding: CGFloat = 10
    }

    /// An inline notice in the panel or the window.
    public enum Banner {
        public static let cornerRadius: CGFloat = 12
        public static let topPadding: CGFloat = 9
        public static let leadingPadding: CGFloat = 10
        public static let bottomPadding: CGFloat = 10
        public static let trailingPadding: CGFloat = 12
        /// The tone's symbol, and the frame it is drawn in.
        public static let iconSize: CGFloat = 16
        public static let iconSpacing: CGFloat = 9
        /// Between the title, the message and the action.
        public static let textSpacing: CGFloat = 3
        /// The close button's symbol frame.
        public static let dismissSize: CGFloat = 11

        /// The banner inside a panel card (the Sharp Scaling offer, Figma 60:547).
        public enum Compact {
            public static let cornerRadius: CGFloat = 10
            public static let trailingPadding: CGFloat = 8
            public static let iconSpacing: CGFloat = 10
            public static let textSpacing: CGFloat = 2
        }
    }

    /// Filled capsule buttons.
    public enum CapsuleButton {
        /// Keep and Revert in the trial dialog, which share the row.
        public static let largeHeight: CGFloat = 32
        public static let largeHorizontalPadding: CGFloat = 8
        /// Between the buttons of a dialog.
        public static let largeSpacing: CGFloat = 8
        /// Apply on a preset card.
        public static let smallHeight: CGFloat = 23
        public static let smallHorizontalPadding: CGFloat = 12
    }

    /// A keyboard shortcut drawn as a key chip ("⌃⌥1").
    public enum ShortcutChip {
        public static let horizontalPadding: CGFloat = 7
        public static let verticalPadding: CGFloat = 2
        public static let cornerRadius: CGFloat = 6
    }

    /// The trial dialog's countdown bar (the kit's medium determinate progress bar).
    public enum Countdown {
        public static let height: CGFloat = 10
        public static let strokeWidth: CGFloat = 0.5
    }
}
