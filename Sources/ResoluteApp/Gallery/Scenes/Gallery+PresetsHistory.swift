import Foundation
import ResoluteDesign
import ResoluteKit
import SwiftUI

extension AppGallery {
    /// Scenes owned by the Presets and History pages owner.
    static var presetAndHistoryScenes: [GalleryScene] {
        [
            GalleryScene(id: "presets.page", title: "Presets", figmaNode: "37:2289", size: pageSize(height: 431)) {
                PresetsPage(model: presetsModel(PresetsSamples.figma))
            },
            GalleryScene(id: "presets.empty", title: "Presets, none yet", size: pageSize(height: 290)) {
                PresetsPage(model: presetsModel([]))
            },
            GalleryScene(id: "presets.recorder", title: "Shortcut recorder", figmaNode: "40:149", padding: 16) {
                ShortcutRecorderSamples()
            },
            GalleryScene(id: "history.page", title: "History", figmaNode: "37:1957", size: pageSize(height: 516)) {
                HistoryPage(model: historyModel(), now: { HistorySamples.now }, locale: HistorySamples.locale)
            },
            GalleryScene(id: "history.terminal", title: "History, Terminal & Agents", figmaNode: "37:1957", size: pageSize(height: 416)) {
                HistoryPage(
                    model: historyModel(), filter: .terminalAndAgents, now: { HistorySamples.now }, locale: HistorySamples.locale
                )
            },
            GalleryScene(id: "history.empty", title: "History, nothing yet", size: pageSize(height: 330)) {
                HistoryPage(model: AppModel(environment: .gallery()), now: { HistorySamples.now }, locale: HistorySamples.locale)
            },
        ]
    }

    /// The window's content area, 800 points wide as in Figma.
    private static func pageSize(height: CGFloat) -> CGSize {
        CGSize(width: 800, height: height)
    }

    /// The gallery's app with `presets` saved, its built-in display at 1496 × 967 so Coding
    /// is the active preset, as in Figma.
    @MainActor
    private static func presetsModel(_ presets: [Preset]) -> AppModel {
        var builtIn = FakeDisplayService.builtIn
        builtIn.currentModeID = builtIn.modes.first { $0.width == 1496 && $0.refreshRate == 120 }?.modeID ?? builtIn.currentModeID
        let environment = AppEnvironment.gallery(service: FakeDisplayService(displays: [builtIn, FakeDisplayService.dell]))
        do {
            try PresetStore(locations: environment.support).update { library in
                for preset in presets { try library.add(preset) }
            }
        } catch {
            FileHandle.standardError.write(Data("Could not write the sample presets: \(error.localizedDescription)\n".utf8))
        }
        return AppModel(environment: environment)
    }

    /// The gallery's app with Figma's five changes in History.
    @MainActor
    private static func historyModel() -> AppModel {
        let environment = AppEnvironment.gallery()
        let store = HistoryStore(locations: environment.support)
        do {
            for entry in HistorySamples.entries { try store.append(entry) }
        } catch {
            FileHandle.standardError.write(Data("Could not write the sample history: \(error.localizedDescription)\n".utf8))
        }
        return AppModel(environment: environment)
    }
}

/// Figma's three presets (37:2289): Coding (active, ⌃⌥1), Presenting (⌃⌥2), Gaming (⌃⌥3).
enum PresetsSamples {
    static var figma: [Preset] {
        let builtIn = DisplayReference(FakeDisplayService.builtIn)
        let dell = DisplayReference(FakeDisplayService.dell)
        func size(_ width: Int, _ height: Int) -> DisplaySetting.Size { .init(width: width, height: height) }
        return [
            Preset(
                name: "Coding",
                displays: [
                    DisplaySetting(display: builtIn, size: size(1496, 967), pixelSize: size(2992, 1934)),
                    DisplaySetting(display: dell, size: size(2560, 1440), pixelSize: size(5120, 2880), refreshRate: 60),
                ],
                shortcut: KeyShortcut(key: "1", modifiers: [.control, .option])
            ),
            Preset(
                name: "Presenting",
                displays: [
                    DisplaySetting(display: builtIn, size: size(1920, 1080), refreshRate: 60),
                    DisplaySetting(display: dell, size: size(1920, 1080), refreshRate: 60),
                ],
                mirroring: true,
                shortcut: KeyShortcut(key: "2", modifiers: [.control, .option])
            ),
            Preset(
                name: "Gaming",
                displays: [
                    DisplaySetting(display: dell, size: size(1920, 1080), refreshRate: 60),
                    DisplaySetting(display: builtIn, refreshRate: 120),
                ],
                shortcut: KeyShortcut(key: "3", modifiers: [.control, .option])
            ),
        ]
    }
}

