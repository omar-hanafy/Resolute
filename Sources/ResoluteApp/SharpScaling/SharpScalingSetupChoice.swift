import ResoluteDesign
import ResoluteKit

/// What the setup sheet (Figma 66:1271) has chosen: the sizes, all that this Mac can draw at
/// first, and whether to switch to a sharp size once macOS offers them. Kept apart from the
/// view so the rules can be checked without one.
struct SharpScalingSetupChoice: Equatable {
    let plan: SharpScalingPlan
    /// The size the display has now, which the switch keeps when it can.
    let current: DisplayMode?
    /// The chosen sizes. Only sizes this Mac can draw get in.
    private(set) var selected: Set<SharpSize>
    var switchWhenReady = true

    init(plan: SharpScalingPlan, current: DisplayMode?) {
        self.plan = plan
        self.current = current
        selected = Set(plan.sizes)
    }

    /// The chosen sizes, Larger Text first.
    var sizes: [SharpSize] {
        plan.sizes.filter(selected.contains)
    }

    func isSelected(_ size: SharpSize) -> Bool {
        selected.contains(size)
    }

    /// Chooses `size`, or leaves it out. A size this Mac can't draw stays out.
    mutating func set(_ size: SharpSize, selected isSelected: Bool) {
        guard plan.step(for: size)?.fits == true else { return }
        if isSelected { selected.insert(size) } else { selected.remove(size) }
    }

    /// The sharp size the display moves to once macOS offers it: the size it has now, else
    /// the nearest chosen one.
    var switchTarget: SharpSize? {
        SharpScalingPlan.switchTarget(from: current, among: sizes, native: plan.native)
    }

    /// What setup saves as the size to switch to: nil when the switch is off.
    var switchTo: SharpSize? {
        switchWhenReady ? switchTarget : nil
    }

    var canConfirm: Bool { !sizes.isEmpty }

    /// "Add 5 Sizes…".
    var confirmTitle: String { SharpScalingText.confirmTitle(count: sizes.count) }

    private var currentSize: SharpSize? { current.map { SharpSize($0) } }

    // MARK: - For the form

    /// One row per step of the plan; `id` is the step's place in it.
    var rows: [SharpScalingSetupForm.Row] {
        plan.steps.enumerated().map { index, step in
            SharpScalingSetupForm.Row(
                id: index,
                size: step.size.sizeText,
                drawn: SharpScalingText.drawn(step.size),
                note: SharpScalingText.note(for: step, in: plan, current: currentSize),
                isNoteEmphasized: step.fits && step.size == currentSize,
                isAvailable: step.fits
            )
        }
    }

    /// The chosen rows' ids.
    var selectedRows: Set<Int> {
        get { Set(plan.steps.indices.filter { selected.contains(plan.steps[$0].size) }) }
        set {
            for (index, step) in plan.steps.enumerated() {
                set(step.size, selected: newValue.contains(index))
            }
        }
    }

    /// The chosen sizes as pictures.
    var preview: [StopPicker.Option] {
        SharpScalingText.options(for: sizes, current: currentSize)
    }

    /// The preview's highlighted picture: the size the display moves to.
    var previewSelection: Int? {
        guard let target = switchTarget, let index = sizes.firstIndex(of: target) else { return nil }
        return preview[index].stop
    }
}
