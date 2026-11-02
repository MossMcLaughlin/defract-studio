# Photo & Video Editor — Complete Agent Implementation Specification v1.1

Date: 2026-11-02. macOS-first local editor. This is a **standalone implementation specification**; no earlier chat history is required. Use the packaged folder when possible because it includes the approved UI mockup and sample fixtures. Read `AGENTS.md` first and follow the verification gates.

**Verified latest media:** `GX011247.MP4` is HEVC Main 10 (10-bit, `yuv420p10le`), Rec.709 **SDR** (not HDR), 5312 × 2988 coded, 29.97 fps, −90° display transform, and AAC stereo audio. `GX011247(1).MP4` is a byte-identical duplicate and omitted. The two earlier GoPro clips are HEVC Main 8-bit Rec.709 with opposite display rotations.

**Use:** Prefer the `photo_editor_agent_handoff_full_media_v1.1.zip` containing complete specs, five still photo fixtures, three original GoPro clips, and the UI reference image. Extract locally and use `START_CODEX.md`. A smaller ZIP without video is also supplied. If sharing only this Markdown, add the photo/video fixtures separately. Underwater color curve constants are starting hypotheses; actual Mac builds and full UI tests must be verified by the coding agent.

---


---

<!-- BEGIN AGENTS.md -->

# AGENTS.md — Binding Implementation Instructions

You are building a practical, local-first **native macOS photo and single-clip video editor**. Read every specification in `README.md` before coding. Implement with disciplined simplicity, objective self-verification, and a strong bias toward completed working features over elegant but untested abstractions.

## Priorities (in order)

1. Correct media interpretation, preview and export; originals untouched; no lost edit metadata.
2. Genuinely responsive shared photo/video color grading and required masks.
3. Agreed UX, easy/advanced behavior, output framing and non-destructive persistence.
4. Modest, idiomatic, maintainable Swift code and easily repeatable tests.
5. Polish; do not spend early work on unsupported features, elaborate branding or premature optimization.

## Mandatory engineering rules

- Target macOS 15+ Apple Silicon; Swift / SwiftUI / Core Image / AVFoundation / Vision / ImageIO / Metal where necessary. No third-party runtime packages without measured need. Use AppKit only for desktop-specific components/behaviors where SwiftUI is insufficient.
- Core edit models, color math, mask math and renderer must **not** import AppKit or depend on macOS window controls; keep them portable enough for a future iPhone app. Do not attempt an iOS app now.
- Prefer one Xcode app target plus one shared core module/package and a test target. Avoid an elaborate plugin architecture, DI container, architecture framework, speculative repositories, and redundant wrappers.
- One canonical edit recipe, renderer and export path. Photo and video share the same adjustment evaluation. For media-specific processing, use thin adapters.
- Rendered preview frames and caches are disposable; never save edited copies into originals, even temporarily. Write exports to temporary output and commit on success.
- Implement visible controls fully or hide them; no fake slider behavior, unsupported formats, placeholder export buttons or misleading “dehaze” labels.
- Make rendering parameter values deterministic. Easy curve updates change only their base contribution; manual Advanced changes are stored as delta; effective = base + delta. Store both terms and the effective values through serialization tests.
- Never use an automatic mask result as the only possible selection path. Preserve user brush correction and source-aligned mask data. No video subject mask.
- Use current SDK APIs: check Xcode availability, warnings and official documentation. **Do not call a macOS 26-only API unguarded when targeting macOS 15.** Check availability of `AVVideoComposition.init(applyingFiltersTo:applier:)` (introduced in the 26 SDK family); use a supported older composition API for macOS 15–25 when required, even if deprecated by the newest SDK. Keep the compatibility branch minimal and test actual preview/export behavior. Do not suppress necessary compatibility warnings dishonestly.
- Specifically verify `GX011247.MP4` (HEVC Main 10, 10-bit Rec.709 **SDR**) for correct decoded color, portrait orientation, adjusted preview/export and audio. Do not call this an HDR sample. Do not use raw, guessed color-space transforms. Honor metadata, sRGB/Rec.709 SDR output, orientation and permitted HDR tone mapping. If a file cannot be safely processed, explain the limitation rather than silently grading it wrong.
- Add small, relevant automated tests for state, curves, masks, geometry, file IO, undo and media output. Test with actual supplied fixtures. Every checkpoint builds cleanly before proceeding.
- Keep comments and documentation focused on **why** decisions were made. Avoid excessive generated scaffolding, files, comments, logging, and fallback branches.
- Never claim tests passed unless invoked and verified on the machine. If GUI or signing cannot be checked, label that explicitly.

## Workflow: one handoff, many internal checkpoints

Implement in the sequence in `IMPLEMENTATION_PLAN.md`. You may make independent routine engineering choices and fix failures without requiring human approval. At each checkpoint: compile; run focused tests; capture known limitations; commit or otherwise checkpoint a buildable state. If a platform limitation blocks a requirement, implement the simplest viable alternative without dropping the feature silently, and document the tradeoff. Prefer completion over stopping for nonessential decisions.

## Required final delivery

- Launchable Xcode project, reproducible build instructions and a clearly identified app entry point.
- Real functionality for all MVP requirements (subject ML best effort, with manual fallback always working).
- `README.md` for users, `DEV_NOTES.md` for maintainers, tests, and `VERIFICATION_REPORT.md` with exact build/test commands and outcomes, tested media, known issues, and any feature shortfall.
- A concise summary of directory layout and where to change color mappings, UI style tokens and export presets.
- No secrets, API keys, external service dependencies, external analytics or uploads.

## Definition of failure

A static SwiftUI mockup, successful compilation alone, a non-working export, a preview that does not match output, editing a duplicated source as if original, lost mask refinement on reopen, or ignored video rotation does **not** meet acceptance. Do not describe those as a finished MVP.


<!-- END AGENTS.md -->



---

<!-- BEGIN PRODUCT_MVP.md -->

# PRODUCT_MVP.md — Product and Scope

## Mission

Create a simple editor with selected Lightroom-like color controls for real-world photos and short single video clips, especially underwater GoPro/TG-7/iPhone media. The main goal is not one-click magic: it is reducing the time needed to perform repetitive underwater corrections while retaining exact manual control. No Lightroom catalog, DaVinci-style node graph, video timeline or cloud processing.

## Design principles

1. **Local-first:** Files open directly from disk; no uploads, accounts or external servers.
2. **Same mental model:** A shared set of color edits and preview for photos and video.
3. **Frictionless output:** One selected file exported at a time with three understandable quality presets and geometry controls.
4. **Minimal, maintainable code:** Native APIs and just enough abstractions for future changes.
5. **Verifiable correctness:** Real-file tests before the user performs fine-grained v2 visual calibration.

## In scope (must ship)

