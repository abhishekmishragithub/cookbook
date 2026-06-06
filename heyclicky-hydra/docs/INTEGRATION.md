# Integrating into a `clicky` fork

The app is a **fork of [`farzaa/clicky`](https://github.com/farzaa/clicky)**
(MIT) with the voice layer swapped to Hydra and the brain swapped to a
voice-OS-agent that runs real macOS actions.

## Keep (reuse from clicky)
| Clicky piece | Reuse for |
|---|---|
| Menu-bar app shell, `NSPanel`, hotkey/always-on plumbing | unchanged |
| Mic capture tap (was → AssemblyAI) | retarget to `MicCapture.onChunk` (PCM16 16k) |
| Any audio playback infra | back `AudioPlayer` (PCM16 24k, gapless, `flush()`) |

## Remove (the old pipeline)
- `AssemblyAI*.swift` (STT) — Hydra hears directly.
- `ClaudeAPI.swift` (LLM) — Hydra is the brain.
- ElevenLabs TTS — Hydra speaks directly.
- `[POINT:...]` text parsing / cursor overlay — not used by the agent (keep only
  if you also want the optional "look at my screen" tutor mode).

## Add (from `macos/HydraClicky/`)
- `HydraClient.swift` — full-duplex WS to Hydra (real OpenAI-Realtime protocol).
- `Orchestrator.swift` — voice ⇄ tool-call routing (replaces `CompanionManager`
  pipeline logic).
- `Actions.swift` — the `ActionRouter`: open_app / open_url / play_music /
  set_volume / set_reminder / check_calendar / start_background_agent / order_food.
- `Collaborators.swift` — `MicCapture` + `AudioPlayer` protocols (back them with
  your reused clicky audio components).
- *(optional, unwired)* `SceneGraph.swift` + `VisionLoop.swift` for screen-awareness.

## Also run (separate process, on the Mac)
- `swiggy-agent/` — `node server.mjs` for `order_food`. See its README + `docs/SAFETY.md`.

## Wiring sketch (app entry / CompanionManager)
```swift
// Connect directly with the key, or via your Worker /hydra passthrough.
let hydraURL = URL(string: "wss://api.smallest.ai/waves/v1/s2s?model=hydra&api_key=\(KEY)")!

let hydra = HydraClient(url: hydraURL)
let orchestrator = Orchestrator(
    hydra: hydra,
    mic: myMicCapture,     // MicCapture-conforming adapter (PCM16 16k chunks)
    player: myPCM16Player  // AudioPlayer-conforming adapter (PCM16 24k + flush)
)

let systemPrompt = /* prompts/system_prompt.md */
let tools        = /* parsed prompts/tools.json "tools" array -> [[String:Any]] */
orchestrator.start(systemPrompt: systemPrompt, tools: tools, voice: "wren")
```

## Permissions (macOS)
First use of Spotify/Reminders/Calendar control prompts for **Automation** /
Calendar access — grant in System Settings → Privacy & Security. The Hydra
protocol itself is settled in `docs/HYDRA_CONTRACT.md`.
