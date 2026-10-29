import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// A connected display's Resolution tab: Larger Text ↔ More Space, the refresh rate and All
/// Modes for a Retina display (Figma 31:5); Sharp Scaling, the resolution and the refresh
/// rate for a standard one (Figma 62:1020), and once its sharp sizes are in, the stops with
/// a Sharp Scaling row (67:2175). Every choice switches at once, through the app model, as
/// asked from the window.
struct ResolutionTab: View {
    let model: AppModel
    let display: Display

    var body: some View {
        let facts = model.facts(for: display)
        let sharpScaling = model.sharpScaling.placement(for: display)
        // On screen whenever Sharp Scaling is off or saved, so its setup sheet can open.
        if sharpScaling == .section {
            SharpScalingSection(model: model, display: display)
        }
        if let stops = model.stops(for: display) {
            StopsSection(model: model, display: display, stops: stops)
            if sharpScaling == .row {
                FormGroup {
                    SharpScalingRow(model: model, display: display)
                    RefreshRateRow(model: model, display: display, facts: facts)
                }
            } else {
                RefreshRateGroup(model: model, display: display, facts: facts)
            }
            AllModesSection(model: model, display: display)
        } else {
            FormGroup {
                StandardResolutionRow(model: model, display: display, facts: facts)
                RefreshRateRow(model: model, display: display, facts: facts)
            }
        }
    }
}

/// Larger Text ↔ More Space, with each size's pixels while ⌥ is held.
private struct StopsSection: View {
    let model: AppModel
    let display: Display
    let stops: SpaceStops
    @State private var optionKey = OptionKeyMonitor()

    var body: some View {
        StopPicker(
            "Resolution",
            options: ResolutionChoices.stopOptions(stops, showsPixels: optionKey.isDown),
            tone: DisplayPagePresentation.tone(for: display),
            selection: Binding(
                get: { stops.current?.thumbnail },
                set: { thumbnail in
                    guard let thumbnail, let mode = ResolutionChoices.mode(forStop: thumbnail, in: stops) else { return }
                    model.apply(mode, to: display, from: .window)
                }
            ),
            footnote: ResolutionChoices.stopFootnote
        )
        .onAppear { optionKey.start() }
        .onDisappear { optionKey.stop() }
    }
}

/// Refresh Rate in a group of its own.
private struct RefreshRateGroup: View {
    let model: AppModel
    let display: Display
    let facts: DisplayFacts

    var body: some View {
        FormGroup {
            RefreshRateRow(model: model, display: display, facts: facts)
        }
    }
}

/// The refresh rate at the current resolution, as a pop-up; a single rate is only shown.
private struct RefreshRateRow: View {
    let model: AppModel
    let display: Display
    let facts: DisplayFacts

    var body: some View {
        let rates = ResolutionChoices.rates(for: display, facts: facts)
        let help = ResolutionChoices.refreshHelp(facts: facts)
        if rates.count > 1 {
            FormRow(
                "Refresh Rate",
                help: help,
                selection: Binding(
                    get: { ResolutionChoices.currentRateKey(of: display) ?? rates[0].key },
                    set: { key in
                        guard let rate = rates.first(where: { $0.key == key }) else { return }
                        model.setRefreshRate(rate.hertz, on: display.id, from: .window)
                    }
                ),
                options: rates.map { FormRowPopUp<Int>.Option($0.key, $0.title) }
            )
        } else {
            FormRow("Refresh Rate", help: help, value: rates.first?.title ?? "—")
        }
    }
}

/// A standard display's resolution, as a pop-up.
private struct StandardResolutionRow: View {
    let model: AppModel
    let display: Display
    let facts: DisplayFacts

    var body: some View {
        let resolutions = ResolutionChoices.resolutions(for: display)
        let current = ModeCatalog.currentKey(for: display)
        FormRow(
            "Resolution",
            help: ResolutionChoices.standardResolutionHelp(facts: facts),
            selection: Binding(
                get: { current ?? resolutions.first?.key },
                set: { key in
                    guard let resolution = resolutions.first(where: { $0.key == key }) else { return }
                    model.apply(resolution.mode, to: display, from: .window)
                }
            ),
            options: resolutions.map { FormRowPopUp<ResolutionGroup.Key?>.Option($0.key, $0.title) }
        )
    }
}

/// Every mode, under HiDPI, Low Resolution (1×) and Hidden; clicking one switches to it,
/// and a hidden one is tried first.
private struct AllModesSection: View {
    let model: AppModel
    let display: Display
    @State private var filter = ResolutionChoices.ModeFilter.hiDPI

    private var filters: [ResolutionChoices.ModeFilter] {
        ResolutionChoices.filters(for: display)
    }

    private var shown: ResolutionChoices.ModeFilter {
        filters.contains(filter) ? filter : (filters.first ?? .hiDPI)
    }

    private var rows: [DataTable<ResolutionGroup.Key, FilterTabs>.Row] {
        ResolutionChoices.modeRows(for: display, matching: shown).map { row in
            DataTable<ResolutionGroup.Key, FilterTabs>.Row(id: row.id, values: row.values, accessibilityLabel: row.accessibilityLabel)
        }
    }

    private var selection: Binding<ResolutionGroup.Key?> {
        let shown = shown
        return Binding(
            get: { ModeCatalog.currentKey(for: display) },
            set: { key in
                guard let key, key != ModeCatalog.currentKey(for: display),
                      let group = ResolutionChoices.groups(of: display, matching: shown).first(where: { $0.key == key })
                else { return }
                model.apply(ModeCatalog.preferredMode(in: group, current: display.currentMode), to: display, from: .window)
            }
        )
    }

    var body: some View {
        let footnote: String? = shown == .hidden ? ResolutionChoices.hiddenFootnote(trialLength: model.preferences.trialLength) : nil
        // Each choice switches the display, so the arrow keys only browse; Return chooses.
        DataTable(
            "All Modes",
            columns: DataTableColumn.modes,
            rows: rows,
            selection: selection,
            choosesWithReturn: true,
            footnote: footnote
        ) {
            FilterTabs(filters: filters, selection: Binding(get: { shown }, set: { filter = $0 }))
        }
    }
}

/// All Modes' HiDPI | Low Resolution (1×) | Hidden, when the display has more than one kind.
private struct FilterTabs: View {
    let filters: [ResolutionChoices.ModeFilter]
    @Binding var selection: ResolutionChoices.ModeFilter

    var body: some View {
        if filters.count > 1 {
            let items: [SegmentedTabs<ResolutionChoices.ModeFilter>.Item] = filters.map { .init($0, $0.title) }
            SegmentedTabs(items, selection: $selection)
                .fixedSize()
                .accessibilityLabel("Modes to show")
        }
    }
}

/// Whether ⌥ is held while the window is in front, for "Hold ⌥ to see the pixel size of each".
@MainActor
@Observable
final class OptionKeyMonitor {
    private(set) var isDown = false
    @ObservationIgnored private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        isDown = NSEvent.modifierFlags.contains(.option)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.update(event.modifierFlags)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isDown = false
    }

    func update(_ flags: NSEvent.ModifierFlags) {
        let down = flags.contains(.option)
        if down != isDown { isDown = down }
    }
}