**Import, navigation, editing:** JPEG/PNG/HEIC images (as system decoder permits), MOV/MP4 with H.264 or HEVC as supported on target Mac; file list/import of several paths; one active media item at a time; file list easily hidden; large correct-aspect preview; Fit/zoom controls; before/after; undo/redo, reset, saved project edits.

**Advanced global adjustments:** Exposure, contrast, highlights, shadows, whites, blacks, temperature, tint, saturation, vibrance, and an eight-band HSL mixer with hue/saturation/luminance controls. No requirement to exactly match Lightroom's proprietary algorithms.

**Easy underwater adjustments:** Water Color, Color Recovery, Light, Visibility. Fixed, conservative mappings to the same Advanced parameters, as specified in `COLOR_ENGINE.md`. An ordinary-photo Easy mode is optional; Advanced remains available for all images and video.

**Photo masks:** Automatic foreground instance detection if Vision returns reasonable subjects, plus independent manual brush Add/Erase, brush size/feather, selection invert, radial and linear gradient masks; mask-local adjustment inspector uses the same Advanced parameter definitions. Multiple independent masks permitted. If ML fails, manual mask still usable. Persist each mask and brush corrections.

**Video masks:** Static linear and radial gradient masks with editable position, direction and feather; local Advanced color adjustments only. No object segmentation, person masks or tracking on video.

**Geometry:** Crop/straighten/rotate, source/original aspect ratio and presets 1:1, 4:5, 9:16, 16:9, custom orientation/position; fit/fill behavior in output. Video has simple start/end trim and playback/scrubbing, no multi-track timeline.

**Save/export:** Original file immutable; app-managed edit session metadata with saved effective state/history and source links; explicit export JPEG/PNG or MP4 (H.264/HEVC as available), Rec.709/sRGB SDR initially, audio preserved, export one at a time, progress, cancellation and recoverable failures; presets Instagram / General / Maximum Quality plus output folder choice.

## Explicit exclusions

No multi-clip video assembly, audio editing, automatic bulk rendering, large asset catalog, offline ML model training, remote AI processing, in-app LLM, video subject/object masking, motion tracking, panoramas, layers, sky replacement, face retouching, curves editor, Photoshop-grade edge tools, RAW-specific workflow, full manual camera log color transforms or true HDR export. Do not invent these for v1.

## Required user journeys

1. Import underwater JPEG; move Water Color and Recovery; open Advanced and see exact effective values; change cyan hue manually; return to Easy and move a slider; delta preserved; save metadata; reopen; export cropped 4:5 JPEG.
2. Select turtle in photo via automatic foreground detection; correct selection with feathered add/erase brush; adjust subject and inverted background independently; close/reopen and see same mask and grade; export same appearance.
3. Import high-resolution rotated GoPro portrait HEVC; preview grade in playback; apply vertical 9:16 crop; static gradient for brighter water; trim 1–2 seconds; export valid upright MP4 with matching audio and colors.
4. Import several shots; navigate thumbnails; edited state is retained automatically without rendering all files; export only explicitly chosen item.
5. Open ordinary landscape/portrait JPEG; use Advanced corrections and selectable horizontal/vertical crops; export to chosen directory with no silent overwrite.

## Release classification

- **Required v1:** All above items that are deterministic and platform-supported; manual mask fully functional. Color corrections need to be conservative and coherent but not professionally tuned on every underwater scene.
- **Best-effort v1:** Apple's automatic photo foreground selection. Vision may not correctly identify turtles, mola mola, reef fish; failure must not disable manual masks. If automatic detection cannot reliably identify an image, show an actionable message and enable brush.
- **Deferred v2:** Fine-tuning Easy curves, scene-specific reef/open-water/skin/sand presets, stronger dehaze, formal subjective grading evaluation, wider codec tests, expanded iPhone support.

## Quality bar

Small source tree, usable app window, no hidden data loss, no broken exports, meaningful visible effect from every offered control, and deterministic restores. Document non-goals honestly.


<!-- END PRODUCT_MVP.md -->



---

<!-- BEGIN UX_SPEC.md -->

# UX_SPEC.md — UI and Interaction Contract

## Approved direction

Treat `reference/UI_REFERENCE.png` as visual guidance. Native macOS dark editor, neutral charcoal central canvas, warm-white text, restrained gold actions, blue focus/active selections, Manrope for controls and Cormorant Garamond only for any occasional brand/title context. Do not reuse Watermark's logo. Working window title: “Photo & Video Editor.” Use existing/native controls where sensible. Do not embed custom font files in source-control unless legally distributable; respect installed fonts and use system fallbacks.

Color tokens (starting point): brand black `#0B0B0A`, warm white `#F6F2E9`, gold `#D0A037`, Pacific blue `#2D708F`, sand `#C7A66A`, stone `#71716C`. Functional editor surfaces: neutral `#141617` canvas, `#222526` panels, `#303434` borders; focus blue needs sufficient contrast for accessibility. Color management of displayed media **must never** inherit UI accent colors.

## Window anatomy

- Top toolbar, approximately 50 px: Import, left sidebar collapse, Undo, Redo, Before/After, Export. Keep title/content controls compact.
- Left file list, default ~120 px; collapsible to zero and persisted. Narrow thumbnails (not an image catalog), filenames short/truncated; keyboard arrow navigation allowed. If thumbnails are too costly/awkward, filenames with small optional thumbnails are acceptable. Selected item obvious.
- Center preview: takes **all remaining flexible width**; fitting crop/rotate and before/after must be visible. On narrow windows prioritize center by allowing inspector resizing and hiding file list; never display the photo under sliders.
- Right inspector: ~340 px default, adjustable ~300–420 px; contains `Global` and `Masks` tabs. Global has `Easy` and `Advanced`. For non-underwater images default Advanced; user can choose underwater Easy manually. Mask inspector exposes mask list + mask tools + all Advanced adjustment groups; no Easy inside masks.
- Photo: lower strip inside preview only for Fit/100%/zoom, dimensions, crop tool; no video scrubber. Video: lightweight play/pause, seek bar and in/out trim handles under preview; *not* a timeline or filmstrip.
- No permanent horizontal filmstrip; left file list serves as navigation. One file actively edited/exported at a time.

## Global edit interactions

