# HeyClicky × Hydra — agent handoff

> Read this first. It's the state + next steps so a fresh Claude Code session
> (or a human) can continue without the original chat.

## What this is
A reimagining of Farza's open-source [Clicky](https://github.com/farzaa/clicky)
(an on-screen AI tutor for macOS) with the 3-stage voice pipeline
(AssemblyAI + Claude + ElevenLabs) replaced by **smallest.ai Hydra**, a native
full-duplex speech-to-speech model, paired with **Gemini** for screen grounding.

Read in order: `README.md` → `docs/DEMO_SCRIPT.md` → `docs/PHASES.md` →
`docs/INTEGRATION.md` → `docs/HYDRA_CONTRACT.md`.

## Architecture (one line)
Hydra runs the full-duplex voice loop and emits *semantic* tool calls
(`point_at("Export button")`); a parallel Gemini vision loop turns screenshots
into a scene-graph; the orchestrator resolves label→pixel coords and drives a
pointing overlay. Voice never blocks on vision.

## What's done
- `web/` — runnable browser demo (zero-setup demo mode + live screen-capture mode).
- `worker/` — Cloudflare Worker: `/hydra` WS passthrough, `/vision`, `/tutor`. Typechecks clean.
- `vision/scene_graph.mjs` — screenshot → scene-graph harness (has `--mock`).
- `prompts/` — Hydra tutor persona + tool defs.
- `macos/HydraClicky/` — Swift orchestrator scaffold (does NOT compile here; needs Xcode).

## What's NOT done (next steps, in order)
1. **Fill `docs/HYDRA_CONTRACT.md`** with the real Hydra endpoint / auth / audio
   format / tool-calling schema. Everything downstream depends on this.
2. **Phase 0 spike**: minimal Swift mic→Hydra→speaker to prove barge-in feels
   great. (See `docs/PHASES.md`.)
3. Phases 1–4: wire Hydra + Gemini into a `farzaa/clicky` fork per
   `docs/INTEGRATION.md`.
4. Phase 5: real-world actions (Spotify / YouTube / Airbnb / booking) via MCP
   tool calling — generalize `BookingMCP` → `ActionRouter`.

## Constraints learned
- Original cloud session was Linux (no Xcode) — Swift app must be built on a Mac.
- The Hydra wire protocol is the only true unknown; isolated in `HydraClient.swift`
  + the Worker passthrough so filling it in doesn't ripple.

## Run locally
See `README.md` "See it now" and `web/README.md`. TL;DR:
`cd web && python3 -m http.server 8080` → open localhost:8080 → "Use demo screenshot".
