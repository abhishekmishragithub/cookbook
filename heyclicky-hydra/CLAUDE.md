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
- **Hydra protocol is REAL/verified** against `smallest-inc/hydra_agents`
  (OpenAI-Realtime style; see `docs/HYDRA_CONTRACT.md`). No longer assumed.
- `web/hydra.js` — full browser Hydra client (mic@16k → WS → playback@24k,
  barge-in, tool calling) ported from the reference app.
- `web/` — browser demo with **real Hydra mode** (key + screen → voice + screen
  context + pointing) and a keyless Gemini/browser-voice stand-in mode.
- `worker/` — Cloudflare Worker: `/hydra` WS passthrough (real endpoint +
  api_key query param), `/vision`, `/tutor`. Typechecks clean.
- `vision/scene_graph.mjs` — screenshot → scene-graph harness (has `--mock`).
- `prompts/` — Hydra tutor persona + tool defs.
- `macos/HydraClicky/` — Swift orchestrator scaffold, `HydraClient.swift` now
  matches the real protocol (does NOT compile here; needs Xcode).

## What's NOT done (next steps, in order)
1. **Verify the real Hydra browser demo** end-to-end with a live smallest.ai key
   (mic perms, audio in/out, barge-in, point_at). Logic is in place; needs a
   human with a key + mic. This is the fastest path to a showable demo.
2. **Phase 0 spike (native)**: minimal Swift mic→Hydra→speaker on a Mac to
   confirm the same feel natively. (See `docs/PHASES.md`.)
3. Phases 1–4: wire Hydra + Gemini into a `farzaa/clicky` fork per
   `docs/INTEGRATION.md` (HydraClient.swift already matches the real protocol).
4. Phase 5: real-world actions (Spotify / YouTube / Airbnb / booking) via MCP
   tool calling — generalize `BookingMCP` → `ActionRouter`.

## Constraints learned
- This cloud session is Linux (no Xcode) — the native Swift app must be built on
  a Mac. The **browser demo (`web/`) needs no Mac** and uses real Hydra.
- Hydra protocol = OpenAI-Realtime style, verified from the reference repo;
  isolated in `web/hydra.js`, `HydraClient.swift`, and the Worker passthrough.

## Run locally
See `README.md` "See it now" and `web/README.md`. TL;DR:
`cd web && python3 -m http.server 8080` → open localhost:8080 → "Use demo screenshot".
