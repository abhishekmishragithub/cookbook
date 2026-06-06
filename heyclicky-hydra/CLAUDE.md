# HeyClicky × Hydra — agent handoff

> Read this first. State + next steps so a fresh session continues without the
> original chat.

## What this is
A **hands-free voice agent that runs your Mac** (Farza's latest Clicky demo),
powered by **smallest.ai Hydra** (native full-duplex speech-to-speech) instead
of GPT-Realtime. You talk; it opens apps, plays music, sets volume, opens URLs,
sets reminders, checks calendar, starts background work, and **orders food on
Swiggy** — and talks back. You can interrupt it mid-sentence.

Read: `README.md` → `docs/DEMO_SCRIPT.md` → `docs/PHASES.md` →
`docs/SAFETY.md` → `docs/INTEGRATION.md` → `docs/HYDRA_CONTRACT.md`.

## Architecture
Hydra runs the full-duplex voice loop and emits OpenAI-Realtime-style function
calls. The Swift `ActionRouter` (`macos/.../Actions.swift`) executes them via
`osascript` / `NSWorkspace` / EventKit. `order_food` delegates to a Node +
Playwright sidecar (`swiggy-agent/`) driving the user's logged-in Swiggy.

## Direction note (important)
An earlier build targeted the *older* open-source `farzaa/clicky` — a screen
**tutor** that points at UI (Gemini vision + pointer). The product is now the
**voice-OS-agent** above. The tutor pieces still exist and work (`web/` pointing
demo, `vision/`, Worker `/vision`+`/tutor`, `SceneGraph.swift`/`VisionLoop.swift`)
but are **unwired** from the current Orchestrator — optional "look at my screen".

## What's done
- **Hydra protocol verified** against `smallest-inc/hydra_agents` (see
  `docs/HYDRA_CONTRACT.md`). `web/hydra.js` is a working browser Hydra client.
- `prompts/` — voice-OS-agent persona + 8 action tools (`prompts/tools.json`).
- `macos/HydraClicky/` — Swift app core: `HydraClient` (real protocol),
  `Orchestrator` (voice ⇄ actions), `Actions.swift` (the ActionRouter),
  `Collaborators` (mic/player protocols). **Does NOT compile here — needs Xcode.**
- `swiggy-agent/` — Playwright ordering sidecar, confirm-gated (parses clean).
- `web/`, `worker/`, `vision/` — runnable; browser Hydra voice tester works.

## What's NOT done (next, in order)
1. Verify the browser Hydra demo with a live smallest.ai key (mic/audio/barge-in).
2. Fork `farzaa/clicky`; build in Xcode (`docs/INTEGRATION.md`).
3. Implement/verify each action on a Mac (Phase 2 — perms prompts expected).
4. Swiggy: run sidecar, log in, tune `SELECTORS`, test cart→confirm→place.

## Constraints
- This cloud session is Linux (no Xcode) — Swift must be built on a Mac. Author
  can't run osascript/Playwright here either; logic is written, needs Mac to run.
- `order_food` is double-gated (confirm flag + env) — never auto-pays. See SAFETY.

## Run the browser voice tester
`cd web && python3 -m http.server 8080` → localhost:8080 → pick a source → paste
smallest.ai key → Connect Hydra.
