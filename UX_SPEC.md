# UX_SPEC.md — UI and Interaction Contract

## Approved direction

Treat `reference/UI_REFERENCE.png` as visual guidance. Native macOS dark editor, neutral charcoal central canvas, warm-white text, restrained gold actions, blue focus/active selections, Manrope for controls and Cormorant Garamond only for any occasional brand/title context. Do not reuse Watermark's logo. Working window title: “Defract Studio”; the target and bundle name remain `EditorApp`. Use existing/native controls where sensible. Do not embed custom font files in source-control unless legally distributable; respect installed fonts and use system fallbacks.

Color tokens (starting point): brand black `#0B0B0A`, warm white `#F6F2E9`, gold `#D0A037`, Pacific blue `#2D708F`, sand `#C7A66A`, stone `#71716C`. The current editor uses near-black toolbar and side panels, muted sand for slider fills and reset accents, and a dark Export button in the same family as the toolbar controls. Focus blue needs sufficient contrast for accessibility. Color management of displayed media **must never** inherit UI accent colors.

## Window anatomy

- Top toolbar, approximately 50 px: Undo, Redo, Before/After, Crop & Rotate, Export. When the sidebar is collapsed, show a small **Show Files** control at top left. Keep title/content controls compact.
- Left file list, default ~128 px; collapsible to zero and persisted. Put **Import** and **Hide Files** at its top. Use small lazily loaded photo/video thumbnails and truncated filenames; selected item remains obvious. Do not add a bottom filmstrip.
- Center preview: takes **all remaining flexible width**; fitting crop/rotate and before/after must be visible. On narrow windows prioritize center by allowing inspector resizing and hiding file list; never display the photo under sliders.
- Right inspector: ~340 px fixed width in the current implementation; contains `Global` and `Masks` tabs with a gold active underline. Global has `Easy` and `Advanced` in a muted Pacific-blue segmented row. For non-underwater images default Advanced; user can choose underwater Easy manually. Mask inspector exposes mask list + mask tools + all Advanced adjustment groups; no Easy inside masks. Reserve a trailing gutter so the visible scroll indicator does not cover values or reset buttons.
- Photo: lower strip inside preview for Fit and Fit-relative zoom; wheel over preview zooms near the pointer and dragging pans within bounds when zoomed. Brush and on-canvas handles take precedence over panning. Video: lightweight play/pause, seek bar and in/out trim controls under preview; *not* a timeline or filmstrip.
- No permanent horizontal filmstrip; left file list serves as navigation. One file actively edited/exported at a time.

## Global edit interactions

- Underwater Easy shows four sand-accented sliders with live values, short helper descriptions, contextual info help, and a bottom **Reset Underwater Easy** action. Put **Deepen Blue** and **Remove Green** directly below the Water Color slider as its left and right endpoint labels. Zero-centered controls fill from their midpoint; minimum-based controls fill from the left. No “auto enhance” button. Underwater mode remains a toggle of controls, not a separate set of hidden filters.
- Moving an Easy slider changes base contributions to Advanced parameters. Advanced displays **effective** values, not internal delta or misleading zero. Switching Easy↔Advanced alone never reprocesses to a different color grade or resets anything.
- Editing an Advanced parameter writes `manualDelta = userRequestedEffectiveValue - currentEasyBase`, without touching the Easy slider positions. Returning to Easy retains slider positions. Subsequent Easy changes recompute bases and preserve deltas. `Reset Easy` sets only its slider contribution to neutral; `Reset Manual` sets deltas to zero; `Reset All` confirms then clears global edits. One slider gesture = one undo action even if many parameters changed.
- When user first returns from Advanced with nonzero manual deltas, show an **unobtrusive once-per-install** explanation: “Manual refinements are preserved when you change Easy controls. For predictable results, start with Easy and finish with Advanced.” Thereafter show only discreet “Customized” info if desired; don't show modal on every tab switch.
- Advanced panel sections: `Light` (6 controls), `Color` (4), `Color Mixer` (one horizontal row of Red, Orange, Yellow, Green, Aqua, Blue, Purple, Magenta swatches; Hue/Saturation/Luminance for the selected hue). The selected swatch has a non-color indicator. The Hue slider track itself shows adjacent hue colors, without a duplicate guide beneath it; the math remains unchanged. Zero-centered tonal and color controls fill outward from their midpoint. Input can be slider plus numeric readout. Small header reset icons reset only their section's manual deltas, preserving Easy bases. The mixer section reset covers all eight bands. Double-clicking an individual label may return only that control to its Easy-derived baseline.
- Before/After compares current selected media with original. Prefer hold-to-view-original or toggle; optional split view only if trivial. Video before/after must not mute/lose audio or alter trim state.
- Undo/Redo in top bar and native shortcuts (`⌘Z`, `⇧⌘Z`). Slider drags commit one history entry on gesture end; brush stroke one history entry on pointer up; resets, crop and trim one transaction each. Redo invalidated by new edit.

