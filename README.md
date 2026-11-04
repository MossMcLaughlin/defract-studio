# Defract Studio

A local, native macOS editor for photos and single video clips. Edits are saved as metadata; imported originals stay untouched. Export creates a separate JPEG, PNG, or MP4. The Xcode target and app binary are still named `EditorApp`.

## Build and run

Requires an Apple Silicon Mac with macOS 15 or later, Xcode with the macOS SDK, and Xcode's Metal Toolchain component. Open `EditorApp.xcodeproj`, select the **EditorApp** scheme and **My Mac**, then Run. `EditorApp/App.swift` is the app entry point. No external packages, account, network service, or paid developer team is needed for local Debug builds.

For a command-line build and automated tests:

```sh
xcodebuild -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO test
```

## Edit a file

1. Click **Import** and choose JPEG, PNG, HEIC, MP4, or MOV files. Select a file in the left sidebar. Missing files can be relinked from the notice.
2. Use **Global → Easy** for Water Color, Color Recovery, Light, and Visibility. **Advanced** offers exposure, tone, white balance, saturation, vibrance, eight color-band Hue/Saturation/Luminance controls, Clarity, Dehaze, Detail noise protection, and output Sharpening for new edits. Manual Advanced refinements remain in place when Easy sliders move. Dehaze uses a conservative whole-scene water estimate; masks offer local Clarity but not local Dehaze.
3. Use **Crop & Rotate** for aspect, position, quarter turns, and straighten. Photos can use **Masks → Select Subject** when Vision finds a foreground subject, or **Brush** for manual selection. Brush Add/Erase, feather, inversion, linear and radial masks, and separate local color adjustments are available. Videos support static linear and radial masks only.
4. On videos, set the In and Out values below the preview. Use Play/Pause to review. **Before/After** shows the source color without changing the saved recipe. Undo is ⌘Z; Redo is ⇧⌘Z.
5. Click **Export…** (⌘E). Choose Instagram, General, or Maximum Quality; choose a frame, Fit or Fill, dimensions, format/codec, name, and output folder. The preview updates to the chosen frame. **Fit** pads the image; **Fill** crops it. Export asks before replacing an existing file and writes a temporary file first. Cancel is available while exporting; **Show in Finder** appears on success.

Use **File > New Project** (⌘N) for an empty workspace, **Open Project…** (⌘O) for a saved `.defractproject`, **Save Project** (⌘S) or **Save Project As…** (⇧⌘S) to choose a location, and **Delete Project…** to move the active saved project to Trash after confirmation. A project references original media and contains its edits; it does not copy media. Switching or closing with unsaved project changes offers Save, Discard, or Cancel. An older implicitly restored session is recoverable as an unsaved project until saved or deliberately discarded. Missing sources are hidden from the sidebar and listed once on opening; their saved edits remain in the project. Legacy per-file histories are stored in `~/Library/Application Support/PhotoVideoEditor/Projects/` until migrated. Photo exports default to `~/Pictures/PhotoVideoEditor/Exports/` and video exports to `~/Movies/PhotoVideoEditor/Exports/`; the chosen folder is remembered by media type.

## Scope and limits

The editor processes SDR media into 8-bit sRGB photos or Rec.709 MP4. The supplied `GX011247.MP4` is 10-bit HEVC Main 10 **SDR**; a new-edit Maximum Quality HEVC export from this source was verified as decoded 10-bit SDR on the development Mac. H.264 remains the compatibility choice. HDR and RAW-specific workflows, multi-clip editing, video subject tracking, and batch export are outside this MVP. Automatic subject selection depends on Apple's Vision result; manual brush selection is always available for photos.

See `VERIFICATION_REPORT.md` for machine-tested results and open checks; `DEV_NOTES.md` for the actual architecture; `PRODUCT_MVP.md`, `UX_SPEC.md`, and `COLOR_ENGINE.md` for approved behavior; and `MEDIA_AND_TESTS.md` for local fixtures. `reference/STYLE_GUIDE_v0.1.md` and `reference/UI_REFERENCE.png` are the visual references.

## Implementation handoffs

Place the next approved task and any temporary screenshots or reference assets in `.handoff/current/` (create it if absent). The folder is ignored by Git. Codex reads that task and only the relevant current documents, implements and verifies it, then updates the affected canonical documents and `VERIFICATION_REPORT.md`. Once verified and captured in tracked documentation, temporary handoff material can be cleared. Older specifications and completed gate plans remain available in Git history.
