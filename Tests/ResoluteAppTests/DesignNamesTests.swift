import ResoluteDesign
import ResoluteKit
import Testing

/// Kit and the design system name the display pictures with the same strings, so the app
/// maps one to the other by raw value.
@Suite struct DesignNamesTests {
    @Test func displayPicturesShareTheirNames() {
        let pictures = DisplayPictureModel.allCases.map(\.rawValue)
        #expect(DisplaySkin.allCases.map(\.rawValue) == pictures)
        #expect(DisplayIcons.skins == pictures)
    }
}
