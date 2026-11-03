# Project verification and status

Last updated: 2026-11-03. This is the current status record; earlier gate-by-gate details remain in Git history.

## Build and automated tests

Development machine: Apple M1 MacBook Pro, macOS 26.5.2, Xcode 26.6 (17F113), macOS SDK 26.5. The app targets macOS 15+, but an actual macOS 15 runtime has **not** been tested. Local Debug builds use `CODE_SIGNING_ALLOWED=NO`.

```sh
xcodebuild -quiet -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO test
```

The latest implementation run on 2026-11-02 passed **28 tests, 0 failures, 0 skips** (`Test-EditorApp-2026.11.02_23-27-02--0500.xcresult`). Those tests use the local photos and all three GoPro clips. They check non-destructive JPEG/PNG export; color and Easy base/manual delta serialization; mask blend, inverse copy and radial angle; geometry, trim, orientation and Fit/Fill; output audio and Rec.709 tags; preview/export comparisons; cancellation/overwrite; corrupt project recovery; and original-file hashes. `GX011247.MP4` was verified as HEVC Main 10, 10-bit **Rec.709 SDR**, portrait by display transform, with AAC stereo. SDR export intentionally may use an 8-bit codec. The local `test_media/` files remain on disk and out of future Git commits.

Repository cleanup on 2026-11-03 changed documentation only. The exact build and test commands above were rerun: build **passed**, tests **28 passed, 0 failed, 0 skipped** (`Test-EditorApp-2026.11.03_00-20-31--0500.xcresult`). No application source, Xcode configuration, or test code changed in the cleanup.

Current tracked documentation is `README.md` (use/build/handoff index), `AGENTS.md` (standing workflow), `PRODUCT_MVP.md` and `UX_SPEC.md` (approved product/interaction), `COLOR_ENGINE.md` (color contract), `MEDIA_AND_TESTS.md` (fixtures/acceptance), `DEV_NOTES.md` (actual implementation), `VERIFICATION_REPORT.md` (status), and the style guide in `reference/`. The exact-copy master specification, completed gate plan, first-run/template files, outdated illustrative architecture/foundation, and separate Gate 3 report were retired after their lasting decisions and current results were incorporated here; Git history retains their full text. The already present `.handoff/current/` UI polish task was not modified or executed by this cleanup.

Historical checkpoints: Gate 0 passed 5 tests, Gate 1 passed 11, Gate 2 passed 21, and Gate 3 passed 26. Gate 3 refinement raised the suite to 28. Git history preserves the detailed reports and the original implementation plan.

## Interactive editor checks

Computer Use screenshots were captured and inspected in the implementation sessions, but were not saved as separate repository files. Gate 3 confirmed photo and GoPro import, upright display, changing video playback frames, Easy/Advanced delta persistence, cross-mode undo/redo, export presets, GUI photo/video exports, overwrite prompt, and close/quit prompt choices. The initial GUI pass found two failures: Close & Keep Edits did not complete the close/quit, and a completed video export appeared on a later photo's export sheet.

The 2026-11-02 refinement pass reproduced the old close failure, then confirmed the corrected **Close & Keep Edits** path terminated on `⌘Q`; reopening restored the selected photo and its non-destructive values. Closing the original window also completed. A fresh photo export sheet after video selection showed no stale completion/Finder action. Screenshots showed Photo/Global/Easy, Photo/Global/Advanced/Color Mixer, Photo/Masks, and upright GoPro video. The Masks tab with overlay hidden retained the visible global grade. The eight mixer swatches and Green's saved H/S/L values, Water Color endpoint labels, scoped reset icons, and loaded photo/video thumbnails were visible. Creating an inverse subject mask produced a separate selected mask with neutral local values; the verification-only copy was removed with Undo. The zoom control visibly enlarged the photo and reported `1.3× Fit`.

## Open checks and limits

- Computer Use coordinate scroll, click, and drag returned `noWindowsAvailable` despite working accessibility clicks and screenshots. **Wheel zoom, pointer anchoring, drag-to-pan, and image updates before mouse-up remain unverified interactively.** Manually check these on a photo, including rapid back-and-forth dragging and one undo step per drag.
- The new radial angle control and independent inverse brush edits passed automated math/render/serialization checks, but their full GUI edit/reopen/export flows were not repeated. The hue color transition appears below the native slider track, not inside it.
- The final refinement was not exported again through the GUI. Automated photo/GoPro output checks passed; after the player-item composition change, GoPro playback displayed and Play was pressed, but advancing frames were not conclusively observed in that pass.
- HDR mastering, RAW-specific processing, video subject masks, multi-clip timelines, App Store sandboxing/signing, and a macOS 15 runtime check remain outside the verified MVP. Automatic Vision subject quality is scene-dependent; the manual photo brush remains available.
- A long endurance/memory-growth test has not been run; the existing suite covers repeated short media operations and fixture-driven exports.
