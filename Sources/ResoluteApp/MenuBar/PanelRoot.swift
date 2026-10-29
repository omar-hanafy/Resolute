import ResoluteDesign
import ResoluteKit
import SwiftUI

/// The menu bar panel (Figma: Menu bar panel › two displays 23:557): a card for each display,
/// the presets, the last change from outside Resolute, and the app's actions. All
/// Resolutions takes the place of the cards for one display until Back.
struct PanelRoot: View {
    let model: AppModel

    var body: some View {
        PanelSurface {
            if let id = model.panelAllResolutions, let display = model.displays.first(where: { $0.id == id }) {
                AllResolutionsPage(model: model, display: display)
            } else {
                PanelCardsPage(model: model)
            }
        }
    }
}

/// The panel's first page.
private struct PanelCardsPage: View {
    let model: AppModel

    var body: some View {
        PanelHeader(openWindow: { model.openWindow(model.defaultRoute) })
        ForEach(PanelContent.waiting(for: model)) { waiting in
            WaitingBanner(title: waiting.title, message: waiting.message) {
                model.stopWaiting(for: waiting.displayID)
            }
        }
        ForEach(PanelContent.cards(for: model)) { card in
            PanelCard(model: model, card: card)
        }
        PresetsRow(
            model.presets.map { preset in
                PanelChoice(preset.name, isSelected: model.isActive(preset), accessibilityLabel: preset.name) {
                    // The panel finishes its click before the displays reconfigure.
                    MainRunLoop.perform { model.applyPreset(preset, from: .panel) }
                }
            },
            saveCurrentSetup: {
                do {
                    try model.saveCurrentSetupAsPreset()
                } catch {
                    model.showError(error, "The preset could not be saved")
                }
            }
        )
        if let activity = model.sharpScaling.activity {
            // A sharp size Resolute switched to once the display reconnected (Figma 60:873).
            ActivityRow(symbol: activity.symbol, title: activity.title, detail: activity.detail()) {
                MainRunLoop.perform { model.sharpScaling.undoActivity() }
            }
        } else if model.preferences.showsCommandLineChangesInPanel, let activity = model.lastOutsideActivity() {
            ActivityRow(symbol: Symbol(rawValue: activity.symbolName) ?? .terminal, title: activity.title, detail: activity.detail) {
                MainRunLoop.perform { model.undo(activity.entry, from: .panel) }
            }
        }
        PanelActions(model: model)
    }
}

/// One display's card, or a mirror set's.
private struct PanelCard: View {
    let model: AppModel
    let card: PanelContent.Card

    private var display: Display? {
        model.displays.first { $0.id == card.displayID }
    }

    var body: some View {
        DisplayCard(
            name: card.name,
            summary: card.summary,
            picture: DisplayPictureModel(rawValue: card.skin.rawValue) ?? .display,
            badge: card.badge.map { Badge($0.text, tone: $0.isAccent ? .accent : .neutral) },
            sizes: sizes(),
            refreshRates: card.refreshRates.map { rate in
                PanelChoice(rate.title, isSelected: rate.isSelected, accessibilityLabel: rate.accessibilityLabel) {
                    MainRunLoop.perform { model.setRefreshRate(rate.value, on: card.displayID, from: .panel) }
                }
            },
            resolutionCount: card.resolutionCount,
            openDisplay: { model.openWindow(.display(.id(card.displayID))) },
            showAllResolutions: { model.panelAllResolutions = card.displayID }
        ) {
            if let display, let offer = model.sharpScaling.offer(for: display) {
                PanelOffer(
                    title: offer.title, message: offer.message, actionTitle: offer.actionTitle,
                    action: { model.sharpScaling.startSetup(for: display) },
                    dismiss: { model.sharpScaling.dismissOffer(for: display) }
                )
            }
        }
        // A display that went dark during its trial can't take another mode until it is back.
        .disabled(!card.isResponding)
    }

    /// The card's sizes, for whichever card type the offer makes it.
    private func sizes<Offer: View>() -> DisplayCard<Offer>.Sizes {
        switch card.sizes {
        case .stops(let stops, let caption, let isBuiltIn):
            .stops(StopStrip(stops.map(choice), caption: caption, tone: isBuiltIn ? .violet : .teal))
        case .resolutions(let resolutions):
            .resolutions(resolutions.map(choice))
        }
    }

    private func choice(_ size: PanelContent.Choice<DisplayMode>) -> PanelChoice {
        PanelChoice(size.title, isSelected: size.isSelected, accessibilityLabel: size.accessibilityLabel) {
            MainRunLoop.perform {
                guard let display = model.displays.first(where: { $0.id == card.displayID }) else { return }
                model.apply(size.value, to: display, from: .panel)
            }
        }
    }
}

/// The rows at the bottom of the panel.
private struct PanelActions: View {
    let model: AppModel

    var body: some View {
        PanelSeparator()
        VStack(spacing: 0) {
            if model.canMirror || model.isMirroring {
                PanelRow("Mirror Displays", symbol: .rectangleOnRectangle, isOn: Binding(
                    get: { model.isMirroring },
                    set: { isOn in MainRunLoop.perform { model.setMirroring(isOn, from: .panel) } }
                ))
            }
            PanelRow("Custom Resolutions…", symbol: .plusRectangleOnRectangle) {
                model.openCustomResolutions(for: nil)
            }
            PanelRow("Settings…", symbol: .gearshape, trailing: .shortcut("⌘,")) {
                model.openSettings()
            }
            PanelRow("Quit Resolute", symbol: .power, trailing: .shortcut("⌘Q")) {
                model.quit()
            }
        }
    }
}
