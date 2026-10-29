import Foundation
import ResoluteDesign
import ResoluteKit

/// What Sharp Scaling says in the app, in the design's words (Figma: Sharp Scaling, page
/// 60:543), worked out from the plan and the status so each display gets its own numbers.
enum SharpScalingText {
    // MARK: - Panel

    /// The panel card's offer (60:547).
    static func offer(native: SharpSize) -> SharpScalingModel.Offer {
        let like = retinaClass(of: native).map { "like a \($0) display" } ?? "like a Retina display"
        return SharpScalingModel.Offer(
            title: "Sharper text on this display",
            message: "Add Retina-style sizes, from Larger Text to More Space, \(like).",
            actionTitle: "Set Up Sharp Scaling…"
        )
    }

    /// "ASUS PA278QV → 2560 × 1440 sharp" (60:873).
    static func activityTitle(display: String, size: SharpSize) -> String {
        "\(display) → \(size.sizeText) sharp"
    }

    /// "Sharp Scaling is ready · just now".
    static func activityDetail(since date: Date, now: Date) -> String {
        "Sharp Scaling is ready · " + HistoryText.relativeTime(of: date, now: now)
    }

    // MARK: - Page sections

    /// Before setup (62:1020): "Give this display the sizes a 5K display has: five steps …"
    static func offMessage(plan: SharpScalingPlan) -> String {
        let steps = plan.sizes.count == 1 ? "one step" : "\(word(plan.sizes.count)) steps"
        let sizes = retinaClass(of: plan.native).map { "the sizes a \($0) display has" } ?? "Retina-style sizes"
        return "Give this display \(sizes): \(steps) from Larger Text to More Space. "
            + "Each is drawn at twice its size, then scaled to the panel, so text stays sharp at every step."
    }

    static let offFootnote = "Asks for an administrator password. The sizes appear after the display reconnects."

    /// Saved, waiting for a reconnect (67:1585): "Saved at 9:42: 1600 × 900, … and 2560 × 1440. …"
    static func savedMessage(saved: Date, sizes: [SharpSize], timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        "Saved at \(time(of: saved, timeZone: timeZone, locale: locale)): \(list(sizes.map(\.sizeText))). "
            + "macOS reads the override file when the display connects."
    }

    /// Under Undo Setup… and beside Remove…: what turning Sharp Scaling off does to the file.
    static func undoFootnote(restoresFileFromBefore: Bool) -> String {
        restoresFileFromBefore
            ? "Puts back the file from before. A backup is kept either way."
            : "Takes out the sharp sizes and keeps the rest of the file, which changed since. A backup is kept either way."
    }

    /// The Sharp Scaling row once the sizes are in use (67:2175): "5 sizes, added today at
    /// 9:42. Removing them puts back the file from before."
    static func rowHelp(
        sizes: Int, saved: Date, restoresFileFromBefore: Bool, now: Date = Date(), timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let count = sizes == 1 ? "1 size" : "\(sizes) sizes"
        let removing = restoresFileFromBefore
            ? "Removing them puts back the file from before."
            : "Removing them keeps the rest of the file, which changed since."
        return "\(count), added \(day(of: saved, now: now, timeZone: timeZone, locale: locale)) at "
            + "\(time(of: saved, timeZone: timeZone, locale: locale)). \(removing)"
    }

    // MARK: - Banners

    /// What a banner says, and its link.
    struct BannerText: Equatable {
        var title: String
        var message: String
        var actionTitle: String?
    }

    /// Saved, waiting for a reconnect (67:1585).
    static func waitingBanner(display: String, sizes: Int) -> BannerText {
        let saved = sizes == 1 ? "One sharp size is saved." : "\(word(sizes).capitalized) sharp sizes are saved."
        return BannerText(
            title: "Reconnect \(display) to finish",
            message: "\(saved) Unplug the display and plug it back in, or restart your Mac. "
                + "Resolute checks them as soon as the display is back."
        )
    }

    /// Ready (67:2175). Offers the sharp version of the size the display has when it is
    /// still at 1×.
    static func readyBanner(display: String, status: SharpScalingStatus) -> BannerText {
        let count = status.available.count
        let accepted = count == 1 ? "macOS accepted the size" : count == 2 ? "macOS accepted both sizes" : "macOS accepted all \(count) sizes"
        let sameSizes = "System Settings › Displays lists the same sizes."
        if let current = status.current, current.isHiDPI, status.saved.contains(SharpSize(current)) {
            return BannerText(
                title: "Sharp Scaling is ready",
                message: "\(accepted), and \(display) now uses the sharp \(SharpSize(current).sizeText). \(sameSizes)"
            )
        }
        if let current = status.current, !current.isHiDPI, let sharp = status.sharpVersionOfCurrent {
            return BannerText(
                title: "Sharp Scaling is ready",
                message: "\(accepted). \(display) still uses \(SharpSize(current).sizeText) at 1×.",
                actionTitle: "Use the Sharp \(SharpSize(sharp).sizeText)"
            )
        }
        return BannerText(title: "Sharp Scaling is ready", message: "\(accepted). \(sameSizes)")
    }