/// Figma's five changes (37:1957), told from 9:45 today.
enum HistorySamples {
    static let locale = Locale(identifier: "en_GB")

    static var now: Date {
        Calendar.current.date(bySettingHour: 9, minute: 45, second: 0, of: Date()) ?? Date()
    }

    static var entries: [HistoryEntry] {
        let calendar = Calendar.current
        let today = now
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        func at(_ hour: Int, _ minute: Int, on day: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        let builtIn = HistoryEntry.DisplayRecord(FakeDisplayService.builtIn)
        let dell = HistoryEntry.DisplayRecord(FakeDisplayService.dell)
        func mode(_ width: Int, _ height: Int, _ rate: Double, hidden: Bool = false) -> HistoryEntry.ModeRecord {
            HistoryEntry.ModeRecord(
                modeID: 0, width: width, height: height, pixelWidth: width * 2, pixelHeight: height * 2,
                refreshRate: rate, isHidden: hidden
            )
        }
        let undone = HistoryEntry(
            date: at(8, 30, on: yesterday), source: .panel,
            change: .mode(.init(display: builtIn, from: mode(1728, 1117, 120), to: mode(1496, 967, 120))),
            outcome: .applied
        )
        return [
            undone,
            HistoryEntry(
                date: at(8, 40, on: yesterday), source: .panel,
                change: .mode(.init(display: builtIn, from: mode(1496, 967, 120), to: mode(1728, 1117, 120))),
                outcome: .undone(of: undone.id)
            ),
            HistoryEntry(
                date: at(18, 5, on: yesterday), source: .preset(name: "Presenting", via: .shortcuts),
                change: .mirroring(.init(isOn: true, displays: [builtIn, dell])),
                outcome: .applied
            ),
            HistoryEntry(
                date: at(9, 20, on: today), source: .panel,
                change: .mode(.init(display: builtIn, from: mode(1728, 1117, 120), to: mode(1728, 1117, 60))),
                outcome: .applied
            ),
            HistoryEntry(
                date: at(9, 38, on: today), source: .terminal(app: "Terminal"),
                change: .mode(.init(display: dell, from: mode(1920, 1080, 60), to: mode(2560, 1440, 60))),
                outcome: .applied
            ),
            HistoryEntry(
                date: at(9, 41, on: today), source: .agent(name: "Claude Code", app: "Terminal"),
                change: .mode(.init(display: dell, from: mode(2560, 1440, 60), to: mode(2880, 1620, 60, hidden: true))),
                outcome: .reverted(.noAnswer)
            ),
        ]
    }
}

/// The recorder's states: a shortcut as Settings shows it, none, recording, and a shortcut
/// refused because the panel has it.
private struct ShortcutRecorderSamples: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: Metrics.Spacing.large) {
            ShortcutRecorder(shortcut: .constant(.openPanel))
            ShortcutRecorder(shortcut: .constant(KeyShortcut(key: "1", modifiers: [.control, .option])), style: .chip)
            ShortcutRecorder(shortcut: .constant(nil))
            ShortcutRecorder(shortcut: .constant(.openPanel), style: .chip, startsRecording: true, message: nil)
            ShortcutRecorder(
                shortcut: .constant(nil), style: .chip, startsRecording: true,
                message: "⌃⌥R already opens the panel."
            )
        }
        .frame(width: 240, alignment: .trailing)
    }
}
