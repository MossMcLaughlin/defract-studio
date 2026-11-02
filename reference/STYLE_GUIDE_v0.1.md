# Photo & Video Editor
## Visual Identity & Interface Style Guide

**Version 0.1 · 2 November 2026**  
**Status:** Proposed visual design direction; suitable as a foundation, not yet a final UI specification.  
**Product name and logo:** Not selected. “Photo & Video Editor” is a working title only.  
**Source material:** Watermark Expeditions *Visual Identity & Media System v2.0* (August 2026), adapted for software; *Photo & Video Editor — Product Foundation v0.1* (October 2026).

> **Design thesis:** An editorial identity surrounding a neutral, precise editing workspace. The product should feel capable and carefully made, while the photograph or video—not the interface—supplies color and emotion.

---

## 01 · Foundation — transfer the philosophy, not the expedition branding

**Keep from Watermark:** editorial restraint; black and warm-white structure; a distinctive serif for brand moments; a highly legible modern sans serif for information; gold and Pacific Blue used sparingly; authentic photography as the visual centerpiece; clear, calmly confident language.

**Change for editing software:** precision replaces adventure as the central impression. The application should disappear while someone edits. Feature-rich visual metaphors, decorative gradients, and strongly colored panels compete with evaluating exposure, color casts, and saturation, so they do not belong near the preview.

**Four character traits**

- **Capable, not complicated.** Expose the essential controls clearly; avoid professional-software theater.
- **Refined, not ornamental.** Quiet hierarchy, consistent spacing, and confident typography—not effects or decoration.
- **Approachable, not simplistic.** Easy edits get users close; Advanced reveals the actual underlying values and full control.
- **Trustworthy, not magical.** The app accurately shows edits, preserves originals and work, and describes automatic features without promising perfection.

**Product principles:** local-first; consistent photo/video controls; frictionless export; minimal maintainable implementation; predictable, non-destructive results; engineering verified on real files.

**Boundary:** Reuse the palette and type families, **not** the Watermark W, circle, waves, logo geometry, expedition iconography, or expedition language. A new product identity and app icon will be designed after the product name is chosen.

## 02 · Color system — brand palette and editor semantics

### 2.1 Original brand palette (retained)

| Token | Hex | Software usage |
|---|---|---|
| Expedition Black | `#0B0B0A` | Brand typography, cover panels, high-contrast surfaces |
| Warm White | `#F6F2E9` | Editorial backgrounds and high-contrast UI text |
| Watermark Gold | `#D0A037` | Restrained brand accent, selected primary call to action |
| Pacific Blue | `#2D708F` | Editorial rules and information hierarchy on light surfaces |
| Sunwashed Sand | `#C7A66A` | Subtle editorial warmth, never a signal for image correction |
| Stone Grey | `#71716C` | Decorative/secondary brand use; **not** small text on dark surfaces |

The photography must **never** be tinted or color-matched to this palette. A blue underwater image and a warm alpine sunset must look equally at home in the brand.

### 2.2 Editor-only semantic colors (proposed additions)

| Role | Hex | Usage |
|---|---|---|
| Canvas / image surround | `#171919` | Neutral image/video surround |
| Main application surface | `#202322` | Left browser, inspector background |
| Raised surface | `#292C2B` | Popovers, selected components, export panels |
| Subtle divider | `#414644` | Panel separators and thin rules |
| Primary UI text | `#F6F2E9` | Headings, labels, numerical values |
| Secondary UI text | `#BFC5C2` | Supporting labels and metadata |
| Interactive focus blue | `#74B8D4` | High-contrast focus/selection states on dark surfaces |

These are **functional UI tokens**, not replacements for the six-color brand palette. Pacific Blue is too low-contrast for small text on dark editor surfaces; the brighter focus blue is a purposeful UI-only adaptation. Gold can be used for one dominant action (for example, *Export*) but should not flood slider tracks or image borders.

**Color restraint rules**

- The preview surround stays neutral, with no colored backlight, tinted checkerboard, or persistent overlays.
- Use color to communicate state or an important action, not to decorate every control.
- Use Warm White or sufficiently bright neutrals for readable text; test all actual color pairs for contrast.
- Keep error/success/warning colors separate from the brand system and pair them with text/icons; do not rely on hue alone.
- Mask overlays may be colored for visibility **only while editing masks**, and must be hideable; the normal preview stays unaltered.

## 03 · Typography and iconography

**Brand display family:** **Cormorant Garamond SemiBold**. Use for a landing/welcome headline, product website, promotional banners, editorial section covers and occasional large empty-state messages. Its role is expressive, not operational.

**Working/interface family:** **Manrope Regular / Medium / SemiBold**. Use for navigation, labels, sliders, numerical values, dialog boxes, export descriptions, tooltips, button text, onboarding, and long-form documentation. Native macOS UI type may be used where platform controls demand it; consistency and legibility win over font purity.

