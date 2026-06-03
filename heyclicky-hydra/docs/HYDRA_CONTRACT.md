# Hydra integration contract (REAL — from smallest-inc/hydra_agents)

Verified against the official reference app
[`smallest-inc/hydra_agents`](https://github.com/smallest-inc/hydra_agents)
(`src/app/lib/hydra-client.ts`, `lib/audio.ts`, `hooks/useHydraSession.ts`,
`types.ts`). Hydra speaks an **OpenAI-Realtime-style** JSON-over-WebSocket
protocol. This file is now fact, not assumption.

## 1. Transport
- **URL:** `wss://api.smallest.ai/waves/v1/s2s?model=hydra&api_key=<KEY>`
- **Auth:** API key as the `api_key` **query parameter** (not a header).
- **Framing:** every frame is JSON, keyed by `type`. Audio is base64 inside
  JSON (no raw binary frames).

## 2. Audio
- **Uplink (mic):** PCM16, **16 kHz** mono, sent as base64 in
  `input_audio_buffer.append`. Reference posts **480-sample (30 ms)** frames.
- **Downlink:** PCM16, **24 kHz** mono (server announces
  `output_audio_sample_rate` in `session.configured`), base64 in
  `response.output_audio.delta`.

## 3. Handshake & turn lifecycle
```
server → session.created   { session_id }
client → session.configure { session: { instructions, voice, tools,
                                         generate_initial_response } }
server → session.configured { session: { output_audio_sample_rate, ... } }
        ... client now streams input_audio_buffer.append continuously ...
server → input_audio_buffer.speech_started   // VAD: user talking → BARGE-IN
server → input_audio_buffer.speech_stopped
server → conversation.item.added / .done     // transcript items
server → response.created
server → response.output_audio.delta { delta: <b64 pcm16> }   // play these
server → response.output_audio.done
server → response.done { response: { status, output, usage } }
```

## 4. Barge-in (the demo hero) — already native
Server emits **`input_audio_buffer.speech_started`** the instant the user talks
over the agent. On that event: **stop playback immediately** and clear the
queued audio (the reference calls `playback.stop()` which kills every scheduled
buffer). No special config needed — full-duplex is built in.

## 5. Tool calling (OpenAI-Realtime style)
- Tools passed in `session.configure` as `{ type:"function", name, description,
  parameters }` (JSON-schema params). See `prompts/tools.json`.
- Server streams the call:
  `response.function_call_arguments.delta { call_id, name, delta }` →
  `response.function_call_arguments.done { call_id, name, arguments }`.
- Client executes locally, then:
  ```
  client → conversation.item.create { item: { type:"function_call_output",
                                               call_id, output: <string> } }
  client → response.create          // resume so it narrates the result
  ```
  (Reference debounces ~220 ms so parallel calls all land before `response.create`.)

## 6. Injecting screen context mid-session
The session prompt/voice/tools are **locked at `session.configure`** and can't
change without reconnecting. To stream the Gemini scene-graph in, send it as a
conversation item:
```
client → conversation.item.create { item: { type:"message", role:"system",
            content:[{ type:"input_text", text:"ON SCREEN NOW: ..." }] } }
```
(`session.update` only swaps `tools`.)

## 7. Voices
Waves voices, e.g. **`wren`**, `sloane`, `reed`. Pick one for `voice`.

## 8. Where consumed
- `worker/wrangler.toml` → `HYDRA_WS_URL`; key via `wrangler secret HYDRA_API_KEY`.
- `web/hydra.js` → full browser client (ported from the reference).
- `macos/HydraClicky/HydraClient.swift` → same protocol in Swift.
- `prompts/tools.json` → tool schema (`type:"function"`).