## Mask editing

- Select `Masks`; show mask list with visibility, edit/rename/delete/invert. **Create Inverted Mask** copies the current editable selection and refinements to a new independent mask with the opposite alpha and neutral local adjustments. The original remains unchanged. `Add mask` menu: `Select Subject (Photo)`, `Brush`, `Linear Gradient`, `Radial Gradient`. On a video omit subject and brush entirely.
- Photo `Select Subject` runs Apple Vision asynchronously with spinner/stop; render editable translucent alpha overlay. It may select the wrong thing; allow user to refine with brush (Add and Erase) or start manually without detection.
- Brush has size, feather and Add/Erase toggle, with intuitive on-canvas cursor, pan/zoom support, and actual brush preview; paint in coordinates corresponding to original orientation, not the current UI viewport.
- Gradients show draggable handles and feather/falloff. Radial ellipses have a visible Feather control and a rotation slider limited to ±90°; older saved equivalent angles remain readable. Delete Mask sits beside the selected mask name and remains undoable. Orientation and geometry must remain stable under preview zoom, crop and export. Mask-local color inspector uses the same Advanced controls, only applied inside alpha mask, with scoped section resets. The stronger pink mask-selection tint is off by default; with it hidden, switching Global/Masks must display identical graded pixels. Invert selection and mask enable/disable work without changing underlying edit values.
- Masks are not “layers” in the main UI. If two masks overlap, corrections process in saved order, deterministically. No blend modes required.
- Auto-segmentation failure explicitly says “No suitable subject found. Use Brush to select it manually.” Never erase an existing mask on detection failure.

## Crop, rotate and export

- Add a clearly visible `Crop & Rotate` action, accessible both via toolbar or geometry control near the preview. Crop overlay with draggable edges/corners; numeric aspect ratio via `Original`, `Free`, `1:1`, `4:5`, `9:16`, `16:9`; portrait/landscape orientation can be chosen regardless of source; rotate by ±90°, straighten by a small angle, and flip horizontally/vertically (if low-cost). Preserve edit geometry in source-relative coordinates and show exact final crop before export.
- An export dialog shows `Preset` (Instagram / General / Maximum Quality), `Aspect Ratio` / `Fit` or `Fill` / resolution, file format, name, folder and estimated output size when practical. Instagram offers Feed 4:5 and Reel/Story 9:16 choices; horizontal 16:9 remains available. Explicit selection of frame dimensions must be accompanied by a visual crop/padding indication.
- Preset **never** silently crops content. Default original geometry (and any explicit user crop) stays intact. If changing preset requires a new ratio, user sees crop/letterbox preview and chooses Fit or Fill. For Fit with a fixed aspect ratio, show neutral letterboxing/padding; Fill crops with repositioning. An `Original` export uses current manual crop, if any, at its own aspect ratio.
- Save/persist edit settings automatically without rendering. Export is a separate explicit action. Because preview caches are disposable and project edits are already persisted, **do not prompt on every file switch or cache eviction**. Warn when a file is intentionally removed from the project with unsaved recovery state, when deleting an edit recipe, or when replacing output. If autosave fails, warn and prevent silent loss. Restore edits on reopen.
- Exports are one at a time with progress/cancel, success affordance “Show in Finder,” and actionable failure message. Completion and Finder actions must belong to the current source/export attempt and clear on a fresh sheet or media switch. Never silently overwrite an output. Default path `~/Pictures/<AppName>/Exports/` for photo and `~/Movies/<AppName>/Exports/` for video; remember user's folder.

## Empty, loading and error states

- Empty window: centered `Open Photos or Videos` plus drag-and-drop affordance, unobtrusive shortcuts/help.
- Loading: preview thumbnail and spinner, not frozen app; video controls disabled until media ready.
- Unsupported media / missing file: plain explanation and Relink, not silent blank canvas.
- When project reopened: restore last item and last used panel (Easy/Advanced and Global/Masks); ensure source URL/bookmark security is re-established where applicable.
- Accessibility: keyboard navigation, ≥44 px target preferred for touch-future design though mac can be denser, meaningful labels, text contrast, reduce-motion friendly transitions, no color-only status indication.

## UI acceptance

At a 1440×900 logical-point window, the narrow browser, large media preview, and right inspector all remain usable. The collapsed browser adds width to preview. Photo controls show no scrubber; video controls show scrubber and trim without a full editor timeline. Right-side controls do not change or obscure the image on merely switching panels.
