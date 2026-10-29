import CoreGraphics
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Every mode of one display, in the panel (Figma: Menu bar panel › All Resolutions 23:1079):
/// HiDPI and 1× tabs, hidden modes on request (each tried for the trial length first), and
/// the refresh rates at the size in use. With ⌥ held when the panel opened, hidden modes
/// show this once (Settings › General says so) and each row also gives its pixel size and
/// mode number.
struct AllResolutionsPage: View {
    let model: AppModel
    let display: Display
    @State private var showsLowResolution: Bool

    init(model: AppModel, display: Display) {
        self.model = model
        self.display = display
        // Open on the tab of the mode in use.
        _showsLowResolution = State(initialValue: display.currentMode.map { !$0.isHiDPI } ?? false)
    }

    /// Hidden modes are listed when Settings shows them, or once with ⌥.
    private var showsHidden: Bool {
        model.preferences.showHiddenModes || model.panelShowsDetails
    }

    var body: some View {
        let lists = AllResolutionsLists(
            display: display, showsLowResolution: showsLowResolution,
            includeLowResolution: model.preferences.showLowResolutionModes, includeHidden: showsHidden
        )
        AllResolutionsHeader(
            name: display.name,
            picture: DisplayPictureModel(rawValue: model.skin(for: display).rawValue) ?? .display,
            back: { model.panelAllResolutions = nil }
        )
        ModeList(tabs: lists.hasTabs ? [
            PanelChoice("HiDPI", isSelected: !showsLowResolution) { showsLowResolution = false },
            PanelChoice("Low Resolution (1×)", isSelected: showsLowResolution) { showsLowResolution = true },
        ] : []) {
            ForEach(lists.listed) { row in
                modeRow(row)
            }
            PanelSeparator()
            PanelRow("Show Hidden Modes", symbol: .eye, isOn: Binding(
                get: { model.preferences.showHiddenModes },
                set: { model.preferences.showHiddenModes = $0 }
            ))
            if showsHidden {
                PanelFootnote(
                    "Modes macOS doesn’t list. Each one runs for \(model.preferences.trialLength.title) first and switches back unless you keep it."
                )
                ForEach(lists.hidden) { row in
                    modeRow(row)
                }
            }
            if lists.refreshRates.count > 1 {
                PanelSeparator()
                PanelPopUpRow("Refresh Rate", symbol: .arrowTriangle2Circlepath, choices: lists.refreshRates.map { rate in
                    PanelChoice(rate.title, isSelected: rate.isSelected) {
                        MainRunLoop.perform { model.setRefreshRate(rate.value, on: display.id, from: .panel) }
                    }
                })
            }
        }
        PanelFootnote(
            model.panelShowsDetails
                ? "Mode numbers and pixel sizes are shown because ⌥ was held when you clicked the menu bar icon."
                : "Hold ⌥ while clicking the menu bar icon to also see mode numbers and pixel sizes.",
            tone: .tertiary
        )
        .padding(.bottom, Metrics.Spacing.xxSmall)
    }

    private func modeRow(_ row: AllResolutionsLists.Row) -> some View {
        ModeRow(
            row.size,
            tag: model.panelShowsDetails ? row.detailedTag : row.tag,
            aspectRatio: row.aspectRatio,
            isSelected: row.isCurrent,
            isHidden: row.isHidden
        ) {
            MainRunLoop.perform {
                // Read again: the panel may have been open across a change.
                guard let fresh = model.displays.first(where: { $0.id == display.id }) else { return }
                model.apply(row.mode, to: fresh, from: .panel)
            }
        }
    }
}

/// The rows of All Resolutions, worked out from a display's modes.
struct AllResolutionsLists {
    struct Row: Identifiable, Equatable {
        var size: String
        /// "Default", "Native", "Hidden" or "Hidden · 21:9".
        var tag: String?
        /// The tag with the pixel size and mode number: "Default · 3840 × 2160 px · mode 205".
        var detailedTag: String
        var aspectRatio: CGFloat
        var isCurrent: Bool
        var isHidden: Bool
        /// What choosing the row switches to: at the refresh rate in use when the size has it.
        var mode: DisplayMode

        var id: Int32 { mode.modeID }
    }

    /// Whether the display has HiDPI modes, so its modes come in two tabs.
    var hasTabs: Bool
    /// The tab's rows, or every listed size on a display without HiDPI modes.
    var listed: [Row]
    var hidden: [Row]
    var refreshRates: [PanelContent.Choice<Double>]

    init(display: Display, showsLowResolution: Bool, includeLowResolution: Bool, includeHidden: Bool) {
        let sections = ModeCatalog.sections(for: display, includeLowResolution: includeLowResolution, includeHidden: includeHidden)
        let current = ModeCatalog.currentKey(for: display)
        let panel = display.modes.first(where: \.isNative).map { AspectRatio(width: $0.width, height: $0.height) }
        func rows(_ kind: ResolutionSection.Kind) -> [Row] {
            (sections.first { $0.kind == kind }?.groups ?? []).map { group in
                let mode = ModeCatalog.preferredMode(in: group, current: display.currentMode)
                let ratio = AspectRatio(width: group.key.width, height: group.key.height)
                var tag = group.badge
                if group.isHidden {
                    tag = ratio == panel || panel == nil ? "Hidden" : "Hidden · \(Self.name(of: ratio))"
                }
                let details = "\(group.pixelSizeText) px · mode \(mode.modeID)"
                return Row(
                    size: group.sizeText,
                    tag: tag,
                    detailedTag: tag.map { "\($0) · \(details)" } ?? details,
                    aspectRatio: CGFloat(group.key.width) / CGFloat(max(1, group.key.height)),
                    isCurrent: group.key == current,
                    isHidden: group.isHidden,
                    mode: mode
                )
            }
        }
        hasTabs = sections.contains { $0.kind == .hiDPI } && sections.contains { $0.kind == .lowResolution }
        if hasTabs {
            listed = rows(showsLowResolution ? .lowResolution : .hiDPI)
        } else {
            listed = rows(.hiDPI) + rows(.standard)
        }
        hidden = rows(.hidden)
        refreshRates = ModeCatalog.refreshOptions(for: display, includeHidden: includeHidden).map { option in
            let title = RefreshRate.format(option.refreshRate)
            return PanelContent.Choice(title: title, accessibilityLabel: title, isSelected: option.isCurrent, value: option.refreshRate)
        }
    }

    /// A ratio as monitors are sold: 2560 × 1080 is 64:27 and 3440 × 1440 is 43:18, but
    /// both are sold, and the design names them, as 21:9.
    static func name(of ratio: AspectRatio) -> String {
        switch ratio.value {
        case 2.3...2.45: "21:9"
        case 3.5...3.6: "32:9"
        default: ratio.description
        }
    }
}
