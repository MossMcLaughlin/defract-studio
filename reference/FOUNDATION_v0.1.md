# Photo & Video Editor
## Product Foundation & Design Direction

**Version:** 0.1 — Foundation draft  
**Date:** 12 October 2026  
**Status:** Working product direction; not yet an implementation specification  
**Audience:** Project owner, future design collaborators, and AI coding agents

> **Product thesis:** Build a deliberately small, unusually well-engineered macOS application for locally editing photos and individual video clips. Deliver approachable Lightroom-like color controls, a genuinely useful underwater correction workflow, selective adjustments for photos, and reliable exports—without reproducing a professional editing suite.

---

## 1. Purpose and success criteria

The project serves two purposes: (1) create a useful tool for the owner's real photography and video workflows, especially underwater media; and (2) demonstrate strong software engineering and practical agent-assisted development as a portfolio project. It is not intended to replace Lightroom or DaVinci Resolve, nor to become a full video production suite.

The primary success criterion is **speed to an acceptable edit**: a user should be able to correct common underwater color problems with a small number of guided controls, inspect the resulting conventional adjustment values, and fine-tune only when necessary. A difficult image may legitimately require Advanced editing. “One-click perfection” is explicitly not the objective.

Other success criteria include consistent results across previews and exports, non-destructive editing, predictable UI behavior, maintainable code, and reproducible testing against real camera media.

## 2. Product principles

1. **Local-first.** Open originals from the Mac's file system, process on-device, and avoid uploads, accounts, servers, and cloud infrastructure.
2. **One approachable editor.** Photos and single video clips share a consistent workspace and color controls. No node graphs, multi-clip timelines, or separate grading environments.
3. **Frictionless export.** Provide understandable choices for aspect ratio, resolution, and quality; use sensible presets for social media, general sharing, and high-quality output.
4. **Small scope; unusually good engineering.** Favor simple, well-organized modules, few dependencies, explicit state, and native functionality rather than speculative architecture or unnecessary generated code.
5. **Non-destructive and trustworthy.** Keep originals intact; save recipes, masks, and edits; preserve undo/redo; make previews representative of exported results.
6. **Testable agent-driven delivery.** Coding agents may implement much of the project, but every milestone needs build, automated, and real-media verification. Documentation does not substitute for testing.

## 3. Intended users and core scenarios

**Initial user:** A Mac-based photographer/diver editing iPhone 15 photos and videos, GoPro HERO12 Black footage (including 10-bit Flat footage), and Olympus TG-7 photographs. The editor must remain useful for non-underwater material such as skiing, mountain biking, landscapes, and portraits.

**Core scenarios:**

- Open a single underwater photo, use a few guided controls to recover a natural-looking grade, then make precise HSL/white-balance edits where required.
- Select a turtle or shark in a still photo, fix or paint a mask if automatic subject selection is imperfect, and adjust the animal separately from the water or reef.
- Apply a gradient over bright surface water or a sandy bottom without affecting the rest of the photograph.
- Open a GoPro clip locally, preview and adjust its color in motion, trim/crop it, and export an accurately framed MP4 with preserved audio.
- Work through similar files from one dive; reuse Easy settings or an entire previous grade, then make small per-image corrections without reopening ten individual parameters.

## 4. Scope and feature boundaries

The MVP should implement **strong shared global adjustments for photos and video**. Masking intentionally differs between media types because moving-subject tracking would disproportionately increase complexity.

| Capability | Still photos | Single video clips | Priority / notes |
|---|---|---|---|
| Exposure, contrast, white balance, color and HSL | Yes | Yes | Core MVP |
| Underwater Easy controls + Advanced controls | Yes | Yes | Core MVP |
| Live graded preview | Yes | Yes | Core MVP; playback performance to validate |
| Crop, rotate, aspect-ratio controls | Yes | Yes | Core MVP |
| Linear and radial masks | Yes | Yes | MVP; video masks fixed in frame |
| Automatic foreground/subject mask | Target | No | Photo only; feasibility gate for marine animals |
| Manual mask brush, erase, feather, invert | Yes | No | Photo only; fallback/refinement for selection |
| Trim, scrub, preserve audio | N/A | Yes | Single clip only |
| Non-destructive saved edits, presets, undo/redo | Yes | Yes | Core MVP |
| Export image / MP4 with clear presets | Yes | Yes | Core MVP |
| Motion tracking or video subject masking | N/A | No | Explicitly out of scope |
| Multi-clip timeline, transitions, compositing suite | N/A | No | Explicitly out of scope |

