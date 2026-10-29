import SwiftUI

/// The geometry of the window components (Figma: Components › Window) that `Metrics` doesn't
/// name, in points, as Figma gives it. The window's shared sizes (group corner radius, row
/// heights, divider thickness) stay in `Metrics.Group`.
enum WindowMetrics {
    /// Sidebar Item and Sidebar Header.
    enum Sidebar {
        static let rowHeight: CGFloat = 28
        static let cornerRadius: CGFloat = 8
        static let leadingPadding: CGFloat = 8
        static let trailingPadding: CGFloat = 10
        static let spacing: CGFloat = 7
        static let symbolFrame: CGFloat = 18
        /// Draws the 18-point frame's glyph at Figma's size (`display` 15.2 × 12.8).
        static let symbolPointSize: CGFloat = 13
        /// A display that isn't connected.
        static let dimmedOpacity: Double = 0.6
        /// The header's text sits on the bottom of its 28-point row.
        static let headerInsets = EdgeInsets(top: 12, leading: 10, bottom: 4, trailing: 0)
    }

    /// The picture, name, facts and badges at the top of a display's page.
    enum DisplayHeader {
        static let pictureSize = CGSize(width: 99.2, height: 74.4)
        static let spacing: CGFloat = 18
        static let infoSpacing: CGFloat = 5
        static let badgeSpacing: CGFloat = 6
        /// The picture of a display that isn't connected.
        static let dimmedPictureOpacity: Double = 0.45
    }

    /// History's, Presets' and Settings' title and description.
    enum PageHeader {
        static let spacing: CGFloat = 18
    }

    /// A grouped section: Picture, Preview, Sharp Scaling, Credits.
    enum Section {
        static let insets = EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16)
        static let spacing: CGFloat = 12
        static let headerSpacing: CGFloat = 8
        static let symbolFrame: CGFloat = 18
        static let symbolPointSize: CGFloat = 13
    }

    /// Form Row.
    enum Form {
        static let verticalPadding: CGFloat = 10
        static let trailingPadding: CGFloat = 12
        static let spacing: CGFloat = 16
        /// Between a leading symbol, the text and the control.
        static let symbolSpacing: CGFloat = 12
        static let symbolFrame: CGFloat = 18
        static let symbolPointSize: CGFloat = 15
        static let textSpacing: CGFloat = 2
        static let chevronFrame: CGFloat = 12
        /// Draws `chevron.right` at Figma's 4.1 × 7.3 glyph.
        static let chevronPointSize: CGFloat = 8
        /// Figma's switch is the kit's at 72 %, 38.88 × 17.28.
        static let switchScale: CGFloat = 0.72
    }

    /// Space Option and Stop Picker.
    enum Space {
        static let thumbnailSize = CGSize(width: 116, height: 74)
        static let spacing: CGFloat = 7
        static let pickerInsets = EdgeInsets(top: 14, leading: 18, bottom: 16, trailing: 18)
        /// Between the header, the options and the footnote on the Resolution tab (Figma
        /// 31:5); the Sharp Scaling page (67:2175) uses 12.
        static let pickerSpacing: CGFloat = 14
        /// The least room between two options; Figma spreads them across the section.
        static let minimumGap: CGFloat = 8
    }

    /// Picture Choice and its grid.
    enum Picture {
        static let choiceSize = CGSize(width: 118, height: 110)
        static let pictureSize = CGSize(width: 96, height: 72)
        static let topPadding: CGFloat = 10
        static let spacing: CGFloat = 6
        static let cornerRadius: CGFloat = 12
        static let selectionWidth: CGFloat = 2
        static let gridSpacing: CGFloat = 12
    }

    /// Table Header, Table Row and the table's section.
    enum Table {
        static let rowHeight: CGFloat = 28
        static let horizontalPadding: CGFloat = 12
        static let rowCornerRadius: CGFloat = 6
        /// The outline of the row ↑ and ↓ are on, in a table that chooses with Return.
        static let highlightLineWidth: CGFloat = 2
        static let spacing: CGFloat = 6
        static let titleInsets = EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 6)
        static let titleSpacing: CGFloat = 8
        /// The section's edge: 12 above a title row, 8 above the header without one; 8
        /// under the last row, 10 under a footnote.
        static let sideInset: CGFloat = 8
        static let titledTopInset: CGFloat = 12
        static let footnoteBottomInset: CGFloat = 10
    }

    /// Unsaved Bar.
    enum UnsavedBar {
        static let height: CGFloat = 52
        static let leadingPadding: CGFloat = 16
        static let trailingPadding: CGFloat = 14
        static let spacing: CGFloat = 10
        static let symbolFrame: CGFloat = 16
        /// Draws `lock` at Figma's 7.6 × 11 glyph.
        static let symbolPointSize: CGFloat = 11
    }

    /// History Row.
    enum History {
        static let verticalPadding: CGFloat = 9
        static let horizontalPadding: CGFloat = 14
        static let spacing: CGFloat = 14
        static let timeWidth: CGFloat = 64
        static let symbolFrame: CGFloat = 16
        /// Draws `terminal` at Figma's 13.3 × 10.3 glyph.
        static let symbolPointSize: CGFloat = 11
        static let textSpacing: CGFloat = 1
        static let undoWidth: CGFloat = 36
    }

    /// Preset Card.
    enum Preset {
        static let cornerRadius: CGFloat = 14
        static let insets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 14)
        static let spacing: CGFloat = 14
        static let starFrame: CGFloat = 20
        /// Draws `star` at Figma's 15.6 × 14.9 glyph.
        static let starPointSize: CGFloat = 14
        static let textSpacing: CGFloat = 3
        /// The active card's outline, which Figma lays out inside the card's padding.
        static let activeOutlineWidth: CGFloat = 1.5
        static let shortcutInsets = EdgeInsets(top: 2, leading: 7, bottom: 2, trailing: 7)
        static let shortcutCornerRadius: CGFloat = 6
        static let applyInsets = EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        /// Between cards in a list.
        static let listSpacing: CGFloat = 10
    }
}
