# COLOR_ENGINE.md — Parameters, Algorithms and Underwater Easy

## Core rule

New imports store schema/renderer version 6 and source-color evidence. Saved renderers 1–5 retain their original appearance and Easy mapping; they are never migrated automatically. Renderers 2–6 use an extended-linear-sRGB RGBAh Core Image working context. Renderer 5 retains renderer 3's color math and renderer 4's source protection, adding spatial Visibility effects. Renderer 6 adds an output stage after framing and an explicit SDR delivery conversion. HDR/Log normalization remains unsupported.

Renderer 3 applies native `CITemperatureAndTint` in the linear working context, with the target-neutral direction inverted so positive Temperature warms and positive Tint moves magenta. The zero vector bypasses the filter. Exposure multiplies straight linear RGB by `2^EV` without intermediate clipping. A 4096-sample log-luminance tone curve uses an 18% gray pivot and Gaussian light-control lobes; pool-adjacent-violators projection enforces at least 0.05 log-space slope under opposing extreme settings. Its luminance gain is smoothly limited to 0.125...8.

The mixer selects eight overlapping hue bands from a bounded encoded-sRGB proxy, using wrapped Gaussian weights precomputed into a small recipe-keyed lookup table. Actual hue, chroma and lightness changes use signed-cube-root Oklab/Oklch in a Core Image Metal kernel. Hue shifts have a low-chroma gate; global Saturation and Vibrance scale perceptual chroma. The kernel handles straight color and repremultiplies alpha. An SDR shoulder activates continuously with positive highlight-driving edits; out-of-gamut RGB is mapped by fixed-hue Oklch chroma search, leaving valid RGB unchanged. These coefficients are initial behavior, not a calibrated match to another editor. Photo and video share this path, including local masks in saved blend order.

Renderer 4 samples an upright, ungraded source with a bounded 1024-pixel overview and up to twelve native-size 128×128 tiles per frame. Video uses three fixed positions within the selected trim. A 2×2 Haar/MAD proxy in signed encoded-sRGB opponent channels estimates chroma and luminance noise; too few usable tiles yields zero Auto confidence. The compact result is tied to file size, modification time, interpretation, trim, and analysis version. Auto demand uses this evidence and the final effective grade, including enabled local masks. At zero demand the protection stage returns the source image without launching its Metal kernel. Otherwise one 5×5 joint bilateral pass applies a combined source-aligned field, with separate Color Noise and Luminance Noise strengths. The provisional Auto evidence ramp is 0.002–0.015; manual Detail controls range 0–100, and Auto off leaves manual values authoritative. These are engineering estimates, not camera calibrations.

Renderer 5 extends the same source analysis snapshot with a bounded overview estimate of smooth blue/green water, rejecting clipped, dark, textured, and low-chroma candidates. The robust median water color and confidence are fixed across three sampled video frames and tied to source interpretation and trim through analysis identity version 2. Dehaze runs before creative color math: a small blurred transmission proxy applies a confidence-gated, scalar, bounded veiling-light correction (`t ≥ 0.60`), with weaker treatment in smooth water and bright/dark regions. Clarity runs after global creative math: a quarter-resolution log-luminance input and full-resolution guide drive Core Image's guided filter; a Metal kernel applies bounded signed detail gain, with noise-floor and tonal gates. Both effects bypass spatial work at zero. Local Clarity is available in masks; Dehaze is Global only because its water estimate is scene-wide. All constants are provisional visual estimates, not calibrated restoration or recovered scene depth.

Renderer 6 leaves that creative pipeline unchanged. After final crop, rotation and resize, an optional 0–100 Sharpening control applies a 0.85-output-pixel Gaussian luminance unsharp response, with a 0.0015 + 2.5×measured-luma-noise threshold, highlight/edge gates and at most 0.018 linear-luminance overshoot. Alpha edges are bypassed. Preview uses its selected output size; fit-to-window can hide detail visible in an export. The default zero amount is an exact bypass. Existing v4/v5 Detail JSON decodes missing Sharpening as zero, and older renderers ignore it.