- First use of underwater Easy: show 4 sliders, with value, labeled neutral/default and reset-to-neutral ability. No “auto enhance” button. Underwater mode remains a toggle of controls, not a separate set of hidden filters.
- Moving an Easy slider changes base contributions to Advanced parameters. Advanced displays **effective** values, not internal delta or misleading zero. Switching Easy↔Advanced alone never reprocesses to a different color grade or resets anything.
- Editing an Advanced parameter writes `manualDelta = userRequestedEffectiveValue - currentEasyBase`, without touching the Easy slider positions. Returning to Easy retains slider positions. Subsequent Easy changes recompute bases and preserve deltas. `Reset Easy` sets only its slider contribution to neutral; `Reset Manual` sets deltas to zero; `Reset All` confirms then clears global edits. One slider gesture = one undo action even if many parameters changed.
- When user first returns from Advanced with nonzero manual deltas, show an **unobtrusive once-per-install** explanation: “Manual refinements are preserved when you change Easy controls. For predictable results, start with Easy and finish with Advanced.” Thereafter show only discreet “Customized” info if desired; don't show modal on every tab switch.
- Advanced panel sections: `Light` (6 controls), `Color` (4), `Color Mixer` (8 swatches; Hue/Saturation/Luminance for selected hue). Color mixer must visually explain “Green → Aqua → Blue” hue movement; hue range available in both directions and labels are clear. Do not build a color wheel/node editor. Input can be slider plus numeric readout. Double-click label or small reset affordance returns an individual control to its easy-derived baseline (delta=0).
- Before/After compares current selected media with original. Prefer hold-to-view-original or toggle; optional split view only if trivial. Video before/after must not mute/lose audio or alter trim state.
- Undo/Redo in top bar and native shortcuts (`⌘Z`, `⇧⌘Z`). Slider drags commit one history entry on gesture end; brush stroke one history entry on pointer up; resets, crop and trim one transaction each. Redo invalidated by new edit.

## Mask editing

- Select `Masks`; show mask list with visibility, edit/rename/delete/invert. `Add mask` menu: `Select Subject (Photo)`, `Brush`, `Linear Gradient`, `Radial Gradient`. On a video omit subject and brush entirely.
- Photo `Select Subject` runs Apple Vision asynchronously with spinner/stop; render editable translucent alpha overlay. It may select the wrong thing; allow user to refine with brush (Add and Erase) or start manually without detection.
- Brush has size, feather and Add/Erase toggle, with intuitive on-canvas cursor, pan/zoom support, and actual brush preview; paint in coordinates corresponding to original orientation, not the current UI viewport.
- Gradients show draggable handles and feather/falloff. Orientation and geometry must remain stable under preview zoom, crop and export. Mask-local color inspector is visually the same Advanced controls, only applied inside alpha mask. Invert selection, mask enable/disable, and hide overlay all work without changing underlying edit values.
- Masks are not “layers” in the main UI. If two masks overlap, corrections process in saved order, deterministically. No blend modes required.
- Auto-segmentation failure explicitly says “No suitable subject found. Use Brush to select it manually.” Never erase an existing mask on detection failure.

## Crop, rotate and export

- Add a clearly visible `Crop & Rotate` action, accessible both via toolbar or geometry control near the preview. Crop overlay with draggable edges/corners; numeric aspect ratio via `Original`, `Free`, `1:1`, `4:5`, `9:16`, `16:9`; portrait/landscape orientation can be chosen regardless of source; rotate by ±90°, straighten by a small angle, and flip horizontally/vertically (if low-cost). Preserve edit geometry in source-relative coordinates and show exact final crop before export.
- An export dialog shows `Preset` (Instagram / General / Maximum Quality), `Aspect Ratio` / `Fit` or `Fill` / resolution, file format, name, folder and estimated output size when practical. Instagram offers Feed 4:5 and Reel/Story 9:16 choices; horizontal 16:9 remains available. Explicit selection of frame dimensions must be accompanied by a visual crop/padding indication.
- Preset **never** silently crops content. Default original geometry (and any explicit user crop) stays intact. If changing preset requires a new ratio, user sees crop/letterbox preview and chooses Fit or Fill. For Fit with a fixed aspect ratio, show neutral letterboxing/padding; Fill crops with repositioning. An `Original` export uses current manual crop, if any, at its own aspect ratio.
- Save/persist edit settings automatically without rendering. Export is a separate explicit action. Because preview caches are disposable and project edits are already persisted, **do not prompt on every file switch or cache eviction**. Warn when a file is intentionally removed from the project with unsaved recovery state, when deleting an edit recipe, or when replacing output. If autosave fails, warn and prevent silent loss. Restore edits on reopen.
- Exports are one at a time with progress/cancel, success affordance “Show in Finder,” and actionable failure message. Never silently overwrite an output. Default path `~/Pictures/<AppName>/Exports/` for photo and `~/Movies/<AppName>/Exports/` for video; remember user's folder.

## Empty, loading and error states

- Empty window: centered `Open Photos or Videos` plus drag-and-drop affordance, unobtrusive shortcuts/help.
- Loading: preview thumbnail and spinner, not frozen app; video controls disabled until media ready.
- Unsupported media / missing file: plain explanation and Relink, not silent blank canvas.
- When project reopened: restore last item and last used panel (Easy/Advanced and Global/Masks); ensure source URL/bookmark security is re-established where applicable.
- Accessibility: keyboard navigation, ≥44 px target preferred for touch-future design though mac can be denser, meaningful labels, text contrast, reduce-motion friendly transitions, no color-only status indication.

## UI acceptance

At a 1440×900 logical-point window, the narrow browser, large media preview, and right inspector all remain usable. The collapsed browser adds width to preview. Photo controls show no scrubber; video controls show scrubber and trim without a full editor timeline. Right-side controls do not change or obscure the image on merely switching panels.


<!-- END UX_SPEC.md -->



---

<!-- BEGIN COLOR_ENGINE.md -->

# COLOR_ENGINE.md — Parameters, Algorithms and Underwater Easy v0.1

## Core rule

There is **one actual set of color adjustments**. Easy slider coordinates contribute a deterministic `base` vector; Advanced edits contribute a `manualDelta` vector. The renderer and Advanced UI use `effective = clamp(base + manualDelta, parameterAllowedRange)`. The stored, unclamped delta remains intact to allow reversal of an Easy change; numeric Advanced controls show the **clamped rendered value**. A new Advanced target sets `manualDelta = requestedEffective - currentBase`. Switching tabs never changes results. Store Easy controls + manual deltas + masks; don't overwrite manual values on Easy movement.

All Easy parameters start at neutral. Each Easy component should derive from its absolute slider position, **not accumulate incremental floating-point changes**. Contribution vectors add together so overlapping edits remain predictable. Map formulas versioned as `underwaterMappingVersion: 1` in the saved recipe, permitting later recalibration/migration; saved project output must not suddenly change when a new mapping is installed (persist evaluated base or a versioned mapping implementation).

## Canonical Advanced controls

- **Light:** `Exposure` −3...+3 EV (0), `Contrast`, `Highlights`, `Shadows`, `Whites`, `Blacks` each −100...+100 (0).
- **Color:** `Temperature` (−100 cool / +100 warm), `Tint` (−100 green / +100 magenta), `Saturation`, `Vibrance` each −100...+100 (0).
- **HSL Color Mixer:** 8 overlapping hue bands: Red (0°), Orange (30°), Yellow (60°), Green (120°), Aqua (180°), Blue (240°), Purple (275°), Magenta (320°). Each has `Hue` (−100...+100 mapped to ±45° maximum), `Saturation` and `Luminance` (−100...+100). HSL selective effect uses smooth hue-region weights with wraparound, not hard cutoffs or arbitrary discrete colors. Design the mixer so raising Green Hue shifts green **toward aqua/blue**, raising Aqua Hue shifts aqua toward blue, and neighboring channels blend smoothly. Preserve meaningful hue responses at very low saturation; do not create severe banding. Use color chips and readable labels; no color wheel required.
- Numeric UI uses normalized integers for colors; Exposure may show two decimals. Actual algorithms need not match Adobe. Every active control must have a visible, monotone, reasonably standard effect and testable neutral=identity.
- Optional later: Clarity, sharpening, real dehaze, auto white balance, finer channels. **Don't render dead controls**; if a feature is not implemented, omit it rather than falsely exposing it.

