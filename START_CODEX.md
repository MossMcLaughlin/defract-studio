# START_CODEX.md — Efficient first build on your Mac

**Recommended environment:** Use the local Codex desktop app or Codex CLI, opened at this extracted folder on an Apple Silicon Mac with Xcode installed. Prefer local over cloud for the initial build so the agent can run `xcodebuild`, launch the native UI, inspect media, and verify actual exports. Sign in with your ChatGPT account rather than an API key when you intend to use included subscription usage. The agent does not need the prior ChatGPT conversation: all requirements are in this package.

## Paste this as the first Codex task

> Build the native macOS Photo & Video Editor MVP described in this repository. Read `AGENTS.md` and `README.md` first, then consult their referenced specification files as needed. Use the supplied test media locally, including verified 10-bit SDR `GX011247.MP4`. Implement end-to-end through `IMPLEMENTATION_PLAN.md` gates, keeping each gate buildable and verifying tests and real exports before continuing. Prefer minimal maintainable Swift and native frameworks; avoid unnecessary dependencies and features. Keep private fixture media out of Git. Maintain `VERIFICATION_REPORT.md` with actual commands/results and create concise commits at successful gates. Do not claim success on untested UI/video workflows; disclose blockers accurately. Proceed without routine confirmations, but request approval before risky/destructive operations.

## Avoid wasted usage

- Begin with **one agent** and the normal/default or GPT-6.1 Sol setting available to your account. No parallel autonomous subagents unless a test proves a need.
- Do not paste every document into the initial prompt: the agent can read files locally when it needs them.
- Let builds, media probing and automated tests provide concrete feedback; avoid repeated long speculative design responses.
- Maintain small checkpoint commits and a short `VERIFICATION_REPORT.md` so you can resume from disk without restating the entire project.
- If the build stops due to usage or SDK issues, resume the same local repository and ask for the **next failing checkpoint**, not an entirely new project.
- Only escalate to a higher-cost or higher-reasoning model for specific difficult debugging or architecture failures.

## Before running the task

Check Xcode can launch and `xcodebuild -version` works, then extract **the full-media ZIP** into a normal development directory. Keep all sample files in `test_media/` (gitignored). The user-provided photo/video assets may contain people and location metadata; they are for local tests only, not for GitHub or public demo collateral.

When the agent completes a gate, review the checkpoint summary. The initial human verification can be brief: open the app, try a photo grade and a video export, and send specific issues back to Codex for repair.
