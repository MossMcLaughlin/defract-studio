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