## Standard processing model (implement once)

`Decode and orient original → honor profile/transfer → working-space conversion → global white balance/exposure → global tone (contrast/highlights/shadows/whites/blacks) → global HSL mixer + saturation/vibrance → global optional detail → each enabled mask's local edit transform composed through its alpha mask in saved order → crop/rotate → display/output transform.`

White balance should be chromatically sensible, ideally using known Core Image temperature/tint support rather than naive RGB channel multiplication; use per-channel adjustment with safeguards only if needed. Exposure should act in linear light. Tonal edits should preserve continuity and avoid hard clipping; implement highlights/shadows/whites/blacks using a well-documented, smooth tone operator or common Core Image tools, with 0=identity, signed adjustments, bounded gains and stable end values. Contrast is a pivoted S-curve rather than uniformly multiplying brightness. HSL is best performed in a perceptually suitable encoded representation, with conversion to/from the working space handled explicitly. Vibrance preferentially increases low-saturation colors and protects highly saturated colors/skin as practical. Do not perform per-color hue shifts using unfeathered, discontinuous bins.

Precise photographic look is **provisional** and should be tested against supplied media. Use concise implementation notes to document exact constants, order and GPU/render performance. Preview/export use identical algorithm version and effective values (only render resolution and output conversion differ). Avoid double-applying Easy corrections as an invisible overlay.

## Underwater Easy — precisely defined initial input space

Initial sliders, saved as integers:

1. **Water Color**: `−100 ... +100`, neutral `0`. **Asymmetric**: negative = “Deepen Blue / reduce excess cyan” (never deliberately add green); positive = “Remove Green” (warm/magenta balance, green→aqua, aqua→blue, restrained green desaturation and blue emphasis). UI labels at endpoints and a centered neutral tick. This is *not* Blue↔Green symmetric white balance.
2. **Color Recovery**: `0 ... 100`, neutral `0`, mild red/orange/yellow + vibrance/saturation recovery; preserve sand/skin where possible; don't amplify clipped/noisy red data excessively.
3. **Light**: `−100 ... +100`, neutral `0`, negative for darker, more subject-focused background; positive to brighten dark exposure while lifting shadows and protecting highlights.
4. **Visibility**: `0 ... 100`, neutral `0`, mild contrast/black-level adjustment; no promise to reverse scattering, no fake dehaze.

Each slider maps to **all named relevant Advanced controls**, not to a separate invisible effect. These *provisional*, deliberately conservative lookup knots are specified below; values are **Advanced UI units** except Exposure (EV). Omitted parameters = 0. Use piecewise-linear interpolation between knot values for v1; fit smooth monotone splines only after user-led color testing. This avoids an expensive/fragile curve-fitting system before we have sample target grades.

### Water Color curve — sample knots

| Easy value | Temp | Tint | Green Hue | Aqua Hue | Green Sat | Aqua Sat | Blue Sat | Blue Lum | Whites |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| −100 | 0 | 0 | 0 | +12 | 0 | −10 | +5 | −5 | 0 |
| −50 | 0 | 0 | 0 | +6 | 0 | −5 | +2 | −2 | 0 |
| 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| +50 | +7 | +7 | +25 | +15 | −10 | +2 | +4 | +1 | +2 |
| +100 | +14 | +14 | +50 | +30 | −22 | +4 | +8 | +2 | +4 |

At the positive end, a small Aqua Luminance increase (+0/+1/+2 at 0/+50/+100) may help but should be optional if testing causes washed-out blue water. Before adjusting Blue hue further, test whether Aqua→Blue and Green→Aqua already provide sufficient shift. Hue numbers are normalized mixer UI units (100 = 45° shift); these changes should be smooth across color-band boundaries.

### Color Recovery curve — sample knots

| Easy | Saturation | Vibrance | Red Sat | Orange Sat | Yellow Sat | Red Lum | Orange Lum | Yellow Lum | Green Lum | Aqua Lum | Blue Lum | Shadows |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 50 | +5 | +8 | +7 | +9 | +3 | −2 | +2 | +2 | +1 | +1 | −2 | +2 |
| 100 | +10 | +16 | +14 | +18 | +6 | −4 | +4 | +4 | +2 | +2 | −4 | +4 |

Why this shape: improve warm objects without over-warming every pixel. Reds may not contain usable signal at depth, so limit boost; warm object luminance is treated separately from the global tone. This is one balanced default; reef/open-water/people-and-sand scene profiles are a possible v2 improvement, **not an additional MVP slider**. If the actual scene has no red data, an Advanced refinement or mask is expected.

### Light curve — sample knots

| Easy | Exposure EV | Contrast | Highlights | Shadows | Whites | Blacks |
|---:|---:|---:|---:|---:|---:|---:|
| −100 | −0.80 | +5 | −8 | −20 | 0 | −10 |
| −50 | −0.35 | +2 | −4 | −8 | 0 | −4 |
| 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| +50 | +0.35 | +2 | −5 | +9 | +1 | 0 |
| +100 | +0.80 | +4 | −12 | +18 | +2 | 0 |

Negative end darkens an open-water background or washed-out scene without drastically changing WB. Positive end lifts shadows/exposure but restrains excessive sunlit highlights. A diver in the blue and a sun-facing shallow reef may still need manual/masked tuning. Users should judge brightness according to display and source quality, not a simulated depth value.

### Visibility curve — sample knots

| Easy | Contrast | Blacks | Highlights |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 50 | +6 | −4 | −2 |
| 100 | +12 | −8 | −4 |

This is effectively “clarity/contrast correction,” not physical visibility estimation or dehazing. No local frequency-based clarity implementation is required for v1. The fourth slider is retained because contrast/backscatter characteristics vary independently from water color and brightness. If it proves redundant in real testing, it may be simplified in v2.

## Correctness and behavior tests

