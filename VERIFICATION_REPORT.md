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
- Gate 2: **NOT TESTED / NOT COMPLETE** — manual/photo masks, static video gradients, complete geometry, trim, all three GoPro exports.
- Gate 3: **NOT TESTED / NOT COMPLETE** — preset UI, progress/cancel, close prompts, accessibility and final handoff.

Known Gate 0 limitations: the visible app has only exposure and saturation; video interactive playback could not be verified in headless XCTest (`AVPlayer.currentTime` did not advance there), though composition frame generation and export succeeded. JPEG and MP4 output color was checked by metadata and sampled frames, not a calibrated display. UI screenshot capture was unavailable in this session.
