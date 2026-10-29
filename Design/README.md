# Design artwork

Artwork exported from the [Resolute Figma file](https://www.figma.com/design/84S2G57E0NBXaPpaVxg8C7/Resolute)
as PDF, which macOS draws as vectors at any size. The app doesn't read these files: they
are embedded in `ResoluteDesign` as Swift data, and the app icon is packed into
`Resources/AppIcon.icns`.

| File | Figma node |
| --- | --- |
| `DisplayPictures/macBookPro.pdf` | Components › Display Picture › Model=MacBook Pro (9:11) |
| `DisplayPictures/iMac.pdf` | Model=iMac (9:20) |
| `DisplayPictures/studioDisplay.pdf` | Model=Studio Display (9:27) |
| `DisplayPictures/proDisplayXDR.pdf` | Model=Pro Display XDR (9:34) |
| `DisplayPictures/display.pdf` | Model=Display (9:41) |
| `DisplayPictures/ultrawide.pdf` | Model=Ultrawide Display (9:48) |
| `DisplayPictures/tv.pdf` | Model=TV (9:55) |
| `AppIcon/default.pdf` | Components › App Icon › Appearance=Default (26:454), the master on the App Icon page (46:5) |
| `AppIcon/dark.pdf` | Appearance=Dark (26:464) |

Each file is the whole component exported from Figma as PDF at 1×, so it keeps the
component's frame (160 × 120 for a display picture, 128 × 128 for the icon). A display
picture's file is named after its `DisplayPictureModel` case.

After adding or changing a file:

- `swift Scripts/embed-assets.swift` rewrites `Sources/ResoluteDesign/Assets/EmbeddedArtwork.swift`.
  The tests fail until the embedded bytes match these files.
- `make icon` rewrites `Resources/AppIcon.icns` from `AppIcon/default.pdf`.
