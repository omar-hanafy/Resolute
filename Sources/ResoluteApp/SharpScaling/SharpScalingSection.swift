import ResoluteDesign
import ResoluteKit
import SwiftUI

/// What a display's page says about Sharp Scaling, in whatever state it is on that display
/// (Figma: Sharp Scaling › page off 62:1020, saved 67:1585, ready 67:2175, partial 68:2089).
/// The Resolution tab shows it for displays that can have Sharp Scaling or have it.
///
/// Before the sizes are in use it is a section of its own, with Set Up Sharp Scaling… or
/// Undo Setup…; once they are, the Sharp Scaling row with Remove… (which the page can also
/// put in its own group with `SharpScalingRow`). It presents the setup sheet when Set Up
/// Sharp Scaling… asks for it on this display, from here or from the panel.
struct SharpScalingSection: View {
    let model: AppModel
    let display: Display

    private var sharp: SharpScalingModel { model.sharpScaling }

    var body: some View {
        content
            .sheet(isPresented: isSettingUp) {
                if let plan = sharp.plan(for: display) {
                    SharpScalingSetupSheet(model: model, display: display, plan: plan)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch sharp.stage(for: display) {
        case .off(let plan)?:
            SharpScalingSummary(
                symbol: .sparkles,
                symbolColor: Palette.accent,
                badge: "Off",
                message: SharpScalingText.offMessage(plan: plan),
                sizes: SharpScalingText.options(for: plan.sizes, current: currentSize),
                isPreview: true,
                action: .init("Set Up Sharp Scaling…", isProminent: true) {
                    sharp.setupRequest = display.id
                },
                footnote: SharpScalingText.offFootnote,
                isWorking: sharp.isWorking(on: display)
            )
        case .waiting(let status)?:
            SharpScalingSummary(
                symbol: .hourglass,
                symbolColor: Palette.orange,
                badge: "Waiting for reconnect",
                message: status.record.map { SharpScalingText.savedMessage(saved: $0.saved, sizes: status.saved) } ?? "",
                sizes: SharpScalingText.options(for: status.saved, current: currentSize),
                isPreview: false,
                action: .init("Undo Setup…", isProminent: false) {
                    Task { await sharp.turnOff(for: display) }
                },
                footnote: SharpScalingText.undoFootnote(restoresFileFromBefore: restoresFileFromBefore),
                isWorking: sharp.isWorking(on: display)
            )
        case .ready?, .partial?:
            FormGroup {
                SharpScalingRow(model: model, display: display)
            }
        case nil:
            EmptyView()
        }
    }

    private var currentSize: SharpSize? {
        display.currentMode.map { SharpSize($0) }
    }

    private var restoresFileFromBefore: Bool {
        sharp.states[display.id]?.restoresFileFromBefore ?? true
    }

    /// Up while Set Up Sharp Scaling… asked for this display's sheet.
    private var isSettingUp: Binding<Bool> {
        Binding(
            get: { sharp.setupRequest == display.id && sharp.plan(for: display) != nil },
            set: { isUp in
                if !isUp, sharp.setupRequest == display.id { sharp.setupRequest = nil }
            }
        )
    }
}

/// The Sharp Scaling row once its sizes are in use (Figma 67:2175): how many sizes and when
/// they were added, and Remove…. A row of a `FormGroup`; the page puts it above Refresh Rate.
struct SharpScalingRow: View {
    let model: AppModel
    let display: Display

    var body: some View {
        let sharp = model.sharpScaling
        if let state = sharp.states[display.id], let status = state.status, let record = status.record, status.state != .off {
            FormRow(
                "Sharp Scaling",
                help: SharpScalingText.rowHelp(
                    sizes: status.saved.count, saved: record.saved, restoresFileFromBefore: state.restoresFileFromBefore
                ),
                buttonTitle: "Remove…"
            ) {
                Task { await sharp.turnOff(for: display) }
            }
            .disabled(sharp.isWorking(on: display))
        }
    }
}

/// The banner Sharp Scaling puts above a display page's tabs: reconnect to finish (67:1585),
/// ready (67:2175), macOS skipped a size (68:2089), or removed until the reconnect.
struct SharpScalingBanner: View {
    let model: AppModel
    let display: Display

    var body: some View {
        let sharp = model.sharpScaling
        if let banner = sharp.banner(for: display) {
            Banner(
                banner.text.title,
                message: banner.text.message,
                tone: banner.tone,
                action: action(banner)
            )
            .disabled(sharp.isWorking(on: display))
        }
    }

    private func action(_ banner: SharpScalingModel.PageBanner) -> Banner.Action? {
        guard let kind = banner.action, let title = banner.text.actionTitle else { return nil }
        let sharp = model.sharpScaling
        let display = display
        return Banner.Action(title) {
            switch kind {
            case .useSharpVersion:
                sharp.useSharpVersion(on: display)
            case .removeSkippedSizes:
                Task { await sharp.removeSkippedSizes(on: display) }
            case .remove:
                Task { await sharp.turnOff(for: display) }
            }
        }
    }
}
