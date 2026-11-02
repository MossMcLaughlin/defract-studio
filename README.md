# Photo & Video Editor

A local, native macOS editor for photos and single video clips. Edits are saved as metadata; imported originals stay untouched. Export creates a separate JPEG, PNG, or MP4.

## Build and run

Requires an Apple Silicon Mac with macOS 15 or later and Xcode with the macOS SDK. Open `EditorApp.xcodeproj`, select the **EditorApp** scheme and **My Mac**, then Run. `EditorApp/App.swift` is the app entry point. No external packages, account, network service, or paid developer team is needed for local Debug builds.

For a command-line build and automated tests:

```sh
xcodebuild -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO test
```

## Edit a file

1. Click **Import** (⌘O) and choose JPEG, PNG, HEIC, MP4, or MOV files. Select a file in the left sidebar. Missing files can be relinked from the notice.
2. Use **Global → Easy** for Water Color, Color Recovery, Light, and Visibility. **Advanced** offers exposure, tone, white balance, saturation, vibrance, and eight color-band Hue/Saturation/Luminance controls. Manual Advanced refinements remain in place when Easy sliders move.
3. Use **Crop & Rotate** for aspect, position, quarter turns, and straighten. Photos can use **Masks → Select Subject** when Vision finds a foreground subject, or **Brush** for manual selection. Brush Add/Erase, feather, inversion, linear and radial masks, and separate local color adjustments are available. Videos support static linear and radial masks only.
4. On videos, set the In and Out values below the preview. Use Play/Pause to review. **Before/After** shows the source color without changing the saved recipe. Undo is ⌘Z; Redo is ⇧⌘Z.
5. Click **Export…** (⌘E). Choose Instagram, General, or Maximum Quality; choose a frame, Fit or Fill, dimensions, format/codec, name, and output folder. The preview updates to the chosen frame. **Fit** pads the image; **Fill** crops it. Export asks before replacing an existing file and writes a temporary file first. Cancel is available while exporting; **Show in Finder** appears on success.

Edits and undo history are stored in `~/Library/Application Support/PhotoVideoEditor/Projects/`. Closing with edits that have not been exported offers Export, Close & Keep Edits, or Cancel. Keeping edits does not render a copy; reopen the app to continue. Photo exports default to `~/Pictures/PhotoVideoEditor/Exports/` and video exports to `~/Movies/PhotoVideoEditor/Exports/`; the chosen folder is remembered by media type.

## Scope and limits

The editor processes SDR media into sRGB photos or Rec.709 MP4. The supplied `GX011247.MP4` is 10-bit HEVC Main 10 **SDR**, and its export is intentionally converted to an SDR delivery codec. HDR and RAW-specific workflows, multi-clip editing, video subject tracking, and batch export are outside this MVP. Automatic subject selection depends on Apple's Vision result; manual brush selection is always available for photos.

See `VERIFICATION_REPORT.md` for exact machine-tested results and limits, `DEV_NOTES.md` for implementation details, and the remaining specification documents for the original product contract.