- All neutral Easy sliders + zero manual deltas yield identity within agreed working-space tolerances; no unexpected exposure shifts.
- Example: Easy Water Color base Temp +10; Advanced user sets +15 ⇒ delta +5. User changes Easy such that base +15 ⇒ Advanced and rendered Temp +20. The Easy UI remains at the chosen input position. Same behavior for HSL and masked values.
- Two different Easy sliders changing the same parameter produce sum of contributions. Avoid cumulative rounding drift; use internal Float/Double precision and round **only when displaying**.
- Save/reopen returns **byte-identical serialized values** for slider positions, deltas, masks and mapping version. Undo/redo restores joint state per user gesture.
- Every HSL hue band wraps correctly across 360°, feathered transitions are smooth, with no sharp color contouring. No NaNs, infinity or negative-alpha corruption.
- Basic parameter extremes are bounded and reversible; same input+recipe outputs same pixels within GPU/codec tolerances. Preserve notes of current known differences.

## Iteration workflow for user calibration

Later, use actual underwater images to record: image type, starting settings, target manual grade, Easy-slider vector, visual acceptability and Advanced deltas. Revise lookup knots or add scene profiles only based on repeatable observed patterns. **Do not build a trained prediction model, image classifier or auto-white-balance system for v1.**


<!-- END COLOR_ENGINE.md -->



---

<!-- BEGIN ARCHITECTURE.md -->

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


<!-- END ARCHITECTURE.md -->



---

<!-- BEGIN MEDIA_AND_TESTS.md -->

# MEDIA_AND_TESTS.md — Uploaded Fixtures, Validation and Acceptance

**Grounding:** Metadata below was inspected in the preparation environment using Pillow/ffprobe. Filename and codec interpretations are test annotations, not assertions about quality. **Three** GoPro video fixtures have now been inspected with `ffprobe` (2026-11-02). `GX011247.MP4` is verified **HEVC Main 10, 10-bit SDR Rec.709**, not HDR. The other two are HEVC Main 8-bit Rec.709. The second uploaded filename `GX011247(1).MP4` has an identical SHA-256 checksum; include only `GX011247.MP4` in fixtures.

## 1. Source fixture manifest

`test_media/` is a directory the coding agent should populate with the user's originals. The lightweight ZIP bundles five still-image samples under `test_media/photos/` but intentionally excludes the large MP4 originals. The full-media ZIP includes **all three verified GoPro clips**, including `GX011247.MP4`, under `test_media/videos/`. For the light version, place the videos there manually using the original names. Never modify test originals; store exports in `test_outputs/` (gitignored).

| File | Available format / pixel size | Primary test | Expected behavior |
|---|---|---|---|
| `IMG_3635.jpeg` | JPEG, 1536×2048 | Non-underwater ordinary photo, bright area and shadows | Works in Advanced; standard presets, correct upright export |
| `P7310233.JPG` | JPEG, 1536×2048 | Deep blue diver with high cast | Easy asymmetric blue corrections + mask fallback; no invented reds |
| `P8110319.JPG` | JPEG, 1536×2048 | Deep blue mola mola | Foreground Vision feasibility and brush fallback; strong blue scene |
| `B663700C-50E6-4C26-B95F-25C7E5F271E9.JPG` | JPEG, 1792×2048 | Divers/people in blue water | Subject detection, brush feather, skin/suit/water tradeoff |
| `image.png` | PNG RGBA, 638×1130 | Reef and fish portrait | Preserve portrait aspect and alpha behavior; export horizontal/vertical choices |
| `GX011123.MP4` | HEVC Main, 5312×2988 coded, 29.97fps, Rec.709, 8-bit; display rotation **+90°** | Portrait GoPro clip, audio, upright import and export | Display must obey transform, not be wrongly landscape or cropped |
| `GX011176.MP4` | HEVC Main, 5312×2988 coded, 29.97fps, Rec.709, 8-bit; display rotation **−90°** | Opposite portrait orientation, audio, edit/trim/export | Vertical output must be correct even though encoded dimensions are landscape |
| `GX011247.MP4` | **HEVC Main 10, 10-bit** (`yuv420p10le`), 5312×2988 coded, 30000/1001 fps (29.97), **SDR Rec.709** (primaries/transfer/matrix `bt709`), full-range (`pc`), display rotation **−90°**, AAC stereo 48 kHz; duration ~3.470 s | Verify genuine 10-bit decoding, neutral/graded preview vs output, upright portrait playback/export, trim and audio | **Do not claim HDR** for this fixture; maintain suitable working precision and intentional Rec.709 SDR output |

Photo fixture files may have been resized/re-encoded by upload; absent original EXIF camera model **must not** be used to infer color transform. Some JPEGs contain ICC profiles; respect them. For precise TG-7/iPhone metadata, request full originals in later calibration rather than assuming the small uploaded copies include it.

### Inspect on the development Mac

Use `mdls`, `sips`, `ffprobe` if available, or AVFoundation/ImageIO metadata; **ffprobe is a QA tool only and not a runtime dependency**. Example commands where installed:

```bash
ffprobe -v error -show_entries stream=index,codec_name,profile,pix_fmt,width,height,avg_frame_rate,color_primaries,color_transfer,color_space:stream_side_data=rotation -of json test_media/videos/GX011123.MP4
```

A 10-bit claim needs `p010le`, `yuv420p10le`, HEVC `Main 10`, a sample-bit-depth marker, or reliable Apple track/format metadata. **HEVC codec alone does not imply 10-bit**. SDR 10-bit and HDR are separate questions.

## 2. Essential automated tests — no manual color evaluation needed

### Color and state (`unit`)

- Neutral Easy + zero Advanced + masks off renders identity (allow documented conversion rounding).
- Easy `base + delta` example across mode switches and save/reload, including HSL values and simultaneous overlapping Easy contributions.
- Underwater LUT knot/interpolation tests at negative/neutral/positive Water Color, full limits, deterministic versioning and no accumulation drift after repeated drags.
- Undo/redo grouping (single Easy slider drag, single brush stroke, reset, crop/trim transaction), redo invalidation on later edit, saved/reopened history.
- Changing preview resolution does not change underlying effective parameters. Switching tabs is no-op for render state.
- HSL hue wrap, near-gray pixels, contiguous band interpolation, absence of discontinuities and NaN/Inf. Color adjustments have correct sign and neutral effect.

### Masks and geometry (`unit + integration`)

- Linear and radial alpha at edges, inversion, size/feather, geometry normalized coordinates and rotations; mask is crisp enough at export resolution.
- Photo manual brush add/erase persists; exact existing strokes + automatic mask cached on reopen; auto failure doesn't erase manual strokes.
- Mask local edits leave unselected pixels effectively unchanged (within conversion tolerance) and do not repeat the global grade.
- Crop: `Original`, `1:1`, `4:5`, `9:16`, `16:9`, horizontal-to-vertical and vice versa, fill reposition, fit letterboxing. No accidental stretching.
- Video masks explicitly *lack* subject and brush actions; static gradient appears consistently across different frames.

### File/persistence (`integration`)

- Import all supported photos and videos; unchanged original checksums after preview, save, undo, export.
- Close/reopen item restores Easy positions, effective Advanced values, masks/brushes, crop and undo. File cache deletion is harmless.
- Relink missing/renamed source; corrupt recipe produces actionable recovery, not crash or silent data loss.
- Autosave atomicity and failure surfaced. Export not required to preserve edits.

