# Development notes

`EditorApp.xcodeproj` has one macOS app target (`EditorApp/`), one portable framework (`EditorCore/`), and one XCTest target (`EditorTests/`). `EditorApp/App.swift` is the entry point. The target is macOS 15+ on Apple Silicon. Local Debug builds are unsandboxed and need no external package; sandboxed distribution would require security-scoped source bookmarks, signing, and further testing.

## Where behavior lives

| Concern | Current source |
|---|---|
| Canonical recipe, Easy base/manual delta/effective values, Easy mapping knots | `EditorCore/Recipe.swift` |
| Color math and shared Core Image rendering | `EditorCore/ColorMath.swift`, `EditorCore/Core.swift` |
| Source-aligned masks, inverse copy, radial angle, ordered local blending | `EditorCore/Masks.swift` |
| Crop/rotation and Fit/Fill output framing | `EditorCore/Geometry.swift`, `EditorCore/OutputFrame.swift` |
| Atomic JSON project storage and bounded undo/redo | `EditorCore/ProjectStore.swift` |
| Editor state, autosave, selection, preview scheduling | `EditorApp/EditorModel.swift` |
| Photo/video decoding, compositions, exports | `EditorApp/MediaIO.swift` |
| UI style colors/spacing, workspace and Color Mixer | `EditorApp/App.swift`; `EditorApp/MaskInspector.swift` |
| Export presets and dialog | `EditorApp/ExportOptions.swift`; `EditorApp/ExportSheet.swift` |
| Vision subject trial and native close/quit continuation | `EditorApp/VisionMask.swift`; `EditorApp/WindowCloseObserver.swift` |

`EditRecipe` is the only saved edit description. Easy changes recompute base contributions; Advanced writes a delta relative to the base; the renderer receives effective values. A slider drag edits a transient draft and commits one history transaction on release. Local masks use the same Advanced parameter definitions without Easy bases. Enabled masks process in saved order after the global grade. Brush strokes and optional Vision matte remain in source coordinates through preview zoom, crop, and export. An inverse copy clones the editable selection definition with a new ID and neutral local grade; `rotationDegrees` is optional so older mask JSON decodes at zero angle.

`ProjectStore` keeps edits and history in `~/Library/Application Support/PhotoVideoEditor/Projects/`. Sources are absolute paths in this unsandboxed build; a missing file needs manual relinking. Corrupt JSON is left on disk while other sessions recover. Preview images/caches are disposable. `EditorModel` saves committed edits; Close & Keep Edits saves all histories before closing. An autosave failure is shown and prevents that close path.

`MediaIO` adapts photos and video to one `CoreRenderer` grade and geometry path. Photo preview uses a cached downsampled source (900 pixels while dragging, 1800 when idle); cancellation and revision checks prevent stale frames from publishing. Full-resolution photo export reopens the source. Video updates the existing player's item composition on edit; preview and export use the same macOS 15-compatible `AVMutableVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:completionHandler:)` handler. The macOS 26-only initializer is not used. The 33³ color cube is cached by adjustment values; temperature/tint use Core Image's temperature-and-tint filter. These are conservative photographic formulas, not Lightroom parity.

Photo JPEG/PNG exports are sRGB; video MP4 delivery is Rec.709 SDR with source audio preserved when present. The supplied `GX011247.MP4` is HEVC Main 10 **SDR**, and compatible SDR delivery may be 8-bit. Both photo and video exports write a sibling temporary file, validate readable output, then move/replace only on success. `ExportOptions.swift` defines preset dimensions and formats. The export sheet temporarily previews the chosen output frame; its completion UI clears on a fresh sheet or source switch. No RAW-specific workflow or HDR mastering is promised.

Fit uses black padding to retain the entire cropped source at the requested output aspect; Fill crops overflow without stretching. Preview and export use the same framing operation. The older reference architecture's proposed nested source folders and package-style project schema were illustrative; the actual flat target folders and one JSON history file per media item are the maintained implementation.

The workspace uses a narrow collapsible sidebar, a central media canvas, and a 340-point right inspector. `EditorTheme`, `EditorTabs`, `InspectorSliderRow`, and `GoldSliderTrack` in `EditorApp/App.swift` hold the shared UI styling; `EditorApp/MaskInspector.swift` reuses it. The slider modifier overlays a non-interactive gold fill on the native control because `.tint` alone left the active track gray on the tested macOS build. Both inspector scroll views keep 28 points of trailing content clearance. The preview footer reads display-oriented dimensions from the selected source metadata. The approved direction is in `UX_SPEC.md` and `reference/STYLE_GUIDE_v0.1.md`; `reference/UI_REFERENCE.png` is a concept, not an app screenshot. See `VERIFICATION_REPORT.md` for tested results and open checks.