V6 photo output converts through the shared float CIContext to tagged 8-bit sRGB JPEG/PNG. V6 video composition requests Rec.709 primaries, transfer and matrix together; Apple's Core Image composition path converts the source frames into that space, and the output CIContext uses Rec.709. A deterministic Metal TPDF term is applied in encoded sRGB before 8-bit photo quantization, or as an encoded-luminance approximation before the framework's video-range YCbCr quantizer. Video uses the source's nominal frame index, stills use stable output-pixel coordinates. The video term is ±one target luma code (8-bit or 10-bit), and Main10 uses one-quarter of the 8-bit amplitude. The final YCbCr quantizer is owned by AVFoundation, so this is not an exact final-stage YCbCr dither. Output is reopened and checked for sRGB/Rec.709 tags, and 10-bit-source HEVC must actually report Main10 before the temporary export is committed. JPEG/PNG remain 8-bit; H.264 is the compatibility path. Dither cannot reconstruct bands already present in source media.

There is **one actual set of color adjustments**. Easy slider coordinates contribute a deterministic `base` vector; Advanced edits contribute a `manualDelta` vector. The renderer and Advanced UI use `effective = clamp(base + manualDelta, parameterAllowedRange)`. The stored, unclamped delta remains intact to allow reversal of an Easy change; numeric Advanced controls show the **clamped rendered value**. A new Advanced target sets `manualDelta = requestedEffective - currentBase`. Switching tabs never changes results. Store Easy controls + manual deltas + masks; don't overwrite manual values on Easy movement.

All Easy parameters start at neutral. Each Easy component derives from its absolute slider position, **not accumulated incremental floating-point changes**. Contribution vectors add together so overlapping edits remain predictable. Historical v1–v4 projects keep `underwaterMappingVersion: 1`; v5 and newer imports use version 2. Both mappings remain executable, and saved projects are never silently recalculated under the new mapping.

## Canonical Advanced controls

- **Light:** `Exposure` −3...+3 EV (0), `Contrast`, `Highlights`, `Shadows`, `Whites`, `Blacks` each −100...+100 (0).
- **Color:** `Temperature` (−100 cool / +100 warm), `Tint` (−100 green / +100 magenta), `Saturation`, `Vibrance` each −100...+100 (0).
- **HSL Color Mixer:** 8 overlapping hue bands: Red (0°), Orange (30°), Yellow (60°), Green (120°), Aqua (180°), Blue (240°), Purple (275°), Magenta (320°). Each has `Hue` (−100...+100 mapped to ±45° maximum), `Saturation` and `Luminance` (−100...+100). HSL selective effect uses smooth hue-region weights with wraparound, not hard cutoffs or arbitrary discrete colors. Design the mixer so raising Green Hue shifts green **toward aqua/blue**, raising Aqua Hue shifts aqua toward blue, and neighboring channels blend smoothly. Preserve meaningful hue responses at very low saturation; do not create severe banding. Use color chips and readable labels; no color wheel required.
- **Detail:** Auto protection on by default, Color Noise 0–100 (0), Luminance Noise 0–100 (0); renderer 6 adds output Sharpening 0–100 (0).
- **Visibility (renderer 5):** Clarity −100...+100 (0), Dehaze 0...100 (0); local masks expose Clarity only.
- Numeric UI uses normalized integers for colors; Exposure may show two decimals. Actual algorithms need not match Adobe. Every active control must have a visible, monotone, reasonably standard effect and testable neutral=identity.
- Optional later: auto white balance and finer channels. **Don't render dead controls**; if a feature is not implemented, omit it rather than falsely exposing it.

## Standard processing model (implement once)

`Decode and orient original → honor profile/transfer → working-space conversion → source protection when demanded → renderer-5 Dehaze when requested → global white balance/exposure → global tone (contrast/highlights/shadows/whites/blacks) → global mixer + saturation/vibrance → renderer-5 Clarity when requested → each enabled mask's local edit and Clarity through its alpha mask in saved order → crop/rotate and resize → renderer-6 Sharpening when requested → target-aware dither and SDR conversion.`

