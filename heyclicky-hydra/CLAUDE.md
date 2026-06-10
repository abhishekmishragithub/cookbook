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
- `macos/HydraClicky/` — **clean SwiftUI menu-bar app** (no clicky fork needed):
  `HydraClickyApp.swift` (MenuBarExtra + AppState + UI), `Orchestrator` (voice ⇄
  actions + UI state), `HydraClient` (real protocol), `Actions.swift`
  (ActionRouter), `Mic.swift` (AVAudioEngine → PCM16 16k), `Player.swift`
  (gapless PCM16 24k + flush), `Prompts.swift` (persona+tools inline),
  `Collaborators` (protocols). **Needs Xcode to build — see `SETUP.md`.**
- `SETUP.md` — full local runbook (build the Xcode menu-bar app, perms, Swiggy).
- `swiggy-agent/` — Playwright ordering sidecar, confirm-gated (parses clean).
- `web/`, `worker/`, `vision/` — runnable; browser Hydra voice tester works.

## What's NOT done (next, in order)
0. **App BUILDS and runs** (Xcode via `xcodegen generate`). Not yet verified
   live end-to-end. Start here: run it, click Start listening, debug the real
   Hydra connection + mic capture (`Mic.swift`) + playback (`Player.swift`) +
   barge-in. Audio is the least-tested code.
1. Verify each action live on the Mac (expect Automation/Calendar/Mic permission
   prompts): open_app, open_url, play_music, set_volume, set_reminder,
   check_calendar, start_background_agent.
2. Swiggy: `cd swiggy-agent && npm install && npx playwright install chromium`,
   `node server.mjs`, `/login` once, then tune `SELECTORS` against the live DOM.
   Test cart→confirm→place with the double safety gate (see docs/SAFETY.md).
3. Polish + record the demo (docs/DEMO_SCRIPT.md).

## Constraints
- This cloud session is Linux (no Xcode) — Swift must be built on a Mac. Author
  can't run osascript/Playwright here either; logic is written, needs Mac to run.
- `order_food` is double-gated (confirm flag + env) — never auto-pays. See SAFETY.

## Run the browser voice tester
`cd web && python3 -m http.server 8080` → localhost:8080 → pick a source → paste
smallest.ai key → Connect Hydra.
