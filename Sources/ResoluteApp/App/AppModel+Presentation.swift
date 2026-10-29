import CoreGraphics
import ResoluteKit

/// What the panel and the window say about a display: its facts, its Larger Text ↔ More
/// Space stops and its picture, from the same details everywhere.
extension AppModel {
    /// The display's physical size and Mac model, read once per display.
    func details(for display: Display) -> DisplayDetails {
        if let details = detailsByDisplay[display.id] { return details }
        let details = readDetails(display)
        detailsByDisplay[display.id] = details
        return details
    }

    /// "16.2-inch · 3456 × 2234 pixels · ProMotion up to 120 Hz", the badge, the count of
    /// resolutions.
    func facts(for display: Display) -> DisplayFacts {
        DisplayFacts(display: display, details: details(for: display))
    }

    /// The five Larger Text ↔ More Space stops; nil for a standard display.
    func stops(for display: Display) -> SpaceStops? {
        SpaceStops(display: display)
    }

    /// The picture to draw: the one chosen in Picture & Name, else the one that suggests
    /// the display. A picture Resolute did not write ("custom") or none ("display") falls
    /// back to the suggestion, since either looks like the display to the person.
    func skin(for display: Display) -> DisplaySkin {
        if let chosen = overridePictures[OverrideKey(display: display)].flatMap(DisplaySkin.init(rawValue:)),
           chosen != .display {
            return chosen
        }
        return DisplaySkin.suggestion(for: display, details: details(for: display))
    }
}
