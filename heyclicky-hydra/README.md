# HeyClicky × Hydra

An AI tutor that lives next to your cursor — sees your screen, talks to you in
real time, and points at things. A reimagining of
[Clicky](https://github.com/farzaa/clicky) (Farza Majeed, MIT) with the
**3-stage voice pipeline replaced by [Hydra](https://smallest.ai/speech-to-speech),
smallest.ai's native full-duplex speech-to-speech model.**

## Why this is different from the original Clicky

Original Clicky stitches three systems together:

```
mic ─► AssemblyAI (STT) ─► Claude (LLM) ─► ElevenLabs (TTS) ─► speaker
```

This version uses a single native speech-to-speech model for the whole voice
loop, paired with a vision model for screen grounding:

```
mic ⇄ Hydra (full-duplex S2S)  ─ sub-300ms, barge-in, emotional voice
        │  tool calls (point_at / highlight / look / book_flight…)
        ▼
   ORCHESTRATOR  ── resolves semantic labels ─► pixel coords
        ▲
screen ─► Gemini (vision, ~1–2 fps) ─► scene-graph {label, bbox, desc}
        │
        ▼
   blue-cursor overlay animates to the target
```

**The demo hook:** you can interrupt Hydra mid-sentence and talk over it — it
keeps listening while it speaks. That full-duplex feel is the thing a stitched
STT→LLM→TTS pipeline can't do.

## Design principles

- **Voice reasoning lives on Hydra; pixel grounding lives on Gemini.** Hydra
  never sees raw coordinates. It calls `point_at("Export button")` and the
  orchestrator resolves that label against Gemini's latest scene-graph. The two
  loops run concurrently so vision never blocks voice.
- **Keys never ship in the app.** A Cloudflare Worker proxies both Hydra and
  Gemini (mirrors the original Clicky `worker/` pattern).
- **The Hydra wire protocol is isolated in one place** (`worker/` passthrough +
  `macos/.../HydraClient.swift`). Fill in the endpoint/format/auth and nothing
  else changes.

## See it now (no Mac, no keys)

A browser demo proves the screen-aware + pointing experience today, using Gemini
as the brain and browser speech as a Hydra stand-in:

```bash
cd web && python3 -m http.server 8080   # open http://localhost:8080
```
Click **▶️ Use demo screenshot**, ask "how do I export?", watch Clicky point.
(Demo mode needs zero setup; live mode uses real screen capture + your Worker.)

## Layout

| Path | What it is | Runnable here? |
|------|-----------|----------------|
| `web/`      | Browser demo: screen-aware pointing + voice (Hydra stand-in) | ✅ static server |
| `worker/`   | Cloudflare Worker: Hydra WS passthrough + Gemini `/vision` + `/tutor` | ✅ `wrangler dev` |
| `vision/`   | Node harness: screenshot → Gemini → scene-graph JSON (has mock mode) | ✅ `node` |
| `prompts/`  | Hydra tutor system prompt + tool definitions | n/a |
| `macos/`    | Swift orchestrator scaffold to drop into a `clicky` fork | ⚠️ needs Xcode/Mac |
| `docs/`     | Demo script, integration guide, Hydra API contract, build phases | n/a |

The thing that makes it stand out is in **`docs/DEMO_SCRIPT.md`** — lead with
barge-in (interrupting it mid-sentence), point-while-talking, and proactive help.

## Status

This is built in phases (see `docs/PHASES.md`). The Mac app is meant to be a
**fork of `farzaa/clicky`** with the voice layer swapped — `macos/` holds the
new files plus a migration guide for what to remove from the original.

Start here: **`docs/INTEGRATION.md`** and **`docs/HYDRA_CONTRACT.md`**.
