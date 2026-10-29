import ResoluteDesign
import ResoluteKit
import SwiftUI

/// Set Up Sharp Scaling for a display (Figma 66:1271): the plan's sizes, all that this Mac
/// can draw chosen at first, the switch once they are ready, and Add N Sizes…, which writes
/// them after the administrator password. The sheet stays up when the prompt is cancelled
/// or the write fails, and closes once the sizes are saved.
struct SharpScalingSetupSheet: View {
    let model: AppModel
    let display: Display
    @State private var choice: SharpScalingSetupChoice
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, display: Display, plan: SharpScalingPlan) {
        self.model = model
        self.display = display
        _choice = State(initialValue: SharpScalingSetupChoice(plan: plan, current: display.currentMode))
    }

    var body: some View {
        SharpScalingSetupForm(
            title: SharpScalingText.sheetTitle(display: display.name),
            message: SharpScalingText.sheetMessage(native: choice.plan.native),
            preview: choice.preview,
            previewSelection: choice.previewSelection,
            rows: choice.rows,
            selection: $choice.selectedRows,
            switchTitle: choice.switchTarget.map(SharpScalingText.switchTitle),
            switchWhenReady: $choice.switchWhenReady,
            limitNote: SharpScalingText.limitNote(plan: choice.plan),
            footnote: SharpScalingText.sheetFootnote,
            confirmTitle: choice.confirmTitle,
            canConfirm: choice.canConfirm,
            isWorking: model.sharpScaling.isWorking(on: display),
            cancel: { dismiss() },
            confirm: add
        )
        // Esc would leave the password prompt with nothing to report to.
        .interactiveDismissDisabled(model.sharpScaling.isWorking(on: display))
    }

    private func add() {
        let choice = choice
        Task {
            if await model.sharpScaling.turnOn(for: display, sizes: choice.sizes, switchTo: choice.switchTo) {
                dismiss()
            }
        }
    }
}
