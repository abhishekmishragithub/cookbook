# HeyClicky × Hydra

A **hands-free voice agent that runs your Mac** — talk to it and it opens apps,
plays music, sets volume, opens sites, sets reminders, checks your calendar,
kicks off background work, and even orders food. Inspired by Farza Majeed's
[Clicky](https://heyclicky.com) voice-control demo, **powered by
[Hydra](https://smallest.ai/speech-to-speech) — smallest.ai's native full-duplex
speech-to-speech model** instead of GPT-Realtime.

## What it does

```
        you talk  ⇄  Hydra (full-duplex S2S, sub-300ms, barge-in)
                        │  function calls
                        ▼
                  ActionRouter (native macOS)
   open_app · open_url · play_music · set_volume · set_reminder ·
   check_calendar · start_background_agent · order_food (Swiggy)
```

You never touch the keyboard. You can **interrupt it mid-sentence** — the thing
a stitched STT→LLM→TTS pipeline physically can't do. Money/irreversible actions
(placing a food order) require a spoken confirmation first.

> An earlier build aimed at the *older* open-source Clicky (a screen tutor that
> points at UI). Those pieces (`web/` pointing demo, `vision/`, Gemini `/vision`)
> still exist and work, but the product direction is now the **voice-OS-agent**
> above, matching Farza's latest demo.

## Design principles

- **Hydra runs the voice; the ActionRouter runs the Mac.** Tools map to
  `osascript` / `NSWorkspace` / EventKit; food ordering delegates to a local
  Playwright sidecar.
- **Confirm before spending.** `order_food` builds the cart and pauses at
  payment unless explicitly confirmed (and double-gated by an env flag).
- **The Hydra wire protocol is isolated in one place** (verified against
  `smallest-inc/hydra_agents`) — `web/hydra.js` + `macos/.../HydraClient.swift`.
  else changes.

## See it now (browser, no Mac)

```bash
cd web && python3 -m http.server 8080   # open http://localhost:8080
```

Two ways to run, both in the browser:
- **Quick (no keys):** click **▶️ Use demo screenshot**, ask "how do I export?" —
  Gemini brain + browser-voice stand-in, watch Clicky point.
- **Real Hydra:** pick a screen source, paste your smallest.ai key, hit
  **🎙️ Connect Hydra** — genuine full-duplex Hydra voice + screen awareness +
  pointing. Just talk, and interrupt it any time. (Protocol ported from the
  official [`smallest-inc/hydra_agents`](https://github.com/smallest-inc/hydra_agents).)

## Layout

| Path | What it is | Runnable here? |
|------|-----------|----------------|
| `macos/`       | **The app.** Swift: Hydra voice loop + `ActionRouter` (runs the Mac). Drop into a `clicky` fork. | ⚠️ needs Xcode/Mac |
| `swiggy-agent/`| Node + Playwright sidecar for `order_food` (your logged-in Swiggy, with a confirm gate) | ✅ `node` (acts on a Mac) |
| `prompts/`     | Hydra voice-OS-agent persona + action tool definitions | n/a |
| `web/`         | Browser Hydra-voice tester + the older screen-pointing demo (keyless or real Hydra) | ✅ static server |
| `worker/`      | Cloudflare Worker: Hydra WS passthrough + Gemini `/vision` + `/tutor` | ✅ `wrangler dev` |
| `vision/`      | Node harness: screenshot → Gemini → scene-graph (optional screen-awareness) | ✅ `node` |
| `docs/`        | Demo script, integration guide, Hydra contract, build phases, safety | n/a |

The standout choreography is in **`docs/DEMO_SCRIPT.md`** — Farza-style hands-free
flow (play music → drop volume → open a dashboard → set a reminder → order food),
all by voice, with barge-in.

## Status

This is built in phases (see `docs/PHASES.md`). The Mac app is meant to be a
**fork of `farzaa/clicky`** with the voice layer swapped — `macos/` holds the
new files plus a migration guide for what to remove from the original.

Start here: **`docs/INTEGRATION.md`** and **`docs/HYDRA_CONTRACT.md`**.