| Role | Proposed size | Typeface / treatment |
|---|---|---|
| Editorial hero | 38–56 pt | Cormorant Garamond SemiBold, restrained line length |
| Welcome heading | 26–34 pt | Cormorant Garamond SemiBold |
| Editor window heading | 17–20 pt | Manrope SemiBold |
| Inspector section heading | 13–14 pt | Manrope SemiBold |
| Main control label / value | 12–13 pt | Manrope Medium; tabular figures for values |
| Supporting text / tooltip | 11–12 pt | Manrope Regular, sufficient contrast |

Avoid serif inside dense toolbars and adjustment inspectors. Avoid tiny spaced-uppercase labels as a dominant UI convention. Use SF Symbols for actions where practical; keep icons simple, stroke-consistent, and accompanied by labels or tooltips on first use. Fallbacks for documents: Georgia (display), Arial (body). Font licenses and packaging must be verified before distribution; do not embed arbitrary third-party font files without their required notices.

## 04 · Product composition — a calm editing workspace

A single editing workspace should serve both photos and individual video clips. The interface should borrow Lightroom's approachable grouping, not DaVinci Resolve's node graphs or complex page switching.

**Proposed desktop shell (dimensions are starting targets, not fixed implementation constraints):**

```text
┌───────────────────────────────────────────────────────────────────────────┐
│ App / File             Filename · media details         Undo  Redo  Export │
├──────────────┬────────────────────────────────────────┬───────────────────┤
│ Media browser│                                        │  Easy | Advanced  │
│ (collapsible)│            MEDIA PREVIEW               │  Global / Masks   │
│ thumbnails   │           neutral surround            │  color controls   │
│              │                                        │  numeric values   │
│              │                                        │                   │
├──────────────┴────────────────────────────────────────┴───────────────────┤
│ Filmstrip (optional). Video: play · scrub · in/out trim controls           │
└───────────────────────────────────────────────────────────────────────────┘
```

**Layout priorities:** Give the preview the most space. The inspector is approximately 320–360 pt wide; the media browser is collapsible; the filmstrip can hide when editing a single item. Video-specific transport and trim controls appear below the viewer, without introducing a multi-clip timeline. Keep a sensible minimum window width; below it, collapse secondary panels rather than shrinking the preview into irrelevance.

**Navigation model:** Welcome / Open Files → Editor → Export sheet. No required media catalog, signup, project dashboard, or separate “Color” workspace. Opening a collection should create a lightweight local editing session with independent edits per file.

## 05 · Controls and interaction language

**Buttons:** One prominent action per screen. *Export* is a clear primary action; *Reset* and *Cancel* remain visually secondary. Use icon + text where discoverability matters. Avoid decorative pills on every surface.

**Sliders:** Direct manipulation with visible numeric results where relevant. Double-click or explicit reset affordance should restore a known default; keyboard arrow adjustment and suitable fine-adjustment behavior should be explored. Slider gestures must form a single undo operation, including an Easy gesture that moves multiple advanced parameters.

**Inspector groups:** Light · White Balance · Color · Color Mixer · Detail (if included) · Geometry · Masks. Use short groups, collapsible sections, regular spacing, and clear hover/focus states. The precise Advanced control list is still open, especially RGB channel controls versus HSL color bands.

**Easy / Advanced interaction — agreed:** Easy sliders compute a base vector; Advanced stores per-parameter deltas. **Rendered and displayed effective value = Easy base + Advanced delta.** Moving between panels never changes the grade by itself. Easy retains its positions after manual tweaks; Advanced always shows the final numbers. A one-time *Customized* explanation can clarify the recommended Easy-first, Advanced-finish workflow. A manual-offset reset remains available without silently clearing Easy settings.

**Underwater Easy — four provisional controls:** Water Color (Blue to Green), Color Recovery (Subtle to Strong), Light (Darker to Brighter), and Visibility Correction (Low to High). Their labels, ranges, nonlinear response, and mappings must be calibrated against real underwater photographs before they become implementation contracts. A generic-photo Easy mode is lower priority. No LLM or image-analysis dependency is required for these controls.

**Mask editing:** Photos support subject detection where feasible plus brush add/erase, brush size, feather, invert, linear and radial masks. Preserve the generated mask, manual refinements, and strokes. Video supports **static linear and radial masks only**; no video subject segmentation/tracking. Mask adjustments use the same conventional adjustment UI as global edits, just spatially restricted. The mask overlay is a temporary working aid, not a color grade.

**Before / After:** Provide an immediately discoverable comparison control (hold-to-view-original or toggle) in the editor. Specify exact interaction later; it must not change persisted edit state.

## 06 · Media behavior and preview trust

The edited media is always the focal point. Avoid false improvements caused by tinted containers, artificial sharpening in thumbnails, or inconsistent preview gamma.