### Export and media (`integration`)

- Photo export: sRGB metadata, specified output dimensions and aspect, no unintended rotation, valid JPEG/PNG.
- Video export: valid MP4, expected display orientation, trim duration tolerance approx one frame plus encoder rounding, audio if source had it, plausible output frame count and color tags.
- All three GoPro fixtures render upright, including the **opposing +90°/−90°** pair (`GX011123`, `GX011176`). `GX011247` is another −90° portrait file encoded as landscape dimensions. At least one portrait 9:16 output from each rotation direction is checked in a separate player.
- `GX011247.MP4` must decode and accept non-neutral color adjustments as 10-bit HEVC Main 10 SDR; compare preview and exported frame within documented visual/color tolerances and verify audio. Downconversion to an 8-bit SDR export is acceptable **only if explicit and deliberate**, not a misidentified 8-bit source.
- Preview/export comparison: render representative frame at source display resolution or downsample output and compare corrected pixels within an empirically documented tolerance. Lossy H.264 frame comparison requires perceptual threshold rather than pixel identity.
- Export failure/cancel leaves original intact and no misleading complete output; repeat works. Existing destination requires explicit overwrite confirmation.

## 3. Short human smoke test after checkpoints

1. Open P8110319.JPG; set Water Color +50, Color Recovery +40, Light +20; inspect Advanced effective values; set Aqua hue manually; return to Easy and adjust Water Color; verify manual offset remains; save/reopen.
2. Add photo gradient and brush mask to diver or mola; adjust mask exposure and hue; export 4:5 image; verify correct edges and persisted strokes after reopen.
3. Open GX011123.MP4; play, apply water correction, trim middle section, choose 9:16 Fit and Fill alternatives, export with audio, check upright in QuickTime; repeat orientation test on GX011176.MP4.
4. Open **GX011247.MP4 (HEVC Main 10, 10-bit SDR)**; play and edit without washed-out/clipped colors, export upright Rec.709 SDR preserving audio, and inspect output metadata. Avoid falsely labeling the source HDR.
5. Open IMG_3635.jpeg; use only Advanced; export General and verify usual terrestrial image isn't automatically changed by underwater settings.
6. Quit with unexported edits: prompt Export / Close & Keep Edits / Cancel; verify edits return if Keep Edits chosen.

## 4. Definition-of-done matrix

| Gate | Requirement | How verified |
|---|---|---|
| A | Mac app compiles and opens without warnings/errors treated as fatal | `xcodebuild` and launch screenshot |
| B | Every visible slider produces usable effect and can undo/reset | test recipe + UI smoke |
| C | Color mixer green→aqua→blue interpolation and 8-band H/S/L work | unit plots/pixel tests + manual check |
| D | Subject mask best-effort; brush always functional | image fixtures + strokes reload |
| E | Static video gradients; no video subject masking | video fixtures + UI assertions |
| F | 3 GoPro videos preview/export upright with audio, including a verified Main 10 10-bit SDR fixture and both rotation signs | AVAsset/QuickTime + probe inspection |
| G | Original never mutated; recipe/history restored | checksum and reload tests |
| H | Outputs correct sRGB/Rec.709, aspect/resolution, failures handled | export metadata + preview comparisons |
| I | Self-contained local app: no network/account dependency | code/dependency review and offline smoke |
| J | Clean source tree, reproducible Xcode build, test report | deliverable audit |

## 5. User-led v2 calibration (not a v1 blocker)

After the MVP: for each photo record environment (blue/green, depth/light, subject reef/sand/people), Easy slider positions, preferred Advanced deltas, and subjective result. Measure editing time, number of manual controls touched, and failure modes. Fit/retune the knots in `COLOR_ENGINE.md` only when there is a consistent pattern. Do not train a proprietary model or claim magical restoration without evidence.

## 6. Files, licensing, privacy

All user fixtures remain private local test data; add `test_media/` and `test_outputs/` to `.gitignore`; don't commit these to a public repo or include originals in the published app. Use the provided `reference/UI_REFERENCE.png` only as a UI direction reference; it is not an image with a real implemented editor. Images of real people should not be re-used in marketing without consent.


<!-- END MEDIA_AND_TESTS.md -->



---

<!-- BEGIN IMPLEMENTATION_PLAN.md -->

# IMPLEMENTATION_PLAN.md — One Agent Handoff, Buildable Checkpoints

## General operating instruction

Implement end-to-end from this package rather than repeatedly asking the user for routine engineering decisions. Make reasonable local decisions within specified scope; record choices in `DEV_NOTES.md`. **Do not** postpone all verification until after coding. Incremental checks are part of the agent's job. Never claim a macOS build or UI acceptance was completed unless it actually ran on macOS with Xcode. No detached/unreviewable generation burst.

If tool environment lacks macOS / Xcode, stop short of claiming a working Mac app, provide the source and exact build commands with limitations, and hand the project to a Mac-based agent for the real verification gate. A Linux-only Swift compile is not an adequate AVFoundation test.

## Gate 0 — Platform and risky API proof (before large UI)

1. Detect `xcodebuild -version`, `sw_vers`, Apple Silicon chip/GPU, installed SDKs; record specifics.
2. Create launchable native app, one shared Core model/renderer. Import a test JPEG and HEVC MP4; report image ICC/color orientation and video codec, transform, fps and transfer. Also inspect the supplied `GX011247.MP4` and confirm its HEVC Main 10 / Rec.709 SDR metadata and correct decoding (not HDR).
3. Render *the same* trivial exposure + saturation operator on a still and through live playback of video; export both. Verify upright portrait output and audio in one file.
4. Confirm the **deployment-compatible** API for video Core Image filtering: use an API available on macOS 15; the `AVVideoComposition.init(applyingFiltersTo:applier:)` API may only be available in macOS 26 SDK-era deployments, so do not build the MVP solely around it. Test photo and video preview parity, keyboard responsiveness and exporter constraints. Investigate Reader/Writer only if standard export cannot satisfy crop+filter+audio.
5. Trial Vision foreground instance segmentation on P8110319.JPG and diver photo; save mask; report failure modes. Manual brush path must remain regardless of ML success.

**Gate pass:** documented feasibility results; build runs; one photo and one portrait HEVC edit and export verified. If not, resolve and annotate exact technical blocker before UI expansion.

## Gate 1 — Functional editing core + global UX

- Implement the complete type-safe recipe/parameter schema, filesystem persistence, source relinking, bounded undo system, preview cache and file list.
- Implement shared color engine parameters (not just UI placeholders). Build HSL controls with 8-band H/S/L mixer and signed hue semantics, use neutral identity and verify pixel-level tests.
- Implement four Easy sliders via the v0.1 piecewise-linear knot tables and base/delta state; ensure only effective Advanced values render.
- Implement approved dark native workspace, collapsible ~120px left files, preview, right Global / Easy / Advanced; standard image photo/video playback; Before/After; shortcuts.
- Implement single photo export and verify output metadata/crop. Resizing and the large preview must behave.

