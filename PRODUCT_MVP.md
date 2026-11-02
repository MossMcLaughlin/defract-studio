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
