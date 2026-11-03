# Verification report

## Environment

- Gate 0 verified on 2026-11-02: macOS 26.5.2, Apple M1 MacBook Pro, Xcode 26.6 (17F113), macOS SDK 26.5, deployment target macOS 15, arm64.
- Xcode first-launch components were initially missing. `xcodebuild -runFirstLaunch` completed successfully after authentication. macOS builds and tests then ran. Xcode emits CoreSimulator service diagnostics in this environment, but the macOS build and tests complete.

## Gate 0 — PASSED for technical feasibility

Build command:

```sh
xcodebuild -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO build
```

Result: **PASSED** (`BUILD SUCCEEDED`). The built app launched and its process stayed running after the framework install path was corrected. A screenshot could not be captured (`screencapture: could not create image from display`), so interactive window appearance and keyboard responsiveness are **NOT TESTED**.

Test command (the macOS XCTest runner required execution outside the repository tool sandbox to reach `testmanagerd`):

```sh
xcodebuild -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO test
```

Result: **PASSED**, 5 tests, 0 failures. Tests cover neutral renderer identity, grade serialization, real JPEG export, real 10-bit HEVC preview-frame generation and export, portrait orientation, audio-track retention, Rec.709 tags, original-file hashes, and a Vision foreground-instance trial on two photos. The Gate 0 video preview/export mean RGB difference sampled over a 64-point grid was **0.00766** (normalized per channel); this is a sampled parity check, not a full color-science evaluation.

`P8110319.JPG` is 1536×2048 sRGB with no orientation property reported by `sips`; edited JPEG export retained 1536×2048. `GX011247.MP4` is HEVC with `BitsPerComponent = 10`, Rec.709 primaries/transfer/matrix, full range, a 90-degree display transform, and audio. The Gate 0 exporter produced portrait H.264/AVC Rec.709 MP4 with an audio track. This compatibility output is an intentional 8-bit SDR downconversion from the 10-bit SDR source; HDR behavior is **NOT TESTED**. Vision returned one foreground instance on both `P8110319.JPG` and `B663700C-50E6-4C26-B95F-25C7E5F271E9.JPG`; mask quality was not judged.

The source SHA-256 values remained `ae79f0c6e0397a239d32600d4dee956a2630b1aef374c3afb2bb9ef46845ab5f` for the photo and `a866aa69ce361bf11e3880cada91396e1e955532b10adb01ccf3c247cc47c288` for the 10-bit video. Private fixtures were removed from Git tracking but remain on disk.

## Remaining gates

- Gate 1: **PASSED for implemented global editing path**, 2026-11-02. The same build/test commands above completed (`BUILD SUCCEEDED`, `TEST SUCCEEDED`, 11 tests, 0 failures) after Gate 1 changes. The rebuilt app launched as a new process. Tests covered the versioned base/delta/effective recipe round-trip, all math controls on representative pixels, actual white-balance pixel changes, deterministic Easy knot interpolation and Green hue direction, bounded undo/redo and atomic reopen, portrait/landscape crop geometry, real 4:5 cropped JPEG preview/export parity, and the 10-bit video grade/export parity. The full global inspector, file list, autosave, shortcuts and before/after are implemented; their interactive UX remains **NOT TESTED** because this session could not capture or control the visible display. Photo crop currently offers aspect and position controls; draggable edges, rotate and straighten remain Gate 2.
- Gate 2: **PASSED automated/integration checks**, 2026-11-02. The exact build/test commands above completed (`BUILD SUCCEEDED`, `TEST SUCCEEDED`, 21 tests, 0 failures). `P8110319.JPG` and the diver photo produced Vision mattes saved as PNG; an erased brush correction and local grade survived serialization. A real brush mask on `P7310233.JPG` exported with sampled preview/export parity and unchanged source hash. Core tests covered mask inversion/edges, local-only blending, source-coordinate mapping through crop/straighten/quarter rotation, Free/fixed crop, and Fit/Fill without stretching. `GX011123.MP4` and `GX011176.MP4` (opposing rotation signs) exported upright 9:16 MP4 with audio. `GX011247.MP4` exported as trimmed 4:5 H.264 Rec.709 with a static linear gradient, 10-bit source metadata confirmed, stereo audio retained, and mean sampled preview/export RGB difference 0.00358. The same clip also exported as rotated landscape HEVC with Rec.709 tags and audio. Fit and Fill each exported an exact 1080×1920 frame, differed visually as expected, and matched their respective preview frames. The canvas crop and gradient handles are implemented, but interactive dragging and appearance remain **NOT TESTED** because GUI capture/control is unavailable in this session.
- Gate 3: **PASSED automated/integration checks**, 2026-11-02. The final commands below completed successfully with **26 tests, 0 failures, 0 skips**. The app launched from the rebuilt bundle and its process remained running. The export sheet implements Instagram, General, and Maximum Quality presets, frame aspect, Fit/Fill, dimensions, JPEG/PNG or H.264/HEVC, file name and folder, overwrite confirmation, progress/cancel, and Show in Finder. Tests verified 1080×1350 Instagram PNG, explicit overwrite with changed pixels, rejection without overwrite, unsafe file-name rejection, model export completion and reopened state, cancellation of a real `GX011247.MP4` export with no output or temporary file, and corrupt-session recovery without deleting the bad file. `image.png` exported upright at 638×1130 with alpha and an unchanged source checksum. Earlier Gate 2 checks still pass for the deep-blue, diver, ordinary photo, and all three GoPro fixtures.

