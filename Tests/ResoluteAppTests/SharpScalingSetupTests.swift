import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// The setup sheet's choice (Figma 66:1271) and what Sharp Scaling says.
@MainActor
@Suite struct SharpScalingSetupTests {
    static let native = SharpSize(width: 2560, height: 1440)
    static let plan = SharpScalingPlan(native: native, limit: DrawingLimit(width: 6144))
    static let asus = SampleDisplays.asusPA278QV.display

    func choice(limit: DrawingLimit = DrawingLimit(width: 6144), current: DisplayMode? = asus.currentMode) -> SharpScalingSetupChoice {
        SharpScalingSetupChoice(plan: SharpScalingPlan(native: Self.native, limit: limit), current: current)
    }

    @Test func choosesEverySizeThisMacCanDrawAndSwitchesToTheSameSize() {
        let choice = choice()
        #expect(choice.sizes == SharpScalingGallery.designSizes)
        #expect(choice.confirmTitle == "Add 5 Sizes…")
        #expect(choice.canConfirm)
        #expect(choice.switchWhenReady)
        #expect(choice.switchTarget == Self.native)
        #expect(choice.switchTo == Self.native)
        #expect(choice.previewSelection == 5)
        #expect(choice.rows.map(\.note) == ["Text 60% larger", "Text 33% larger", "Text 25% larger", "Text 11% larger", "Same size as now"])
        #expect(choice.rows.map(\.drawn).first == "Drawn at 3200 × 1800")
        #expect(choice.rows.map(\.isNoteEmphasized) == [false, false, false, false, true])
        #expect(choice.preview.map(\.caption) == ["Larger Text", nil, nil, nil, "Same as now"])
    }

    @Test func namesTheButtonForTheSizesChosen() {
        var choice = choice()
        choice.set(Self.native, selected: false)
        #expect(choice.confirmTitle == "Add 4 Sizes…")
        // The size the display has is out, so the switch goes to the nearest one left.
        #expect(choice.switchTarget == SharpSize(width: 2304, height: 1296))
        choice.selectedRows = [0]
        #expect(choice.sizes == [SharpSize(width: 1600, height: 900)])
        #expect(choice.confirmTitle == "Add 1 Size…")
        choice.selectedRows = []
        #expect(choice.confirmTitle == "Add Sizes…")
        #expect(!choice.canConfirm)
        #expect(choice.switchTarget == nil)
    }

    @Test func savesNoSwitchWhenItIsOff() {
        var choice = choice()
        choice.switchWhenReady = false
        #expect(choice.switchTo == nil)
        #expect(choice.switchTarget == Self.native)
    }

    @Test func keepsOutSizesThisMacCantDraw() {
        var choice = choice(limit: DrawingLimit(width: 4800))
        #expect(choice.sizes.count == 4)
        #expect(choice.rows.last?.isAvailable == false)
        #expect(choice.rows.last?.note == "Too wide for this Mac")
        choice.set(Self.native, selected: true)
        choice.selectedRows = [0, 1, 2, 3, 4]
        #expect(!choice.isSelected(Self.native))
        #expect(choice.confirmTitle == "Add 4 Sizes…")
        #expect(SharpScalingText.limitNote(plan: choice.plan)
            == "This Mac can draw up to 4800 pixels wide on this display, so four of the five sizes fit. Sharp sizes stop at the panel’s own 2560 × 1440.")
    }

    @Test func saysWhatThisMacCanDraw() {
        #expect(SharpScalingText.limitNote(plan: Self.plan)
            == "This Mac can draw up to 6144 pixels wide on this display, so all five sizes fit. Sharp sizes stop at the panel’s own 2560 × 1440.")
        #expect(SharpScalingText.limitNote(plan: SharpScalingPlan(native: Self.native, limit: .unknown)).hasPrefix("This Mac doesn’t say"))
    }

    @Test func wordsTheSectionsForThePanel() {
        #expect(SharpScalingText.offMessage(plan: Self.plan)
            == "Give this display the sizes a 5K display has: five steps from Larger Text to More Space. Each is drawn at twice its size, then scaled to the panel, so text stays sharp at every step.")
        let fullHD = SharpScalingPlan(native: SharpSize(width: 1920, height: 1080), limit: .unknown)
        #expect(SharpScalingText.offer(native: fullHD.native).message.hasSuffix("like a 4K display."))
        let utc = TimeZone(identifier: "UTC") ?? .current
        let british = Locale(identifier: "en_GB")
        let saved = Date(timeIntervalSince1970: 1_793_094_120) // 27 Oct 2026, 09:42 UTC
        #expect(SharpScalingText.savedMessage(saved: saved, sizes: Array(SharpScalingGallery.designSizes.prefix(3)), timeZone: utc, locale: british)
            == "Saved at 9:42: 1600 × 900, 1920 × 1080 and 2048 × 1152. macOS reads the override file when the display connects.")
        #expect(SharpScalingText.rowHelp(sizes: 5, saved: saved, restoresFileFromBefore: true, now: saved, timeZone: utc, locale: british)
            == "5 sizes, added today at 9:42. Removing them puts back the file from before.")
        #expect(SharpScalingText.waitingBanner(display: "ASUS PA278QV", sizes: 5).message.hasPrefix("Five sharp sizes are saved."))
    }

    @Test func spreadsTheSizesOverTheFivePictures() {
        #expect((0..<5).map { SharpScalingText.stop(at: $0, of: 5) } == [1, 2, 3, 4, 5])
        #expect((0..<3).map { SharpScalingText.stop(at: $0, of: 3) } == [1, 3, 5])
        #expect(SharpScalingText.stop(at: 0, of: 1) == 5)
    }
}