**Gate pass:** files import, edits visibly work with predictable real effects, Easy/Advanced state exact, photo/video preview works, undo and reload pass, crop v1 usable. UI screenshot captured for visual comparison to reference.

## Gate 2 — Masks + geometry + videos

- Implement photo brush (Add/Erase, feather, size), manual mask storage, gradients/radial, inversion and ordered independent local adjustments.
- Integrate Vision as an asynchronous optional Select Subject; retain matte and strokes. Mask overlay controls must remain clear without Photoshop-style tooling.
- Implement video **static gradients only** and verify in playback/export; no video subject mask, brush, motion tracking or keyframes.
- Finish accurate crop, 90° rotate, straighten where feasible, aspect presets including landscape→portrait/portrait→landscape and Fit/Fill preview parity.
- Finish video in/out trim, playback, audio retention and export for H.264/HEVC as supported; test both GoPro 90°/−90° fixtures, plus GX011247.MP4 (10-bit SDR) with actual edits and export.

**Gate pass:** photo subject/brush/gradient workflows can save and reopen; video gradient/trim/portrait export are genuinely correct; no original mutation.

## Gate 3 — Polish, reliability, app handoff

- Make Instagram / General / Maximum Quality export presets simple; implement destination chooser, filename validation, defaults, progress/cancel, temp-output cleanup, overwrite confirmation, QuickTime verification, errors/retry.
- Make closing unexported changes prompt (Export / Close & Keep Edits / Cancel), while file switching and preview cache eviction are seamless due to autosave.
- Complete accessibility labels, minor responsiveness, loading/no-file errors and relinking; add small native help for manual deltas.
- Write `README.md`, `DEV_NOTES.md` (file structure and architecture tradeoffs), `VERIFICATION_REPORT.md` (commands, environment, all features tested, actual errors/limitations), and retain `AGENTS.md`.
- At minimum test: deep blue photo, diver foreground selection with brush fallback, reef photo, ordinary non-underwater photo, both opposing portrait-rotation GoPro clips, and **verified 10-bit SDR GX011247.MP4**. Confirm Main 10 decoding, preview/export fidelity, orientation, and stereo audio; do not misrepresent the clip as HDR.

**Gate pass:** clean reproducible build and tests with real files, objective media-output validation, source tree small and coherent, no dead visible controls, a runnable Xcode project and known limitations honestly documented.

## Tests and artifacts at every checkpoint

1. Run `xcodebuild` build and tests (show exact `-scheme`/`-destination`). Fix compiler errors and appropriate warnings before moving on.
2. Run Swift unit tests and real-media integration tests on available fixtures.
3. Open app/collect screenshot where possible, plus exported example frames/video metadata to review preview parity.
4. Inspect Git diff; remove obsolete scaffolding, unused files, fake buttons; commit a working milestone if repo permissions permit.
5. Update `VERIFICATION_REPORT.md` with result: PASSED, FAILED, or NOT TESTED (not "probably fine").

Example commands (replace scheme with actual):

```bash
xcodebuild -list -project EditorApp.xcodeproj
xcodebuild -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' build
xcodebuild -project EditorApp.xcodeproj -scheme EditorApp -destination 'platform=macOS' test
```

For first-run signing, prefer a local Debug build with automatic local signing or `CODE_SIGNING_ALLOWED=NO` as appropriate to the developer machine. Do not require paid Apple Developer enrollment just to test locally.

## Repository and maintenance rules

- Keep main editor logic separate from state/UI and file/export adapters; target approximately **one straightforward implementation per capability**.
- Resist excessive generic filtering APIs, runtime reflection, an entire plugin framework, huge `ViewModel` classes, or hidden conditional fallbacks. Factor a helper only when it removes real duplication or supports required tests.
- Avoid Swift package dependencies beyond Apple frameworks unless indispensable and recorded with reasons and license.
- No speculative app store/iOS work; preserve portability of the core by not importing AppKit there.
- Use descriptive enums/types, not magic strings. Keep public API surface small. Document why color operator formulas/constants exist; no broad generated comment floods.
- Do not claim one-shot means no checkpoints. The desired outcome is low-supervision delivery that passes tests, not monolithic unchecked code generation.
- Do not invent features beyond v1; a 'nice to have' may be proposed in `FUTURE.md` without implementing it.

## Definition of done (release decision)

A demo GUI with sliders is not done. All required features must work in a native Mac application, render actual media, persist edits, preserve originals, export correct geometry and audio and pass the mandatory checks listed in `MEDIA_AND_TESTS.md`. The full feature list may be considered complete only when **all required gates pass**, with optional automated subject recognition accurately described as best effort. If a mandatory feature is blocked, give a failure report and a proposed simple corrective action, not a false success claim.


<!-- END IMPLEMENTATION_PLAN.md -->



---

<!-- BEGIN TEST_MEDIA_SETUP.md -->

# TEST_MEDIA_SETUP.md — How to Attach the User's Media

The **lightweight** specification ZIP contains the five photo fixtures but **not** the GoPro MP4 clips. The **full-media** ZIP contains **all three** MP4 videos already in the paths below. If using the lightweight ZIP, copy the videos there before video integration tests. This file is descriptive; an agent should not download from private links or guess paths.

```text
test_media/
  photos/
    IMG_3635.jpeg
    P7310233.JPG
    P8110319.JPG
    B663700C-50E6-4C26-B95F-25C7E5F271E9.JPG
    image.png
  videos/
    GX011123.MP4
    GX011176.MP4
    GX011247.MP4              # VERIFIED 10-bit HEVC Main 10 / Rec.709 SDR
```

The 10-bit file has already been verified: HEVC Main 10, 5312×2988, `yuv420p10le`, 29.97fps, Rec.709 SDR, −90° rotation, AAC stereo. Its duplicate upload (`GX011247(1).MP4`) is byte-for-byte identical and is not needed. The video originals are already included in the **full-media** ZIP; with the smaller archive, supply them locally.

If other 10-bit or HDR videos are added, inspect their exact codec/bit depth/primaries/transfer/orientation before describing them. An SDR 10-bit sample does **not** validate HDR support.


<!-- END TEST_MEDIA_SETUP.md -->



---

<!-- BEGIN PRIVACY_AND_SCOPE.md -->

# PRIVACY_AND_SCOPE.md

The attached sample photos/videos are user-provided test materials. They may contain identifiable people, locations and metadata. Keep them on the development machine, do not upload to any online service, do not publish them in a public GitHub repo or release bundle, and do not use them for public promotional screenshots without explicit user approval. The app must work offline and must not add telemetry, third-party analytics, or remote error reporting. The approved UI reference is a generated concept, not a real app screenshot.