**Deferred or investigatory:** generic-photo Easy mode (lower priority), portrait depth/bokeh editing, sophisticated automatic white balance, RAW/ORF support, advanced noise reduction, HDR export, and more advanced masks. These must not silently enter MVP scope.

## 5. Unified editing experience

The interface should borrow the *approachability* of Lightroom's adjustment panels, not its internal algorithms. Its general layout is a large central preview, a clearly organized right-hand adjustment panel, optional media filmstrip/browser, and video playback/trim controls when relevant. Dark, restrained styling is preferred, but exact visual design is still open.

The principal distinction is between **Easy** and **Advanced** controls—not different editing engines:

- **Easy** exposes a small number of meaningful guided controls, initially specialized for underwater media.
- **Advanced** exposes the actual effective exposure, temperature, tint, saturation, HSL, and other supported adjustments.
- Changing the visible panel alone must never alter the image. Switching modes preserves all values.
- The application remembers the most recently selected editing panel.
- Show a brief, non-intrusive explanation when returning to Easy after manual refinements; do not repeatedly interrupt the user. Recommend Easy first, Advanced for finishing.
- Masks use the **same adjustment definitions**. Only the area affected changes; there is no separate masking-grade interface or Easy mode for masks.

### 5.1 Guided underwater controls — initial hypothesis

Start with four sliders. Their names and mappings are **provisional** and will be tested using actual photographs:

| Proposed control | User-facing intent | Candidate parameters it may influence |
|---|---|---|
| **Water Color — Blue to Green** | Correct characteristic water-color shifts | Temperature/tint and selective cyan/green/blue HSL changes |
| **Color Recovery — Subtle to Strong** | Restore restrained warmth and lost color | Red-channel recovery where usable, warmth, saturation/vibrance |
| **Light — Darker to Brighter** | Improve the overall tone | Exposure, shadows, highlights/whites as appropriate |
| **Visibility Correction — Low to High** | Improve hazy or low-contrast appearance | Contrast/blacks; limited local-contrast correction if justified |

Earlier working terminology included **Depth / Light**, **Visibility**, and **Correction Strength**; keep them available for testing. Do not assume environmental labels perfectly describe image conditions. We may adjust names, direction, ranges, or relationships after real-world testing.

The mappings should initially be **deterministic**: the same Easy-slider positions should generate the same base adjustment vector regardless of the source image. No image analysis or machine learning is required for this workflow. Optional Auto White Balance may be explored later but must not be a dependency. Strong color recovery can magnify noise or produce artificial reds, so mappings need conservative limits and empirical review.

The owner will later provide a documented calibration guide based on editing representative photos manually, noting which conventional adjustments change, in what direction, and by approximately how much. That calibration work is **not completed** in this document.

### 5.2 Easy / Advanced state behavior — agreed

For each adjustable parameter, keep an Easy-generated base value and a persistent manual offset:

**Effective value = Easy base + Advanced manual offset**

Example (temperature, using illustrative UI units): Easy sets +10; Advanced changes visible temperature to +15 (offset +5); the Easy correction later changes its base to +15; Advanced now shows +20. The Easy slider's position does not change because of an Advanced edit.

Additional rules:

- Advanced **always** shows the effective values actually applied to the media.
- The Easy base is recalculated from current Easy slider positions, not repeatedly accumulated from previous drag events.
- Advanced edits change manual offsets relative to the current Easy base, preserving the Easy positions.
- A slider drag modifying multiple parameters is **one undoable operation**; all affected values revert together. Undo/redo spans Easy, Advanced, cropping, masks, and other edits.
- Switching panels is not an edit. Save both Easy positions and manual offsets non-destructively.
- Offer separate reset actions for Easy corrections and Advanced refinements; precise UI is open.
- Parameter clamping/boundaries and non-additive operations require a defined, tested policy. The equation is a conceptual user-facing invariant, not an excuse to use physically inappropriate arithmetic for every image-processing operation.

### 5.3 Advanced color controls — working proposal

Initial organization, inspired by Lightroom-style controls:

- **Light:** Exposure, contrast, highlights, shadows, whites, blacks.
- **White balance:** Temperature and tint.
- **Color:** Saturation and vibrance.
- **Color mixer:** Hue, saturation, and luminance per color band; blue, cyan, green, and red are especially important underwater.
- **Potential extension:** Direct RGB channel controls/red recovery if not adequately handled by existing adjustments.
- **Detail:** Basic sharpening is a candidate; sophisticated denoise is not currently core.

