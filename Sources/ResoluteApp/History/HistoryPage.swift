import AppKit
import ResoluteDesign
import ResoluteKit
import SwiftUI

/// The window's History page (Figma: Window › History, 37:1957): the filters, a row for each
/// change of the last 7 days, newest first, with how it ended and Undo while it is in
/// place, and the note on how long History keeps them.
///
/// History grows while the page is open: the app's own switches reload it, and the page
/// watches History's file for the changes `resolute` and agents make, and reads it again
/// when Resolute becomes active.
struct HistoryPage: View {
    let model: AppModel
    /// The time the rows' times are told from; the gallery fixes it.
    var now: () -> Date
    var locale: Locale

    @State private var filter: HistoryFilter
    @State private var watcher: HistoryFileWatcher?

    init(model: AppModel, filter: HistoryFilter = .all, now: @escaping () -> Date = Date.init, locale: Locale = .current) {
        self.model = model
        self.now = now
        self.locale = locale
        _filter = State(initialValue: filter)
    }

    var body: some View {
        TitledPage("History", description: HistoryText.pageDescription) {
            let filters = HistoryFilter.offered(for: model.historyEntries)
            let shown = filters.contains(filter) ? filter : .all
            SegmentedTabs(filters.map { SegmentedTabs.Item($0, $0.title) }, selection: Binding(get: { shown }, set: { filter = $0 }))
                .accessibilityLabel("Show changes from")
            // Times such as "9:41" and "Yesterday" move on as the day does.
            TimelineView(.everyMinute) { _ in
                HistoryList(model: model, filter: shown, now: now(), locale: locale)
            }
            Text(HistoryText.footnote)
                .textStyle(.footnote)
                .foregroundStyle(Palette.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            model.refresh()
            startWatching()
        }
        .onDisappear {
            watcher?.stop()
            watcher = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
            // The support folder may not have existed when the page appeared.
            startWatching()
        }
    }

    private func startWatching() {
        let watcher = watcher ?? HistoryFileWatcher(file: model.support.historyFile) { [model] in
            model.reloadHistory()
        }
        watcher.start()
        self.watcher = watcher
    }
}

/// The list of changes in `filter`, or what an empty list says.
struct HistoryList: View {
    let model: AppModel
    let filter: HistoryFilter
    let now: Date
    let locale: Locale

    var body: some View {
        let items = Self.items(in: model.historyTimeline, filter: filter, now: now, locale: locale)
        GroupedSection(insets: items.isEmpty ? nil : EdgeInsets(), spacing: 0) {
            if items.isEmpty {
                Text(filter.emptyText)
                    .textStyle(.callout)
                    .foregroundStyle(Palette.labelSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(items) { item in
                    row(for: item)
                }
            }
        }
    }

    private func row(for item: HistoryItem) -> some View {
        HistoryRow(
            time: item.time,
            source: Symbol(rawValue: item.symbolName) ?? .clock,
            title: item.title,
            detail: item.detail,
            status: Self.rowStatus(item.status),
            onUndo: item.canUndo ? { model.undo(item.entry, from: .window) } : nil
        )
        // History's own words, which name a failed change as Failed.
        .accessibilityLabel(item.accessibilityLabel)
    }

    /// The rows of `filter`, newest first.
    static func items(in timeline: HistoryTimeline, filter: HistoryFilter, now: Date, locale: Locale) -> [HistoryItem] {
        timeline.items(in: filter, now: now, locale: locale)
    }

    /// The row's badge.
    static func rowStatus(_ status: HistoryStatus) -> HistoryRow.Status {
        switch status {
        case .kept: .kept
        case .reverted: .reverted
        case .undone: .undone
        case .failed: .failed
        }
    }
}
