# AGENTS.md — Binding Implementation Instructions

You are building a practical, local-first **native macOS photo and single-clip video editor**. Read every specification in `README.md` before coding. Implement with disciplined simplicity, objective self-verification, and a strong bias toward completed working features over elegant but untested abstractions.

## Priorities (in order)

1. Correct media interpretation, preview and export; originals untouched; no lost edit metadata.
2. Genuinely responsive shared photo/video color grading and required masks.
3. Agreed UX, easy/advanced behavior, output framing and non-destructive persistence.
4. Modest, idiomatic, maintainable Swift code and easily repeatable tests.
5. Polish; do not spend early work on unsupported features, elaborate branding or premature optimization.

## Mandatory engineering rules

- Target macOS 15+ Apple Silicon; Swift / SwiftUI / Core Image / AVFoundation / Vision / ImageIO / Metal where necessary. No third-party runtime packages without measured need. Use AppKit only for desktop-specific components/behaviors where SwiftUI is insufficient.
- Core edit models, color math, mask math and renderer must **not** import AppKit or depend on macOS window controls; keep them portable enough for a future iPhone app. Do not attempt an iOS app now.
- Prefer one Xcode app target plus one shared core module/package and a test target. Avoid an elaborate plugin architecture, DI container, architecture framework, speculative repositories, and redundant wrappers.
- One canonical edit recipe, renderer and export path. Photo and video share the same adjustment evaluation. For media-specific processing, use thin adapters.
- Rendered preview frames and caches are disposable; never save edited copies into originals, even temporarily. Write exports to temporary output and commit on success.
- Implement visible controls fully or hide them; no fake slider behavior, unsupported formats, placeholder export buttons or misleading “dehaze” labels.
- Make rendering parameter values deterministic. Easy curve updates change only their base contribution; manual Advanced changes are stored as delta; effective = base + delta. Store both terms and the effective values through serialization tests.
- Never use an automatic mask result as the only possible selection path. Preserve user brush correction and source-aligned mask data. No video subject mask.
- Use current SDK APIs: check Xcode availability, warnings and official documentation. **Do not call a macOS 26-only API unguarded when targeting macOS 15.** Check availability of `AVVideoComposition.init(applyingFiltersTo:applier:)` (introduced in the 26 SDK family); use a supported older composition API for macOS 15–25 when required, even if deprecated by the newest SDK. Keep the compatibility branch minimal and test actual preview/export behavior. Do not suppress necessary compatibility warnings dishonestly.
- Specifically verify `GX011247.MP4` (HEVC Main 10, 10-bit Rec.709 **SDR**) for correct decoded color, portrait orientation, adjusted preview/export and audio. Do not call this an HDR sample. Do not use raw, guessed color-space transforms. Honor metadata, sRGB/Rec.709 SDR output, orientation and permitted HDR tone mapping. If a file cannot be safely processed, explain the limitation rather than silently grading it wrong.
- Add small, relevant automated tests for state, curves, masks, geometry, file IO, undo and media output. Test with actual supplied fixtures. Every checkpoint builds cleanly before proceeding.
- Keep comments and documentation focused on **why** decisions were made. Avoid excessive generated scaffolding, files, comments, logging, and fallback branches.
- Never claim tests passed unless invoked and verified on the machine. If GUI or signing cannot be checked, label that explicitly.

## Workflow: one handoff, many internal checkpoints

Implement in the sequence in `IMPLEMENTATION_PLAN.md`. You may make independent routine engineering choices and fix failures without requiring human approval. At each checkpoint: compile; run focused tests; capture known limitations; commit or otherwise checkpoint a buildable state. If a platform limitation blocks a requirement, implement the simplest viable alternative without dropping the feature silently, and document the tradeoff. Prefer completion over stopping for nonessential decisions.

## Required final delivery

- Launchable Xcode project, reproducible build instructions and a clearly identified app entry point.
- Real functionality for all MVP requirements (subject ML best effort, with manual fallback always working).
- `README.md` for users, `DEV_NOTES.md` for maintainers, tests, and `VERIFICATION_REPORT.md` with exact build/test commands and outcomes, tested media, known issues, and any feature shortfall.
- A concise summary of directory layout and where to change color mappings, UI style tokens and export presets.
- No secrets, API keys, external service dependencies, external analytics or uploads.

## Definition of failure

A static SwiftUI mockup, successful compilation alone, a non-working export, a preview that does not match output, editing a duplicated source as if original, lost mask refinement on reopen, or ignored video rotation does **not** meet acceptance. Do not describe those as a finished MVP.