Final Gate 3 commands:

```sh
xcodebuild -quiet -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project EditorApp.xcodeproj -scheme EditorApp -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/defract-derived CODE_SIGNING_ALLOWED=NO test
open -n /private/tmp/defract-derived/Build/Products/Debug/EditorApp.app
```

The final test result bundle is `/private/tmp/defract-derived/Logs/Test/Test-EditorApp-2026.11.02_18-00-38--0500.xcresult`; `xcresulttool get test-results summary` reported `Passed`, 26 passed tests. `screencapture -x /private/tmp/defract-gate3.png` failed with `could not create image from display`. Therefore the export sheet, close/quit dialog, drag handles, live playback, keyboard behavior, visual layout, and QuickTime GUI playback remain **NOT TESTED interactively**. The automated AVFoundation tests verify output decodability, geometry, color tags, sampled preview parity, codec, trim and audio. No calibrated-display color evaluation or HDR input/export test was performed. The code supports macOS 15 deployment but the execution machine ran macOS 26.5.2; an actual macOS 15 runtime test remains **NOT TESTED**.

The session's first Gate 3 full run had one test-only assertion failure because macOS returned the same temporary URL as `/private/var` while the assertion expected `/var`. The test now compares standardized paths. The next full run passed 26/26. Xcode emitted CoreSimulator connection and plist-detector diagnostics, but no app source compiler warnings or build failure. Photo/video exports remain SDR; the 10-bit Rec.709 source is deliberately delivered as SDR. Missing sources require manual relinking. The unsandboxed Debug app is not prepared for App Store distribution.

Repository media note (resolved by owner clarification): `test_media/` is ignored and absent from the current Git index. The initial `0a3adf3` commit retains the fixtures in history by choice; they are not private or sensitive. Keep local fixtures and do not rewrite history. Future commits should continue excluding large media files.

## Gate 3 interactive GUI pass — 2026-11-02

Computer Use connected to the editor after macOS permission was granted. Screenshots were captured in the Computer Use session but were not saved as separate files. This section supersedes the earlier "NOT TESTED interactively" statements for the specific flows below. No app source was changed during this pass.

**Confirmed:** `IMG_3635.jpeg` imported and displayed upright; `GX011247.MP4` imported upright and played from 0 to 3.5 seconds with visibly changing frames. On the video, Water Color 51, Color Recovery 41, Light 21/41, and Visibility 31 changed the preview. Advanced Exposure changed from the Easy base 0.147 to 0.719; changing Easy Light 21 to 41 then changed effective Exposure to 0.859, preserving the ~0.572 manual contribution. Cross-tab Undo returned Exposure to 0.719 then 0.147; Redo restored 0.719 and Easy Light 41. Switching files preserved a separate photo Light 41 edit. At the minimum-sized visible window, the inspector scroll exposed bottom controls; no overlapping or unreachable controls were observed. The long diver filename was truncated in the narrow sidebar but the full name appeared over its preview.

**Export:** The video sheet exposed Instagram, General and Maximum Quality; Instagram changed Original to 1080×1920 and 4:5 Feed to 1080×1350. Fit and Fill options were selectable. A GUI H.264 export completed as `~/Movies/PhotoVideoEditor/Exports/GX011247-gui-check.mp4` (1.3 MB), with progress and a completion message. Re-exporting the same name prompted for replacement; Cancel returned to the sheet. The photo sheet offered JPEG and PNG; `IMG_3635-gui-check.png` exported at 1536×2048 (5.4 MB) in the Pictures export folder. The active sheet could be inspected, but Computer Use did not show the preview behind the sheet, so live framing-preview parity was **NOT TESTED visually**. `ffprobe` was unavailable; prior AVFoundation integration tests remain the media metadata evidence.

**Failures:** After switching from the completed video export to the photo, the photo export sheet still showed `Export complete: GX011247-gui-check.mp4` and Show in Finder for that prior video. Clear the last-export display when selecting another source or opening a new export sheet. With an unexported photo edit, Close and ⌘Q both showed the correct Export / Close & Keep Edits / Cancel prompt. Cancel retained the window and edit; Export opened the export sheet. Choosing **Close & Keep Edits** dismissed the prompt but left the same window open for both Close and Quit; the prompt reappeared on the next attempt. The likely fix is to schedule `performClose` after the alert sheet finishes dismissing, then verify the quit continuation. Reopen-after-Keep was **NOT TESTED** because the window did not close.