White balance should be chromatically sensible, ideally using known Core Image temperature/tint support rather than naive RGB channel multiplication; use per-channel adjustment with safeguards only if needed. Exposure should act in linear light. Tonal edits should preserve continuity and avoid hard clipping; implement highlights/shadows/whites/blacks using a well-documented, smooth tone operator or common Core Image tools, with 0=identity, signed adjustments, bounded gains and stable end values. Contrast is a pivoted S-curve rather than uniformly multiplying brightness. HSL is best performed in a perceptually suitable encoded representation, with conversion to/from the working space handled explicitly. Vibrance preferentially increases low-saturation colors and protects highly saturated colors/skin as practical. Do not perform per-color hue shifts using unfeathered, discontinuous bins.

Precise photographic look is **provisional** and should be tested against supplied media. Use concise implementation notes to document exact constants, order and GPU/render performance. Preview/export use identical algorithm version and effective values (only render resolution and output conversion differ). Avoid double-applying Easy corrections as an invisible overlay.

## Underwater Easy — precisely defined initial input space

Initial sliders, saved as integers:

1. **Water Color**: `−100 ... +100`, neutral `0`. **Asymmetric**: negative = “Deepen Blue / reduce excess cyan” (never deliberately add green); positive = “Remove Green” (warm/magenta balance, green→aqua, aqua→blue, restrained green desaturation and blue emphasis). UI labels at endpoints and a centered neutral tick. This is *not* Blue↔Green symmetric white balance.
2. **Color Recovery**: `0 ... 100`, neutral `0`, mild red/orange/yellow + vibrance/saturation recovery; preserve sand/skin where possible; don't amplify clipped/noisy red data excessively.
3. **Light**: `−100 ... +100`, neutral `0`, negative for darker, more subject-focused background; positive to brighten dark exposure while lifting shadows and protecting highlights.
4. **Visibility**: `0 ... 100`, neutral `0`; v1 mapping uses contrast/black-level adjustment, while v2 adds restrained Clarity and Dehaze. Neither mapping promises to recover scene depth or lost wavelengths.

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

This table remains the **v1 historical mapping**. New v5 recipes use `underwaterMappingVersion: 2` with the provisional knots below; no separate hidden Visibility filter runs.

| Easy | Contrast | Blacks | Highlights | Clarity | Dehaze |
|---:|---:|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 | 0 | 0 |
| 50 | +4 | −3 | −2 | +8 | +10 |
| 100 | +8 | −5 | −4 | +16 | +20 |

## Correctness and behavior tests

- All neutral Easy sliders + zero manual deltas yield identity within agreed working-space tolerances; no unexpected exposure shifts.
- Example: Easy Water Color base Temp +10; Advanced user sets +15 ⇒ delta +5. User changes Easy such that base +15 ⇒ Advanced and rendered Temp +20. The Easy UI remains at the chosen input position. Same behavior for HSL and masked values.
- Two different Easy sliders changing the same parameter produce sum of contributions. Avoid cumulative rounding drift; use internal Float/Double precision and round **only when displaying**.
- Save/reopen returns **byte-identical serialized values** for slider positions, deltas, masks and mapping version. Undo/redo restores joint state per user gesture.
- Every HSL hue band wraps correctly across 360°, feathered transitions are smooth, with no sharp color contouring. No NaNs, infinity or negative-alpha corruption.
- Basic parameter extremes are bounded and reversible; same input+recipe outputs same pixels within GPU/codec tolerances. Preserve notes of current known differences.

## Iteration workflow for user calibration

Later, use actual underwater images to record: image type, starting settings, target manual grade, Easy-slider vector, visual acceptability and Advanced deltas. Revise lookup knots or add scene profiles only based on repeatable observed patterns. **Do not build a trained prediction model, image classifier or auto-white-balance system for v1.**
