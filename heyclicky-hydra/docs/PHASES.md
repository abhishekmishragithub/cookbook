# Build phases — voice-OS-agent

Goal: a hands-free, voice-controlled Mac agent (Farza-style) powered by Hydra.
You drive it by voice; it runs real actions and talks back.

## Phase 0 — De-risk the voice loop ⚠️ first
- [ ] Confirm the **browser** Hydra demo works with a real smallest.ai key
      (`web/` → Connect Hydra): talk, hear it, interrupt it. Proves Hydra +
      barge-in feel before any native code. (`docs/HYDRA_CONTRACT.md` is filled.)
- [ ] Fork `farzaa/clicky`, build it in Xcode.

## Phase 1 — Native voice core
- [ ] Drop the AssemblyAI + Claude + ElevenLabs path.
- [ ] Wire `HydraClient` + `Orchestrator` with the voice-OS-agent prompt.
- [ ] Always-listening mic (PCM16 16k) + gapless 24k playback with `flush()` on
      barge-in. **Gate:** natural spoken conversation.

## Phase 2 — Actions (the demo)
Implement + verify each tool in `ActionRouter` (`macos/.../Actions.swift`):
- [ ] `open_app`, `open_url`  (NSWorkspace / open)
- [ ] `play_music`, `set_volume`  (Spotify via osascript)
- [ ] `set_reminder`, `check_calendar`  (osascript; grant Automation/Calendar perms)
- [ ] `start_background_agent`  (stub → real worker later)
      **Gate:** the first five steps of `docs/DEMO_SCRIPT.md` work by voice.

## Phase 3 — Order food (Swiggy)
- [ ] Run `swiggy-agent` (`node server.mjs`), log in once via `/login`.
- [ ] `order_food {confirm:false}` builds the cart + pauses at payment.
- [ ] Spoken confirmation → `order_food {confirm:true}` (with
      `SWIGGY_ALLOW_PURCHASE=true`) places it. **Gate:** the full demo runs.
- [ ] Tune `SELECTORS` in `server.mjs` to current Swiggy DOM. See `docs/SAFETY.md`.

## Phase 4 — Polish & record
- [ ] Always-on hotword/hotkey, low-latency tuning, short confirmations.
- [ ] Record the one-take demo (`docs/DEMO_SCRIPT.md`).

## Later / optional
- More actions: YouTube, Airbnb, Maps, messaging — same `ActionRouter` pattern.
- Re-add screen awareness (`VisionLoop`/`SceneGraph` + Gemini) for "look at my
  screen and help" — kept in the repo, currently unwired.
- Replace the `start_background_agent` stub with a real headless agent.
