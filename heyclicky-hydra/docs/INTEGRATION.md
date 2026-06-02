# Integrating into a `clicky` fork

The Mac app is a **fork of [`farzaa/clicky`](https://github.com/farzaa/clicky)**
(MIT) with the voice layer swapped from a 3-stage pipeline to Hydra. This guide
maps what to keep, what to remove, and where the new `macos/HydraClicky/` files
go.

## Keep (reuse as-is or lightly adapt)
| Clicky piece | Reuse for |
|---|---|
| Menu-bar app shell, `NSPanel` overlay, character UI | unchanged |
| `[POINT:x,y]` cursor animation | drive it from `PointingOverlay.point(at:)` instead of parsing tags |
| `ScreenCaptureKit` capture + multi-monitor `screenN` logic | feed `VisionLoop` (replace the heuristic capture in `VisionLoop.grabMainDisplayJPEG`) |
| Mic capture tap (was → AssemblyAI) | retarget to `MicCapture.onChunk` |
| Cloudflare `worker/` pattern | replaced by this repo's `worker/` (Hydra + Gemini routes) |

## Remove (the old pipeline)
- `AssemblyAI*.swift` — STT. Hydra hears audio directly.
- `ClaudeAPI.swift` streaming client — Hydra is the brain now.
- ElevenLabs TTS calls — Hydra speaks directly.
- Any `[POINT:...]` **text-parsing** — pointing is a tool call now, not text.

## Add (from `macos/HydraClicky/`)
- `HydraClient.swift` — full-duplex WS to the Worker `/hydra`.
- `VisionLoop.swift` — screen → Worker `/vision` → `SceneGraph`.
- `SceneGraph.swift` — model + label→pixel resolution.
- `Orchestrator.swift` — the glue (replaces `CompanionManager`'s pipeline logic).
- `Collaborators.swift` — protocols (`PointingOverlay`, `MicCapture`,
  `AudioPlayer`) you back with the reused Clicky components, + `BookingMCP` stub.

## Wiring sketch (in your app entry / CompanionManager)
```swift
let proxy = URL(string: "wss://your-worker.workers.dev/hydra")!
let visionURL = URL(string: "https://your-worker.workers.dev/vision")!
let scenePrompt = /* contents of prompts/scene_graph_prompt.md text block */

let hydra = HydraClient(proxyURL: proxy)
let vision = VisionLoop(visionURL: visionURL, prompt: scenePrompt, intervalSeconds: 1.0)

let orchestrator = Orchestrator(
    hydra: hydra, vision: vision,
    overlay: myClickyOverlay,   // your PointingOverlay-conforming adapter
    mic: myMicCapture,          // your MicCapture-conforming adapter
    player: myPCM16Player       // your AudioPlayer-conforming adapter
)

let systemPrompt = /* prompts/system_prompt.md */
let tools        = /* parsed prompts/tools.json -> [["type": ...], ...] */
orchestrator.start(systemPrompt: systemPrompt, tools: tools)
```

## The one boundary that needs your input
`HydraClient` encodes the assumed Hydra wire protocol
(`docs/HYDRA_CONTRACT.md`). Confirm the four open items in §4 of that doc, then
adjust `HydraClient.encode*/decode` only. The Worker is a transparent
passthrough, so it needs no protocol changes — just the endpoint + key.
