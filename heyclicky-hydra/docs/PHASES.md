# Build phases

The first kick-ass demo is a **focused voice-tutor slice**: full-duplex Hydra
voice + screen awareness + pointing, teaching **one** app (DaVinci Resolve or
Figma). Everything below ladders toward that, then Phase 5 adds real-world
booking.

## Phase 0 — De-risk the unknown ⚠️ do this first
The riskiest assumption is "Hydra full-duplex + barge-in feels great over a
WebSocket." Prove it before building UI.
- [ ] Fork `farzaa/clicky`, open in Xcode, confirm it builds & runs.
- [ ] Fill in `docs/HYDRA_CONTRACT.md` from the smallest.ai Hydra docs.
- [ ] Deploy `worker/` (`wrangler deploy`, set both secrets).
- [ ] Tiny spike: `HydraClient` + mic in + speaker out, nothing else. Talk to
      it, interrupt it. **Gate:** interruption/latency feels human. If not,
      revisit transport (chunk size, buffering) before continuing.

## Phase 1 — Voice core
- [ ] Drop the AssemblyAI + Claude + ElevenLabs path (see INTEGRATION.md).
- [ ] Wire `Orchestrator` → `HydraClient` with the tutor system prompt.
- [ ] Always-listening mic (no push-to-talk); `AudioPlayer.flush()` on barge-in.
- [ ] Reuse Clicky's menu-bar + character overlay. **Gate:** natural spoken
      conversation, no screen yet.

## Phase 2 — Vision + grounding
- [ ] `VisionLoop` capturing the main display ~1 fps → Worker `/vision`.
- [ ] Inject `SceneGraph.contextBlock` into Hydra, throttled on change.
- [ ] Verify with `vision/scene_graph.mjs --image real-shot.png` first.
      **Gate:** Hydra references on-screen things correctly.

## Phase 3 — Pointing bridge
- [ ] Implement `point_at` / `highlight` / `look` in `Orchestrator.execute`.
- [ ] `SceneGraph.point(for:in:)` → Clicky's cursor animation.
- [ ] Multi-monitor: iterate displays, carry `screenN`. **Gate:** "point at the
      Export button" lands on the right pixels across monitors.

## Phase 4 — Demo polish
- [ ] Pick the teach-app (DaVinci = Farza's own demo, high wow).
- [ ] Tune persona, choreograph an interrupt moment, tighten latency.
- [ ] Record. Lead with the interruption — that's the Hydra差.

## Phase 5 — Real-world actions via tool calling
The goal: show Hydra *doing* things by voice, through slick MCP tool calling —
not just booking. Candidate actions (pick whichever MCP servers exist / are
easiest first):
- [ ] **Media**: "play lo-fi on Spotify" / "pull up that video on YouTube".
- [ ] **Travel/commerce**: book an Airbnb / flight (Goibibo) / food (Zomato).
- [ ] Generalize `BookingMCP` → an `ActionRouter` that maps a tool name to the
      right MCP server and relays its result verbatim.
- [ ] Handle any login/auth handoff per service.
- [ ] **Gate:** Hydra only fires an action after explicit spoken confirmation,
      and reports the real tool result — never a fabricated one.