    /// macOS skipped a size after the reconnect (68:2089).
    static func partialBanner(status: SharpScalingStatus) -> BannerText {
        let saved = status.saved.count, available = status.available.count, skipped = status.skipped.count
        guard available > 0 else {
            return BannerText(
                title: "macOS added none of the \(saved) sizes",
                message: "It skipped all of them on this Mac. Remove Sharp Scaling to take them out of the override file.",
                actionTitle: "Remove Sharp Scaling…"
            )
        }
        let which = skipped == 1 ? "the skipped size" : "the skipped sizes"
        return BannerText(
            title: "macOS added \(available) of \(saved) sizes",
            message: "It skipped \(list(status.skipped.map(\.sizeText))) on this Mac. "
                + "Keep the other \(word(available)), or remove \(which) so the list matches what you can use.",
            actionTitle: skipped == 1 ? "Remove Skipped Size" : "Remove Skipped Sizes"
        )
    }

    /// After Remove… while the sizes were in use: they stay until macOS reads the file again.
    static func removedBanner(display: String) -> BannerText {
        BannerText(
            title: "Sharp Scaling is removed",
            message: "Its sizes go away after you reconnect \(display) or restart your Mac."
        )
    }

    // MARK: - Setup sheet

    static func sheetTitle(display: String) -> String {
        "Set Up Sharp Scaling for \(display)"
    }

    static func sheetMessage(native: SharpSize) -> String {
        "Resolute adds these sizes to the display’s override file. macOS draws each one at twice its size, "
            + "then scales it to the \(native.sizeText) panel."
    }

    static let sheetFootnote = "Saving asks for an administrator password and backs up the current file. "
        + "The sizes appear after you reconnect the display or restart."

    /// "Switch to the sharp 2560 × 1440 when it’s ready".
    static func switchTitle(_ size: SharpSize) -> String {
        "Switch to the sharp \(size.sizeText) when it’s ready"
    }

    /// "Add 5 Sizes…", "Add 1 Size…".
    static func confirmTitle(count: Int) -> String {
        switch count {
        case 0: "Add Sizes…"
        case 1: "Add 1 Size…"
        default: "Add \(count) Sizes…"
        }
    }

    /// "Drawn at 3200 × 1800".
    static func drawn(_ size: SharpSize) -> String {
        "Drawn at \(size.drawnText)"
    }

    /// "Text 60% larger", "Same size as now", or why the size is left out.
    static func note(for step: SharpScalingPlan.Step, in plan: SharpScalingPlan, current: SharpSize?) -> String {
        guard step.fits else {
            return plan.limit.isTooWide(step.size) ? "Too wide for this Mac" : "Too tall for this Mac"
        }
        if step.size == current { return "Same size as now" }
        return step.textLarger > 0 ? "Text \(step.textLarger)% larger" : "The panel’s own size"
    }

    /// The note about this Mac (66:1676): "This Mac can draw up to 6144 pixels wide on this
    /// display, so all five sizes fit. Sharp sizes stop at the panel’s own 2560 × 1440."
    static func limitNote(plan: SharpScalingPlan) -> String {
        let stop = "Sharp sizes stop at the panel’s own \(plan.native.sizeText)."
        let total = plan.steps.count, fitting = plan.sizes.count
        let fit: String
        switch (fitting, total) {
        case (1, 1): fit = "so the size fits"
        case (2, 2): fit = "so both sizes fit"
        case let (fitting, total) where fitting == total: fit = "so all \(word(total)) sizes fit"
        case (0, _): fit = "so none of the sizes fit"
        default: fit = "so \(word(fitting)) of the \(word(total)) sizes fit"
        }
        if let width = plan.limit.width {
            return "This Mac can draw up to \(width) pixels wide on this display, \(fit). \(stop)"
        }
        if let height = plan.limit.height {
            return "This Mac can draw up to \(height) pixels tall on this display, \(fit). \(stop)"
        }
        return "This Mac doesn’t say how large it can draw, so every size is offered, and Resolute names any size "
            + "macOS skips after the reconnect. \(stop)"
    }

    // MARK: - Pieces

    /// "5K" for a panel whose sharp size at its own resolution is drawn like a 5K display's.
    static func retinaClass(of native: SharpSize) -> String? {
        switch (native.drawnWidth, native.drawnHeight) {
        case (5120, 2880): "5K"
        case (3840, 2160): "4K"
        default: nil
        }
    }

    /// The captions under the sizes: "Larger Text" under the first and "Same as now" under
    /// the display's own size.
    static func caption(for size: SharpSize, at index: Int, current: SharpSize?) -> String? {
        if size == current { return "Same as now" }
        return index == 0 ? "Larger Text" : nil
    }

    /// The pictures for `sizes`, spread over the five stops from Larger Text to More Space.
    static func options(for sizes: [SharpSize], current: SharpSize?) -> [StopPicker.Option] {
        sizes.enumerated().map { index, size in
            StopPicker.Option(
                stop: stop(at: index, of: sizes.count),
                size: size.sizeText,
                caption: caption(for: size, at: index, current: current)
            )
        }
    }

    /// The picture for the `index`th of `count` sizes: the first is stop 1, the last stop 5.
    static func stop(at index: Int, of count: Int) -> Int {
        guard count > 1 else { return 5 }
        return 1 + Int((Double(index) * 4 / Double(count - 1)).rounded())
    }

    /// "a", "a and b", "a, b and c"
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }

    /// "five", as the design writes small counts in a sentence.
    static func word(_ number: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        return words.indices.contains(number) ? words[number] : String(number)
    }

    /// "9:42" in this Mac's format.
    static func time(of date: Date, timeZone: TimeZone, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    /// "today", "yesterday", "on 27 Oct".
    static func day(of date: Date, now: Date, timeZone: TimeZone, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        return "on " + date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).day().month(.abbreviated))
    }
}
