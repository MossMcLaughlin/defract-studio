# ARCHITECTURE.md — Reference Architecture, Project Schema and Media Rules

**Authoritative status:** build specification for macOS v1, not an assertion that implementation was validated here. The agent must use its installed Xcode/SDK to confirm API availability, compile, and test. User-level product and UX decisions take precedence over incidental API suggestions.

## 1. Deployment and package layout

- Native macOS application, **macOS 15 or later**, **Apple Silicon (M1+)**. This is the initial chosen target, not a claim that the user's machine was tested. If their Mac cannot run it, report the exact compatibility issue and choose the nearest supported native target with minimal changes.
- **Swift + SwiftUI**, AppKit only for macOS-specific file pickers, pointer interactions, window/toolbar, or zoom/canvas behaviors that SwiftUI cannot handle reliably. **Core Image** for shared rendering; **Metal** only where a targeted GPU kernel is necessary; **AVFoundation** for video; **ImageIO/CoreGraphics** for photos/profiles; **Vision** for photo foreground segmentation.
- No remote processing, user accounts, in-app LLM, analytics, auto-download of ML models, or third-party runtime dependencies. Prefer shipping the Xcode project with a Swift shared core module and a macOS app target; don't erect a plugin system, event bus, class hierarchy of filters, or unnecessary mock layers.
- **Future iPhone app:** Keep `EditRecipe`, parameter mapping, mask geometry, and renderer independent of AppKit; use foundation/Core Image/portable Swift APIs. Mac window, file access, export dialogs, and shortcuts are thin platform adapters. Do not create an iOS target in v1.

Suggested minimum source grouping (rearrange modestly to fit Xcode idioms):

```text
EditorApp/
  App/                   main app, state coordinator, menus
  Views/                 workspace, sidebar, inspector, canvas, dialogs
  Platform/              macOS file dialogs, security bookmarks, cache paths
EditorCore/
  Models/                EditRecipe, color state, geometry, masks, media metadata
  Color/                 adjustment formulas, 8-band HSL mixer, underwater LUT
  Rendering/             Core Image pipeline and reusable render context
  Masks/                 normalized mask shapes, strokes, matte composition
  Media/                 decoding adapters, metadata/color/orientation
  Export/                photo+video format and geometry processing
EditorTests/             unit, integration and fixture-driven tests
```

Do not multiply packages when one module with folder organization works. Keep the public interface of the shared core intentionally small.

## 2. Single source of truth: edit recipe

Each imported item gets a stable `mediaID` and non-destructive `EditRecipe`. All UI controls read/write this model; it is passed to photo and video renderers. The application is the authority for in-memory edit state, and autosaves committed changes. **Never edit or overwrite the original source file.**

Illustrative schema, fields not a literal Swift Codable implementation:

```json
{
  "schemaVersion": 1,
  "mediaID": "UUID",
  "source": {
    "displayName": "P8110319.JPG",
    "pathHint": "/some/original/location/P8110319.JPG",
    "bookmarkBase64": "platform-specific if sandboxed",
    "fileSize": 347311,
    "mediaKind": "photo",
    "detectedOrientation": 1,
    "metadataFingerprint": "optional stable identifier"
  },
  "underwaterMappingVersion": 1,
  "easy": {"waterColor": 0, "colorRecovery": 0, "light": 0, "visibility": 0},
  "manualDelta": {"exposureEV": 0, "contrast": 0, "temperature": 0},
  "globalEnabled": true,
  "masks": [],
  "geometry": {
    "rotateQuarterTurns": 0,
    "straightenDegrees": 0,
    "cropNormalized": null,
    "outputAspect": "original",
    "fitOrFill": "fit",
    "repositionNormalized": [0.5, 0.5]
  },
  "video": {"trimStartSeconds": 0, "trimEndSeconds": null},
  "lastExportFingerprint": null,
  "lastModifiedUTC": "ISO8601"
}
```

The actual `manualDelta` model MUST enumerate every Advanced parameter in `COLOR_ENGINE.md` (including all 24 HSL values), preferably via one strongly-typed Codable struct. Mask-specific adjustments use the same parameter struct but **do not** inherit global Easy bases; mask-local adjustments are simply Advanced local deltas. Schema fields not applicable to a media type should be absent or default neutral.

