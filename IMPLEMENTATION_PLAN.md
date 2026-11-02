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