The handoff defines the macOS MVP only. Future iPhone app packaging and distribution, App Store compliance, signing/notarization, RAW files, HDR mastering, automatic video subject tracking and full video timelines are outside the current build. Maintain a platform-independent core to make a later iPhone UI economical.


<!-- END PRIVACY_AND_SCOPE.md -->



---

<!-- BEGIN VERIFICATION_TEMPLATE.md -->

# VERIFICATION_REPORT.md — Agent Output Template

**Never prepopulate untested items as PASS.** Fill this in while building on the Mac.

- Date, macOS version, Xcode version, GPU/CPU, signing mode:
- App target, scheme, build command and result (PASS / FAIL / NOT TESTED):
- Swift unit tests command and result, tests count and any failing names:
- Fixture metadata and availability (photos, all three GoPros; GX011247 verified 10-bit Main 10 Rec.709 SDR):
- Validity of photo render/export, sRGB and crop dimensions:
- Video preview/export, frame dimensions, transforms, duration and audio:
- Color-management checks and HDR/10-bit policy:
- Masks (manual, Vision best effort, static video), persist/reload:
- Easy base + Advanced delta, save/reopen, history:
- Export cancellation/overwrite/failure handling:
- UI screenshot or screen recording paths showing implemented functionality:
- Known deviations, reproducible failures, blocked functions, and repair plan:
- Final result: FULLY VERIFIED / PARTIALLY VERIFIED / BLOCKED (explain).


<!-- END VERIFICATION_TEMPLATE.md -->



---

<!-- BEGIN REFERENCES.md -->

# REFERENCES.md — API References and Design Source Notes

External references are development pointers. **Check actual installed SDK signatures and availability at implementation time**. Where docs change, prefer current official SDK types, compilation and Apple guidance over this dated example.

## Apple platforms and processing

- [AVVideoComposition.init(applyingFiltersTo:applier:)](https://developer.apple.com/documentation/avfoundation/avvideocomposition/init%28applyingfiltersto%3Aapplier%3A%29) — newer async Core Image video composition initializer. **Availability warning:** part of the macOS/iOS 26 SDK-era additions; do not use unguarded on the macOS 15 deployment target.
- [AVVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:completionHandler:)](https://developer.apple.com/documentation/avfoundation/avvideocomposition/videocomposition%28with%3Aapplyingcifilterswithhandler%3Acompletionhandler%3A%29) — macOS 15-compatible candidate when targeting pre-26; validate against installed SDK.
- [AVCIImageFilteringResult](https://developer.apple.com/documentation/avfoundation/avciimagefilteringresult) — result image and CIContext for async composition.
- [AVAssetExportSession.export(to:as:isolation:)](https://developer.apple.com/documentation/AVFoundation/AVAssetExportSession/export%28to%3Aas%3Aisolation%3A%29) — modern async video export, supported file types and cancellation/progress considerations.
- [Core Image workingColorSpace](https://developer.apple.com/documentation/coreimage/cicontextoption/workingcolorspace) — explicit working space and managed input/output conversions.
- [Foreground instance mask request](https://developer.apple.com/documentation/vision/generateforegroundinstancemaskrequest) — category-independent prominent subject segmentation; validate on underwater wildlife rather than assuming successful output.
- [Security-scoped NSURL bookmarks](https://developer.apple.com/documentation/Foundation/NSURL) — persistent user-authorized file access in macOS sandbox.
- [App-scope security bookmarks](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access?language=objc) — entitlement/security-scope considerations.

## Product/styling background

- `reference/FOUNDATION_v0.1.md`: earlier agreed product goals, initial architecture/roadmap. Background only; current package resolves more recent decisions.
- `reference/STYLE_GUIDE_v0.1.md`: adaptation of the user's Watermark visual identity to neutral macOS editor; preserve primary palette/type, use neutral editing surfaces.
- `reference/UI_REFERENCE.png`: approved general photo workspace proportion and appearance. A static mockup, not a screenshot of a functioning app or a source asset.

## Contract precedence

If docs conflict, use this order: `AGENTS.md` and user's **latest explicit requirements** > `PRODUCT_MVP.md` > `UX_SPEC.md` > `COLOR_ENGINE.md` > `ARCHITECTURE.md` > `MEDIA_AND_TESTS.md` > `IMPLEMENTATION_PLAN.md` > `reference/` background. Within a single feature, prefer a more specific contract over a generic prior phrase. Do not silently resolve consequential uncertainty by dropping functionality.


<!-- END REFERENCES.md -->



---

<!-- BEGIN START_CODEX.md -->

# START_CODEX.md — Efficient first build on your Mac

**Recommended environment:** Use the local Codex desktop app or Codex CLI, opened at this extracted folder on an Apple Silicon Mac with Xcode installed. Prefer local over cloud for the initial build so the agent can run `xcodebuild`, launch the native UI, inspect media, and verify actual exports. Sign in with your ChatGPT account rather than an API key when you intend to use included subscription usage. The agent does not need the prior ChatGPT conversation: all requirements are in this package.

## Paste this as the first Codex task

> Build the native macOS Photo & Video Editor MVP described in this repository. Read `AGENTS.md` and `README.md` first, then consult their referenced specification files as needed. Use the supplied test media locally, including verified 10-bit SDR `GX011247.MP4`. Implement end-to-end through `IMPLEMENTATION_PLAN.md` gates, keeping each gate buildable and verifying tests and real exports before continuing. Prefer minimal maintainable Swift and native frameworks; avoid unnecessary dependencies and features. Keep private fixture media out of Git. Maintain `VERIFICATION_REPORT.md` with actual commands/results and create concise commits at successful gates. Do not claim success on untested UI/video workflows; disclose blockers accurately. Proceed without routine confirmations, but request approval before risky/destructive operations.

## Avoid wasted usage

- Begin with **one agent** and the normal/default or GPT-6.1 Sol setting available to your account. No parallel autonomous subagents unless a test proves a need.
- Do not paste every document into the initial prompt: the agent can read files locally when it needs them.
- Let builds, media probing and automated tests provide concrete feedback; avoid repeated long speculative design responses.
- Maintain small checkpoint commits and a short `VERIFICATION_REPORT.md` so you can resume from disk without restating the entire project.
- If the build stops due to usage or SDK issues, resume the same local repository and ask for the **next failing checkpoint**, not an entirely new project.
- Only escalate to a higher-cost or higher-reasoning model for specific difficult debugging or architecture failures.

## Before running the task

Check Xcode can launch and `xcodebuild -version` works, then extract **the full-media ZIP** into a normal development directory. Keep all sample files in `test_media/` (gitignored). The user-provided photo/video assets may contain people and location metadata; they are for local tests only, not for GitHub or public demo collateral.

When the agent completes a gate, review the checkpoint summary. The initial human verification can be brief: open the app, try a photo grade and a video export, and send specific issues back to Codex for repair.


<!-- END START_CODEX.md -->