Save project records in `Application Support/<AppName>/Projects/<mediaID>/recipe.json`, plus optional `masks/` files and bounded persisted `history.json`/diff records. Store an index for the current imported file list and last selected file. Use **versioned Codable**, explicit upgrade/default rules, atomic write-and-rename, and graceful recovery if files are missing or schema is newer. Do not use a database for this MVP.

`source.pathHint` is for display/relink; in a sandboxed build use a security-scoped bookmark with appropriately balanced `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource`. Verify bookmark handling against the actual signing/sandbox configuration; do not hardcode development-machine paths. If a source is moved, show Relink; verify fingerprints where practicable to avoid attaching the wrong file.

## 3. Memory, preview caching and history

- Opening a photo creates a downsampled working preview at an appropriate screen pixel size; keep original compressed media unchanged on disk. Open/export full-resolution source on demand.
- Opening video reads original media with AVFoundation, generates/computes filtered frames as needed. Do **not** duplicate a complete 4K/5K video to a temporary file. Downscale preview composition if needed; preserve true export resolution.
- Caches are **derived and disposable**. Eviction must not discard edits or trigger export. Cache keys include source fingerprint, renderer/mapping version, edit revision, orientation and preview dimensions; use bounded NSCache-like behavior.
- Autosave committed actions immediately or with short debounce/atomic flush; save in-memory transient state on safe checkpoints; on crash reopen from last committed state. Failure to autosave must be visible and must never silently lose the only copy.
- Save a **bounded undo/redo history of about 30–50 user transactions per item**, including relevant edits to controls, masks, crop, trim. A drag or brush stroke is one transaction, not hundreds of history entries. Persist history with the project if practical; if persistence fails report and preserve current recipe. Avoid saving full-resolution image snapshots in history; store command/snapshot deltas or stroke records. After a new edit, redo clears.
- Import multiple items but process/export **one selected file at a time**; no background batch processing.

### Close / navigation rules (source of truth)

Because edits autosave, **switching selected files, changing inspector tabs and cache eviction need no Save prompt**. When closing an app/window that has *edits newer than the latest export*, show a simple non-blocking user choice: **Export… / Close & Keep Edits / Cancel**. `Close & Keep Edits` closes safely because recipes were already saved; `Export…` completes current one-file export before close, and never implies that metadata storage requires export. Explicit "Discard Edits" / "Remove from Session" must warn first. Do not prompt for unmodified/unexported original imports. This reconciles the user's desire for an export reminder with zero-loss persistence and minimal interruptions.

## 4. Shared color/geometry processing pipeline

One `evaluateEasyBase(easy, mappingVersion) -> AdjustmentVector`, one `effective = clamp(base + manualDelta)`, one shared `render(sourceFrame, recipe, outputDescription)` pipeline. All active adjustments are applied through the same Core Image logic for stills and video frames. Apply globally once, then compose each enabled local mask correction in saved order. Ensure masks do not multiply the global correction accidentally (mask-local edited result is blended over the current globally edited image).

For each frame:

1. Decode source and determine stored orientation/display transforms; honor source metadata.
2. Normalize geometric orientation and working coordinates (upright, clean image origin). Provide stable normalized source coordinates (0–1) to masks/brushes, independent of preview zoom.
3. Convert source RGB color/profile/transfer to a defined rendering working space.
4. Apply global exposure/white balance, tone, saturation/vibrance, HSL mixer in the documented order. Neutral parameters must be identity.
5. Evaluate each enabled local mask using the same Advanced adjustment definitions; blend by a 0–1 soft alpha mask, preserving original/background unaffected pixels. Multiple masks are composed deterministically in list order.
6. Apply geometry/crop/rotation and fit/fill framing in **upright coordinates**, accounting for source pixel aspect and display transforms.
7. Convert to display or export color target with appropriate metadata and precision; generate error if a required conversion is unsupported.

**HSL-specific implementation:** Core Image does not offer an exact Adobe Color Mixer equivalent. Build a small continuous 8-band hue mixer using a carefully designed shader / Core Image kernel or a sampled color cube (CIColorCube) as justified by performance. Hue operations must be in a documented encoded color representation (not accidentally treating linear RGB as perceptual HSL). Smooth circular band weights and avoid hue discontinuities, visible banding and desaturation edge artifacts. Cache stable lookup tables by mixer parameter vector if using LUTs; do not regenerate a large 3D cube per rendered video frame. If blending near the edges creates problems, prefer mathematically simple, correct behavior over elaborate speed hacks.