Exact algorithms, color ranges, slider limits, HSL bands, precision, and processing order remain to be defined. The objective is predictable editing quality—not reproducing Adobe's proprietary rendering.

## 6. Selective adjustments and masking

**Photos:** Support automatic foreground selection if platform-native segmentation proves useful, with a manual brush to add areas, an erase brush to remove areas, adjustable size and feathering, invert mask, and linear/radial gradients. The user must be able to preview a translucent selection overlay and apply the familiar Advanced adjustments only within it.

**Videos:** Support fixed linear and radial gradient masks and their adjustments. **Do not implement video subject masking, tracking, or frame-by-frame segmentation.**

Evaluate Apple's on-device Vision foreground segmentation using real shark, turtle, diver, and reef photographs. Do not assume it works reliably on marine animals. If it fails on a given image, users should still be able to make practical selections with the brush and gradients. No custom-trained segmentation model is planned for MVP.

**Persistence requirements:** Save automatically generated masks, refinements, brush strokes/erasures, feather parameters, and all associated local adjustments. Reopening a project must not re-run segmentation and replace manual work. Retain a resolution-independent or full-resolution representation sufficient for accurate export, and keep edits reversible.

## 7. Import, editing sessions, persistence, and export

**Input:** Load local JPEG/PNG/HEIC and common macOS-playable MP4/MOV video formats, with H.264 and HEVC as intended targets. Test 10-bit GoPro clips and iPhone media explicitly; exact codec/device guarantees await feasibility testing. Olympus ORF/RAW is investigatory, not assumed. Image orientation, metadata, and iPhone HDR transfer characteristics must be handled deliberately.

**Editing sessions:** Favor a lightweight file/session model with an optional filmstrip rather than a managed photo library. Users can import several files, switch quickly, copy **Easy Settings** separately from **All Adjustments**, and retain independent per-file edits. Originals remain in their current file locations. A moved-file relinking flow should be considered.

**Storage:** Use versioned local project/edit-recipe data referencing original files, with saved settings, mask data, and undo-compatible edit state. Exact on-disk format and autosave behavior are still technical-design decisions; JSON recipes are a plausible starting point. Do not overwrite originals without an explicit user request.

**Export:** Simple JPEG/PNG still-image exports and MP4 video exports; preserve video audio, orientation, intended frame rate when appropriate, and sensible color appearance. Present clear options for resolution, aspect ratio, cropping (Fit vs Fill), and quality, including vertical social-media presets. The export preview must accurately show what will be cropped or letterboxed to avoid unexpected black bars.

**Color management:** Color-space interpretation is a core engineering concern despite not being a complex user-facing feature. Prioritize trustworthy SDR export and explicit HDR-to-SDR behavior before promising full HDR editing/export. Ensure playback and exported frames agree in appearance within an agreed tolerance.

## 8. Candidate technical architecture — not finalized

The current leading proposal is a **native macOS application** built with **SwiftUI (plus AppKit where necessary)**, **Core Image** for shared image processing, **AVFoundation** for video playback/compositing/export, **ImageIO** for still-image I/O and metadata, and optional **Vision** for still-photo subject detection. Metal-backed processing is a likely optimization, not a reason to invent a custom GPU engine prematurely.

This stack remains **provisional** until a short feasibility prototype validates: (a) identical graded still/video semantics, (b) sufficiently responsive video playback, (c) correct export and color handling, and (d) useful automatic photo subject masks. Establish the user's exact Mac hardware and minimum supported macOS version before locking platform decisions.

The implementation should favor a few clear responsibilities: media access, edit state/recipes, color-processing pipeline, masks/compositing, preview, export, and UI. These are responsibilities, **not** permission to generate a framework of dozens of classes and interfaces. Avoid duplicate photo/video grading engines.

No cloud processing, remote inference, runtime LLM, or custom machine-learning model is needed. Agent-assisted development will use subscription-based tools selected separately.

## 9. Development sequence and feasibility gates

| Stage | Purpose | Exit evidence |
|---|---|---|
| **0. Technical feasibility** | Shared edits on still + video; basic underwater mapping; assess marine-animal segmentation and color handling | Test media opens; same edit recipe previews/exports; documented technical risks |
| **1. Core editor** | Local import, graded photo/video preview, global Advanced controls, initial four Easy sliders, saved non-destructive recipes | Can edit representative image and clip and reopen state intact |
| **2. Selective edits and geometry** | Photo subject/brush/gradient masks; video static gradients; crop/rotate and single-clip trimming | Saved masks re-open unchanged; correctly localized render; trims/crops export accurately |
| **3. MVP reliability and polish** | Export presets, filmstrip/copy edits, undo/redo, performance, keyboard/UI polish, automated verification, packaging | Repeatable end-to-end workflows and passing golden-media checks |
| **4. Optional future releases** | Portrait blur, advanced RAW/HDR capabilities, improved denoising, optional generic Easy mode | Prioritize only after MVP proves useful |

