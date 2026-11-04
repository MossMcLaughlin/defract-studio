# Agent instructions

Defract Studio is a local-first native macOS photo and single-clip video editor. The user handles product design and UX decisions separately. Implement approved product requirements and behavioral contracts. Treat proposed algorithms, coefficients, and internal architecture as engineering guidance unless explicitly marked mandatory. Choose efficient, maintainable implementations independently, documenting material deviations. Do not independently redesign the product or add adjacent features.

## Start each implementation task

1. Check Git status and read `.handoff/current/` for the current task and any temporary reference assets. If that directory is empty, use the user's direct request.
2. Read only the relevant current documentation: `README.md` for setup and navigation, `PRODUCT_MVP.md` for scope, `UX_SPEC.md` and `reference/STYLE_GUIDE_v0.1.md` for approved interaction and visual direction, `COLOR_ENGINE.md` for color behavior, `DEV_NOTES.md` for the actual implementation, `MEDIA_AND_TESTS.md` for fixtures, and `VERIFICATION_REPORT.md` for current status. Consult Git history for older decisions when needed; do not repeatedly process retired specifications.
3. Resolve routine engineering choices independently. Clarify only a genuine product ambiguity, blocker, or risky operation. Preserve unrelated work and local media. Keep reads, tool output, and documentation focused to avoid repeatedly spending time on historical material.

## Engineering rules

- Target macOS 15+ on Apple Silicon. Use Swift, SwiftUI, Core Image, AVFoundation, Vision, ImageIO, and AppKit only where desktop behavior needs it. Add no third-party runtime dependency without a demonstrated need.
- Keep `EditorCore/` independent of AppKit and window controls. Use one canonical edit recipe and shared color/mask renderer for photo and video, with thin media adapters. Preserve source orientation, color metadata, audio, and original files. Export to a temporary file and commit on success.
- Easy controls contribute a deterministic base; Advanced manual changes are deltas; effective values are base plus delta. Preserve both terms, source-aligned masks and brush corrections, undo history, and backward-compatible project data. Automatic subject selection must always have a manual photo brush fallback; video masks remain static gradients.
- Performance is a primary design constraint. Reuse existing processing and analysis infrastructure, profile meaningful bottlenecks before optimizing, and avoid expensive new rendering passes unless the visual benefit justifies their cost. Preserve responsive editing, efficient video playback, and full-quality exports.
- Keep adaptive source analysis, Easy calibration, and pixel rendering as separate responsibilities. Analysis should be bounded, cached, source-aligned, and reproducible; video adaptation should use stable per-clip or per-trim results rather than per-frame recalculation. Preserve zero neutrality, versioned mapping behavior, existing Advanced deltas, and historical project appearance.
- Keep source and tests modest. Implement visible controls fully or hide them. Avoid architecture rewrites, speculative abstractions, fake behavior, and unsupported media claims. Never call a macOS 26-only API unguarded on the macOS 15 deployment target. The supplied `GX011247.MP4` is **10-bit HEVC Rec.709 SDR**, not HDR.
- Keep `test_media/`, exports, and build products out of future commits. The local fixtures are development data, not material to purge; do not rewrite Git history. Do not add analytics, accounts, uploads, secrets, or external services.

## Finish each task

Build and run focused/full Xcode tests after meaningful changes. Use real supplied fixtures and actual app interaction where the task requires UX verification; distinguish tested results from assumptions. Keep the repo buildable at checkpoints and commit only task-related, verified changes when appropriate.

After success, update affected canonical documentation and the current status in `VERIFICATION_REPORT.md`. Keep reports concise instead of accumulating per-task duplicates. Temporary handoff files may be cleared **only after** their lasting decisions are incorporated into canonical documents and verification succeeds; otherwise leave them for continuation. `.handoff/` is ignored by Git, so any decision needed by future contributors must also be written in tracked documentation. Report unresolved issues precisely.