For photo masking, automatic Vision foreground extraction is a **best-effort tool**, not a precondition to using brush selection. Save the generated alpha matte (if one was returned) together with user add/erase strokes in upright/source-normalized coordinates. Avoid overwriting or rerunning a changed mask. If high-resolution masks are unavailable, make upscaled matting look sensible with user feather/edge brush; don't pretend ML edge quality is perfect. Use crop-independent mapping; after crop or rotation, mask continues to follow original subject.

Video masks are **static only**: source-normalized linear/radial gradients anchored to the upright source frame and applied to each video frame. No video brush, foreground AI, tracked mask, or per-frame keyframes.

## 5. Color management and HDR policy

**Rules — critical acceptance requirements:**

1. **Read profiles, don't guess:** Inspect image ICC/EXIF orientation, video codec, primaries, transfer function, matrix, video preferred transform and pixel format. Be conscious that a camera's marketing setting "Flat" is not an automatically recognized professional Log transform. Don't invent camera-specific LUTs or mislabel footage.
2. **Internal working color:** Use `extendedLinearSRGB` / Core Image's managed extended linear-sRGB working space and sufficient internal precision. Verify `CIContext` input/output color management and avoid duplicate gamma conversions. In particular, nonlinear white-balance, HSL and perceptual tone operations must explicitly convert into the domain they expect rather than blindly applying an sRGB HSL kernel to linear RGB.
3. **SDR output:** JPEG/PNG output should be sRGB-tagged; video output should carry Rec.709 primaries/transfer/matrix where encoder exposes them. Avoid leaving metadata unspecified when that changes display.
4. **10-bit SDR:** Explicit required real-media test on `GX011247.MP4` (HEVC Main 10, `yuv420p10le`, Rec.709 SDR). Maintain adequate decode/working precision and consistent display. SDR export may be 8-bit H.264/HEVC depending on preset, but must not silently misinterpret the source as 8-bit or HDR. Verify color, portrait orientation and audio in the export. The user needs correct appearance more than 10-bit container output in v1.
5. **HDR:** Initial promise is reliable **SDR**, not HDR mastering. If an HDR input can be safely tone-mapped to SDR, implement an explicit, deterministic tone map and report the output. If it cannot, show a useful unsupported/HDR-conversion warning rather than silently treating PQ/HLG as Rec.709. Full HDR preview/edit/export is deferred.
6. **Orientation:** Prefer source transform / rotation metadata for display. Generate rotated, dimension-correct output according to chosen orientation; verify the source's pixel width/height and track transform may differ. Never infer portrait vs landscape from raw dimensions alone.
7. **Parity:** Photo previews and video preview/export apply the exact same recipe, mask geometry, and output transfer behavior. Differences from downsampling/codec must be within stated tolerances, not gross color shifts.
8. **Clipping and noise:** A slider should not claim to restore physically absent red light or detail lost to backscatter. Limit operations for conservative startup and avoid NaN/Inf/overflow.

### Output geometry contract

Source frame after orientation is `(W,H)`. Optional crop defines an upright image rectangle. "Original" uses that post-crop aspect. For a fixed target `(outW,outH)` the user chooses:

