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
