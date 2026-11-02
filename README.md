# Photo & Video Editor — Agent Handoff v1.1

**Status:** Implementation-ready, subject to platform feasibility checks.  
**Date:** 2026-11-02  
**Platform:** macOS 15+ on Apple Silicon; future iPhone app is desirable but not in scope for v1.  
**Goal:** Build a small, genuinely usable, local-first editor with unusually good engineering, not a Lightroom/DaVinci clone.

## Start here

The coding agent must read, in order:

1. **`AGENTS.md`** — binding instructions, priorities, milestones, and failure/reporting rules.
2. **`PRODUCT_MVP.md`** — scope and actual user journeys.
3. **`UX_SPEC.md`** — screens and precise interactions.
4. **`COLOR_ENGINE.md`** — parameter contract and deterministic provisional underwater mappings.
5. **`ARCHITECTURE.md`** — source code boundaries, local persistence, masks, performance and color management.
6. **`MEDIA_AND_TESTS.md`** — real supplied media, test roles and acceptance gates.
7. **`IMPLEMENTATION_PLAN.md`** — implementation order, definitions of done and deliverables.
8. **`TEST_MEDIA_SETUP.md`** — locations and verified metadata for the three GoPro videos, including 10-bit SDR.
9. **`REFERENCES.md`** — official APIs and supporting editorial guidance.

Older working documents in `reference/` are **background only**. This v1.1 handoff overrides previous inconsistent ideas. `reference/UI_REFERENCE.png` is the approved approximate visual design, not pixel-perfect source code. No name or logo is required.

## Key decisions

- One editing workspace; equal-priority photo and single-video-clip grading.
- Small, fully collapsible thumbnail/file sidebar; large preview; right editing inspector.
- Standard Advanced color controls plus four provisional Underwater Easy sliders.
- Effective parameter = Easy base + Advanced delta; switching tabs never changes output.
- Full per-color HSL mixer; smooth green → cyan → blue adjustments are important.
- Photos: automatic foreground selection **best effort**, brush add/erase, feather, inverse, radial and linear masks.
- Video: **static radial and linear masks only**. No subject segmentation or object tracking.
- Local inputs and exports, no cloud/LLM/service requirement, no timeline, no batch export.
- Source files are immutable. Edits and a bounded undo history are autosaved as project metadata; previews are disposable caches. Export produces a separate output file.
- iOS later: share rendering and edit model code, not macOS windows or file APIs.

## Handoff usage

Extract this directory into a **local working folder on your Mac**. The full-media archive already contains five photo fixtures plus **three GoPro videos**, including the verified 10-bit sample. The lightweight archive contains only photos; manually add its videos using `TEST_MEDIA_SETUP.md`. For the coding agent, use the short task in `START_CODEX.md` (included), which points to this repository-local specification instead of pasting enormous documents.

> Implement the macOS photo/video editor described by this handoff. Read `AGENTS.md` first, then referenced specifications as needed, and work through the verified implementation checkpoints. Report actual test results and unresolved limitations. Do not silently cut required features or replace functionality with mockups.

**Note:** This package does not contain a runnable macOS build. It is a build specification for a coding agent working on a Mac with Xcode. Its numerical underwater mappings are starting hypotheses, not validated underwater color science.

**New in v1.1:** verified `GX011247.MP4` as HEVC Main 10 (10-bit) Rec.709 SDR; added its fixture role and specific acceptance tests. This does **not** establish HDR input/export support.
