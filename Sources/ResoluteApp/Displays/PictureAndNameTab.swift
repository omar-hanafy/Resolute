import ResoluteDesign
import ResoluteKit
import SwiftUI

/// A display's Picture & Name tab: the picture macOS draws for it, the name macOS shows, and
/// a preview of System Settings › Displays (Figma 34:866). Both go into the same draft as
/// the custom resolutions, which the page's unsaved bar saves together.
struct PictureAndNameTab: View {
    let model: AppModel
    @Bindable var editor: CustomResolutionsModel
    /// The connected display; nil when it is away.
    let display: Display?

    var body: some View {
        if editor.draft != nil {
            let choices = DisplayPagePresentation.pictureChoices(canChoose: editor.canChoosePicture)
            GroupedSection(
                "Picture",
                detail: "How macOS draws this display in System Settings › Displays",
                footnote: footnote(for: choices)
            ) {
                PictureChoicePicker(
                    choices,
                    selection: editor.pictureSkin.flatMap(DisplayPictureModel.init(rawValue:))
                ) { picture in
                    editor.choosePicture(picture.rawValue)
                }
            }
            FormGroup {
                FormRow("Name shown by macOS", help: "Leave empty to use the name the display reports.") {
                    TextField(
                        "Name shown by macOS",
                        text: $editor.productName,
                        prompt: Text(ownName)
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Metrics.DisplayPage.nameFieldWidth)
                }
            }
            GroupedSection("Preview", detail: "System Settings › Displays") {
                DisplayArrangement(arrangement)
            }
        } else if let reason = editor.readFailure {
            Banner("The override can't be read", message: reason, tone: .warning)
        }
    }

    /// The name the display reports, which an empty field keeps.
    private var ownName: String {
        display?.name ?? editor.selectedTarget?.name ?? "The display's own name"
    }

    private func footnote(for choices: [PictureChoicePicker.Choice]) -> String? {
        if editor.pictureSkin == DisplayIcons.custom {
            return "Another app chose this display's picture. Choosing one here replaces it."
        }
        return DisplayPagePresentation.unavailablePicturesNote(choices)
    }

    /// The connected displays as System Settings shows them, this one with its unsaved
    /// picture and name; a display that is away on its own.
    private var arrangement: [DisplayArrangement.Item] {
        let name = editor.productName.isEmpty ? ownName : editor.productName
        guard let display else {
            let picture = DisplayPagePresentation.picture(draftSkin: editor.pictureSkin, fallback: .display)
            return [DisplayArrangement.Item(id: "edited", picture: picture, name: name, isEmphasized: true)]
        }
        return model.displays.map { other in
            let isEdited = OverrideKey(display: other) == OverrideKey(display: display)
            let saved = model.skin(for: other)
            let picture = isEdited
                ? DisplayPagePresentation.picture(draftSkin: editor.pictureSkin, fallback: DisplaySkin.suggestion(for: other, details: model.details(for: other)))
                : DisplayPictureModel(rawValue: saved.rawValue) ?? .display
            return DisplayArrangement.Item(
                id: String(other.id), picture: picture, name: isEdited ? name : other.name, isEmphasized: isEdited
            )
        }
    }
}
