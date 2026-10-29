import Foundation
import Testing
@testable import ResoluteApp
@testable import ResoluteKit

/// What the menu bar panel shows for Figma's sample displays.
@MainActor
@Suite struct PanelContentTests {
    let scratch = ScratchDefaults()
    let root = FileManager.default.temporaryDirectory.appending(path: "ResolutePanelTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    func model(_ samples: [SampleDisplays.Sample], mirroring: Bool = false) -> AppModel {
        let service = FakeDisplayService(displays: samples.map(\.display))
        if mirroring { try? service.setMirroring(true) }
        return AppModelTests.makeModel(service: service, preferences: Preferences(defaults: scratch.defaults), overridesRoot: root)
    }

    @Test func showsACardForEachDisplayWithItsStopsAndRates() throws {
        let cards = PanelContent.cards(for: model([SampleDisplays.builtInRetina, SampleDisplays.dellU2723QE]))
        #expect(cards.map(\.name) == ["Built-in Retina Display", "DELL U2723QE"])
        #expect(cards.map(\.summary) == ["1728 × 1117 · 120 Hz", "2560 × 1440 · 60 Hz"])
        #expect(cards[0].badge == PanelContent.Badge(text: "Default"))
        #expect(cards[1].badge == nil)
        #expect(cards.map(\.skin) == [.macBookPro, .display])
        guard case .stops(let stops, let caption, let isBuiltIn) = cards[0].sizes else { Issue.record("no stops"); return }
        #expect(stops.map(\.title) == ["1168 × 755", "1312 × 848", "1496 × 967", "1728 × 1117", "2056 × 1329"])
        #expect(stops.firstIndex(where: \.isSelected) == 3)
        #expect(caption == "1728 × 1117 · Default" && isBuiltIn)
        #expect(cards[0].refreshRates.map(\.title) == ["120 Hz", "60 Hz", "50 Hz", "48 Hz"])
        #expect(cards[1].refreshRates.map(\.title) == ["60 Hz", "50 Hz", "30 Hz"])
        #expect(cards.map(\.resolutionCount) == [22, 19])
        #expect(cards.allSatisfy { $0.isResponding })
    }

    @Test func showsAMirrorSetAsOneCard() {
        let cards = PanelContent.cards(for: model([SampleDisplays.builtInRetina, SampleDisplays.dellU2723QE], mirroring: true))
        #expect(cards.count == 1)
        #expect(cards.first?.name == "Built-in + DELL U2723QE")
        #expect(cards.first?.summary.hasPrefix("Mirroring · ") == true)
        #expect(cards.first?.skin == .display)
        #expect(cards.first?.badge == nil)
    }

    @Test func listsAStandardDisplaysResolutionsForItsPopUp() throws {
        let card = try #require(PanelContent.cards(for: model([SampleDisplays.asusPA278QV])).first)
        #expect(card.badge == PanelContent.Badge(text: "Standard"))
        guard case .resolutions(let sizes) = card.sizes else { Issue.record("no resolutions"); return }
        #expect(sizes.first?.title == "2560 × 1440 · Native")
        #expect(sizes.first?.isSelected == true)
        #expect(sizes.first?.accessibilityLabel == "2560 by 1440, Native")
        #expect(sizes.filter(\.isSelected).count == 1)
    }

    @Test func listsEveryModeWithHiddenOnesNamedAsMonitorsAreSold() throws {
        let dell = SampleDisplays.dellU2723QE.display
        let lists = AllResolutionsLists(display: dell, showsLowResolution: false, includeLowResolution: true, includeHidden: true)
        #expect(lists.hasTabs)
        #expect(lists.listed.map(\.size) == ["3360 × 1890", "3008 × 1692", "2560 × 1440", "2304 × 1296", "1920 × 1080", "1600 × 900", "1280 × 720"])
        #expect(lists.listed.filter(\.isCurrent).map(\.size) == ["2560 × 1440"])
        #expect(lists.listed.first { $0.size == "1920 × 1080" }?.tag == "Default")
        #expect(lists.hidden.map(\.tag) == ["Hidden", "Hidden · 21:9", "Hidden"])
        #expect(lists.hidden.allSatisfy { $0.isHidden })
        let row = try #require(lists.listed.first)
        #expect(row.detailedTag == "6720 × 3780 px · mode \(row.mode.modeID)")
        let oneX = AllResolutionsLists(display: dell, showsLowResolution: true, includeLowResolution: true, includeHidden: false)
        #expect(oneX.listed.allSatisfy { !$0.mode.isHiDPI })
        #expect(oneX.hidden.isEmpty)
    }

    @Test func opensOnTheCardsWithDetailsOnlyWhileOptionIsHeld() {
        let model = model([SampleDisplays.builtInRetina, SampleDisplays.dellU2723QE])
        model.panelAllResolutions = SampleDisplays.dellU2723QE.display.id
        model.panelWillOpen(showingDetails: true)
        #expect(model.panelAllResolutions == nil)
        #expect(model.panelShowsDetails)
        model.panelWillOpen(showingDetails: false)
        #expect(!model.panelShowsDetails)
    }
}