Stage numbering describes sequence, not a license to defer essential tests: export/color correctness, masks' persistence model, and undo state should be considered early enough to avoid costly redesigns.

## 10. Quality gates and working method for coding agents

Agent-built code must be intentionally small and maintainable, not merely quick to generate.

- Give agents bounded tasks with explicit inputs, behavior, tests, and a definition of done. Never rely on a single “build the whole editor” instruction without milestone checkpoints.
- Prefer standard Apple frameworks and minimal dependencies; require justification for substantial libraries or abstraction layers.
- Use one shared adjustment model and rendering implementation where possible. Keep photo-only features clearly isolated rather than infecting the video pipeline.
- Require a clean build, meaningful automated unit/integration tests, and a concise test report after each milestone.
- Maintain a small representative **golden-media suite**: TG-7 underwater stills, iPhone JPEG/HEIC/HDR media, GoPro HERO12 Flat/10-bit clips, high-contrast reef scenes, sharks/turtles, green water, and problematic crops.
- Verify saved/reopened edits are identical, undo/redo restores complete operations, preview/export grading agrees, audio survives export, and failed exports produce comprehensible errors.
- Benchmark interactive performance on actual hardware; establish 1080p/30fps as an initial test target rather than a guaranteed specification. Evaluate lower-resolution 4K preview if necessary.
- Capture known limitations and architecture decisions in short records; do not generate excessive documentation or code for hypothetical future features.

**Human verification remains necessary:** especially image quality, visual mask quality, and export color. Automations should minimize manual debugging work but cannot entirely eliminate human judgment.

## 11. Open decisions and research backlog

These are intentionally **not resolved** in this foundation document:

1. Four underwater slider names, ranges, response curves, and precise mappings. The owner will produce a photo-based calibration guide.
2. Final Advanced control set: HSL bands/behavior, whether direct RGB adjustments are needed, and precise color-space/processing choices.
3. Input color-space detection and treatment of camera Flat/Log-like settings and HDR footage; clear baseline versus later advanced overrides.
4. Segmentation quality for marine subjects and the minimum practical manual brush/mask representation.
5. Exact minimum macOS version, hardware/performance baseline, and whether the proposed native stack meets requirements.
6. File/project package structure, persistence and autosave semantics, relinking, mask-resolution strategy, and undo history lifecycle.
7. Final UX visual language, media browser/filmstrip behavior, keyboard shortcuts, and export preset definitions.
8. Objective image-quality comparisons and measurable usability thresholds (time-to-edit, adjustment count, preview latency, rendering reliability).

## 12. Decision register

| Decision | Status |
|---|---|
| Native macOS MVP; no cloud or account dependency | **Agreed** |
| Equal-quality attention to photo and single-clip video global editing | **Agreed** |
| No multi-clip timeline/node editor | **Agreed** |
| Underwater Easy + Advanced over the same visible effective adjustment values | **Agreed** |
| Easy base + manual offset behavior; switching views does not modify grade | **Agreed** |
| Four initial deterministic underwater sliders; precise definitions to be calibrated | **Agreed direction / mappings open** |
| Photos: automatic subject selection candidate + editable brush masks | **Agreed target / platform quality unverified** |
| Videos: static linear/radial gradients; no video subject masks | **Agreed** |
| Shared non-destructive project state, persistent mask refinements | **Agreed** |
| SwiftUI / Core Image / AVFoundation / Vision technical stack | **Proposed, not final** |
| Precise advanced algorithms, codec guarantees, RAW/HDR export support | **Open** |

## 13. How this document will be used

This is the **first foundation document**, not an instruction to start coding. Its purpose is to preserve product decisions and clearly label hypotheses and feasibility risks. The future agent-facing delivery set should expand it into: (1) a detailed Product Requirements Document; (2) an interaction and UX specification; (3) architecture, data models and media pipeline; (4) feature contracts and acceptance tests; and (5) a staged implementation roadmap with agent instructions and verification checklists.

**Next design activity:** calibrate underwater Easy sliders with representative, manually graded real photographs and settle the minimum Advanced color-control vocabulary. Do not assign specific correction formulas until that work has been completed.