- Center and scale media without stretching; make *Fit* versus *Fill* explicit where crop and export framing matter.
- Reflect crop boundaries and final output aspect ratio in the preview before exporting.
- Keep waveform, histogram, and technical readouts optional or secondary rather than front-and-center during initial work.
- Treat video playback as a first-class workflow, preserving audio and applying the same global color recipe used for still images.
- Test iPhone HDR-to-SDR handling, GoPro 10-bit Flat footage, and TG-7 stills; do not assume color-space correctness because a file can be decoded.
- Distinguish genuine preview-render differences from display settings (True Tone, Night Shift, display profile) in testing instructions.

**Image policy for public-facing materials:** Use authentic before/after samples with clear labels and identical framing; no misleading saturation boosts. Feature images can come from marine wildlife, reefs, mountains, skiing, or mountain biking. Show both underwater specialization and general editing capability; avoid stock “AI magic” visuals.

## 07 · Export design — clear and dependable

Export is a deliberate but lightweight sheet, not a technical render page. Three preset families are recommended: **Social**, **General**, **Maximum Quality**. The sheet should expose destination, file type, framing, resolution, and quality only as needed; advanced codec options can hide under disclosure if eventually supported.

**Core behaviors:** Before confirming, show the actual crop/letterbox result and its output dimensions. Provide *Fit / Fill* and orientation-aware presets; preserve audio for clips; surface export progress; never report success if writing fails; do not overwrite the original silently. Keep export terminology user-facing (*High quality*, *Original size*) while still showing specific pixel dimensions in the details.

**Voice examples:** “Keep original framing” instead of “Bypass transform.” “Fill frame (crops edges)” instead of “Scale to fill.” “Export complete” only after the output file is verified.

## 08 · Identity beyond the editor

The marketing/portfolio presentation may be lighter and more editorial than the editing workspace itself: Warm White pages, black headlines, generous margin, Cormorant title, Manrope captions, and one blue or gold accent per composition. Use actual product screenshots and convincing edits rather than conceptual UI decoration.

**Logo direction (future decision):** Simple flat symbol or wordmark, legible at macOS app-icon size. A restrained split-frame or image-adjustment motif could be evaluated, but no final symbol is approved. Do not borrow the Watermark mark. App icon development follows naming and UI direction; it is not needed to validate the editing engine.

**Verbal identity:** Clear, precise, calm, lightly editorial. Prefer “Adjust water color”, “Refine subject mask”, “Preserve original”, “Apply to next image”, and “Export with audio.” Avoid “Perfect in one click”, “AI-powered magic”, “Pro-grade cinematic”, or guarantees of faithful underwater color recovery.

**Asset conventions:** Until naming is settled use `editor-[asset]-[variant]-[theme]-[size].[ext]` for exported UI/marketing assets. Keep source vectors and editable diagrams in the repo; derive platform icons and PNGs from a single approved master once an identity is selected.

## 09 · Accessibility and implementation handoff rules

- Use semantic component colors, not hardcoded accent values scattered through views. Maintain light/dark/high-contrast variants if those modes are supported.
- Target at least 4.5:1 contrast for normal text; check custom pairings rather than assuming the inherited palette is accessible. Prefer native macOS focus, reduced-motion, and accessibility behaviors.
- Keyboard access must reach export, Easy/Advanced switching, principal editing controls, mask operations, and file navigation. Show visible focus when navigating by keyboard.
- Never communicate masked areas, warning conditions, or selected state by color alone. Mask overlay appearance and opacity must be adjustable or toggleable.
- Centralize typography, spacing, semantic colors and component treatments in a small design-token layer. Do not create a giant bespoke UI framework; use native SwiftUI/AppKit components wherever they meet UX requirements.
- Preserve actual image pixels: no destructive edits to original files, no presentation-only color manipulations, no hidden color-correction effects that Advanced cannot inspect.
- Include screenshots / reference states for: welcome, photo global edit, photo mask edit, video trim/edit, export, and empty/error states in the later detailed UX spec.

## 10 · Decisions, proposals, and handoff gaps

| Item | Current status |
|---|---|
| Reuse six-color palette, Cormorant + Manrope, restrained editorial character | **Agreed input** |
| Distinct software identity; do not reuse Watermark logo | **Recommended boundary** |
| Neutral, dark-first editor with brighter functional focus blue | **Proposed UI direction** |
| One workspace for photos and single clips; right inspector; optional filmstrip | **Agreed direction; detailed layout open** |
| Advanced shows effective values; Easy base + preserved manual delta | **Agreed behavior** |
| Four underwater Easy sliders | **Agreed starting concept; calibration open** |
| Photo subject/brush masks, still/video gradients, no video subject tracking | **Agreed scope** |
| Exact product name, app icon, and website identity | **Open** |
| Minimum macOS version, hardware baseline, codec/color pipeline, concrete export presets | **Technical specification open** |
| Typography scale and UI semantic tokens in this guide | **Provisional; validate in an interactive prototype** |

**Immediate UI design task:** Establish the editing screen at realistic Mac window sizes and test four flows—underwater photo global correction; photo subject mask correction; single GoPro clip grade/trim; social export. Finalize component behavior and responsive collapse rules before handing off the complete product.

---