- **Fit:** scale uniformly to show entire cropped image; center with matte/padding. **Photos:** default matte warm-neutral or black selectable? v1 choose neutral black (#000000) for predictable media appearance. **Videos:** black matte (#000000), no alpha.
- **Fill:** scale uniformly to cover target and crop overflow using normalized anchor `(x,y)`; no stretching.

Never silently turn a horizontal source into a vertical export with accidental black borders or unannounced crop. Rotation 90-degree may swap displayed dimensions and the exported output must remain upright for common clients. Preview must show the same output framing.

## 6. Image export

Use ImageIO/Core Image/CoreGraphics as appropriate, render full resolution after crop to chosen `(outW,outH)` and tag ICC sRGB. JPEG quality presets: Instagram 0.88; General 0.90; Maximum JPEG 0.95, optional PNG. These quality levels are initial defaults and may be revised after testing. Preserve sensible non-sensitive metadata only (orientation normalized; avoid accidentally leaking locations when optional metadata stripping selected). User chooses path, filename and overwrite confirmation. An output written to temporary file must be finalized atomically on success.

Default output directory: `~/Pictures/<AppName>/Exports/`; user choice remembered. If target format is unsupported, remove its option from UI with explanation rather than failing after save.

## 7. Video preview and export

**Compatibility requirement for macOS 15:** Apple's newest SDK docs show `AVVideoComposition.init(applyingFiltersTo:applier:)` using `AVCIImageFilteringParameters` → `AVCIImageFilteringResult`, but these are part of the macOS/iOS 26 SDK-era additions and must **not** be called unguarded for a macOS 15 deployment target. For macOS 15–25 select the last supported Core Image video composition handler API; the async `AVVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:completionHandler:)` is an appropriate candidate even if newer SDK docs mark it deprecated. Use the macOS 26 API behind a valid availability guard only when useful, or keep one older supported implementation if it remains correct. Validate real preview/export on the deployment target. Keep the filter closure stateless/immutable relative to the selected recipe snapshot where safe. If live slider changes require rebuilding/reassigning the composition, use a debounced snapshot and validate playback behavior rather than introducing data races.

Apply trim as CMTime boundaries in the source's presentation timeline with precision and inclusive/exclusive semantics: **start inclusive, end exclusive**, clamped to available duration. UI displays friendly rounded values, but stored times should preserve precise CMTime representation (e.g. rational value/timescale) or high-precision seconds with reliable conversion. Default full duration. Guard against inverted/zero-length trims. Audio follows same segment; preserve at least one supported main audio track unmodified. Do not provide an audio mixing UI.

**Presets (starting defaults):**

- Instagram Reel/Story: MP4 H.264, 1080×1920, preserve source fps up to 60 if feasible. User must explicitly choose Fit (padding) or Fill (crop) if source aspect differs.
- Instagram landscape/feed: offer 1080×1350 for 4:5 feed (stills by default), 1920×1080 for wide video when selected.
- General: MP4 H.264, source orientation, source fps, source resolution capped at 3840×2160 in displayed orientation; offer 1080p as simple alternative. When source is portrait, cap the *long* displayed dimension to 3840 with proportionate short dimension, not a forced landscape ratio.
- Maximum Quality: HEVC MP4 if supported and sufficient compatibility; original edited displayed dimensions up to the supported encoder limits, source fps; user can choose H.264 compatibility instead. `Maximum` is high-quality compressed output, not ProRes/lossless.

**Important:** output format support and encoder settings must be queried on the actual Mac. Some AVAssetExportSession presets don't guarantee arbitrary crop sizes, codec choice or color tags. Use the simplest tested AVFoundation exporter first; if it cannot render the chosen custom geometry with preserved audio and H.264/HEVC output, use an `AVAssetReader` → shared Core Image render → `AVAssetWriter` pipeline (with audio passthrough where supported), but **only after the test proves necessary**. Do not silently ignore explicit output dimensions or apply an unwanted crop.

Video export writes to a temporary URL, reports progress/cancel, validates result file can be probed, has expected orientation/duration, contains audio if source had audio, and succeeds atomically. On error/cancel clean partial output, keep edit session, explain cause and allow retry. Default path: `~/Movies/<AppName>/Exports/`. A user-supplied output filename must not overwrite an existing original.

## 8. Performance and resource limits

- Responsiveness target at 1080p/30fps preview with basic corrections on a representative M1+ Mac; do not promise smooth 5.3K native playback. Use adaptive downscaled preview/resolution/cache. Launch/open interaction must not block the main thread waiting on full-res decode or Vision.
- Reuse CIContext and Metal device/pipeline objects, minimize per-frame allocations, avoid CPU RGBA roundtrips for every video frame.
- Decode one selected video at a time, release stale frame caches on selection changes, retain recipe metadata in memory/disk for all imported items.
- Exports may take longer than playback; progress is mandatory. Avoid unnecessary 5K→5K transforms when scale-down will be chosen.
- Verify 1h endurance testing for memory growth if practical; v1 minimum stress test is repeated open/close/scrub/adjust cycles without runaway memory growth.

## 9. Accessibility and shipping basics

- Native keyboard and VoiceOver labels for toolbars/controls, visible keyboard focus, contrast checked; don't rely on color alone for masks or selection.
- Respect macOS appearance controls while using an intentionally dark neutral editing workspace; external brand screens may use warm-white editorial surfaces.
- No hardcoded fonts, media paths, local secrets or API tokens. Do not bundle full user originals in publicly distributed source or App; fixtures go in gitignored `test_media/`.
- Include reproducible Xcode command-line build/test commands and minimal setup steps. Signing/notarization/App Store release is outside v1 acceptance; app must be runnable locally in a standard Xcode debug build.
