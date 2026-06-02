# Hydra integration contract

Everything the rest of the codebase assumes about Hydra lives here. Fill in the
real values from the smallest.ai Hydra docs/dashboard, then the Worker and the
Swift `HydraClient` work unchanged.

> The Worker is a **transparent passthrough** — it forwards frames in both
> directions and only injects the API key server-side. So even if the message
> framing below is slightly off, the proxy keeps working; you only adjust
> `HydraClient.swift` (client) and `prompts/` (tool schema).

## 1. Transport

| Field | Default assumed | Your value |
|-------|-----------------|-----------|
| Endpoint | `wss://api.smallest.ai/hydra/v1/stream` | `________` |
| Auth | `Authorization: Bearer $HYDRA_API_KEY` | `________` |
| Subprotocol | none | `________` |
| Session config sent as | first JSON message after connect | `________` |

## 2. Audio format

| Field | Default assumed | Your value |
|-------|-----------------|-----------|
| Encoding (uplink) | PCM16 little-endian | `________` |
| Sample rate (uplink) | 16000 Hz mono | `________` |
| Encoding (downlink) | PCM16 little-endian | `________` |
| Sample rate (downlink) | 24000 Hz mono | `________` |
| Framing | raw binary WS frames | `________` |
| Chunk size | 20 ms (~640 bytes @16k) | `________` |

## 3. Control / event messages (JSON over the same socket)

What we assume the client sends and receives. Adjust names to match Hydra.

**Client → Hydra**
```jsonc
{ "type": "session.update", "session": {
    "system_prompt": "...",                 // see prompts/system_prompt.md
    "voice": "warm_tutor",
    "tools": [ /* prompts/tools.json */ ],
    "input_audio_format":  "pcm16",
    "output_audio_format": "pcm16"
} }

// Mid-stream context injection (the Gemini scene summary):
{ "type": "context.append", "role": "system",
  "text": "ON SCREEN NOW:\n- 'Export button' top-right ...\n..." }

// Result of a tool the client executed:
{ "type": "tool.result", "tool_call_id": "abc", "output": { "ok": true } }
```

**Hydra → Client**
```jsonc
{ "type": "audio.delta", "...": "..." }          // or raw binary frames
{ "type": "tool.call", "id": "abc",
  "name": "point_at", "arguments": { "label": "Export button" } }
{ "type": "speech.interrupted" }                 // user barged in
{ "type": "transcript.delta", "text": "..." }    // optional, for captions
```

## 4. Capabilities to confirm with the smallest.ai team

- [ ] **Mid-stream text context injection** — can we push the Gemini scene
      summary into an active session without resetting it? (Plan B if not:
      send it as a synthetic tool result to a `look()` call.)
- [ ] **Tool-calling schema** — OpenAI-style `{name, arguments}`? JSON-schema
      params? This drives `prompts/tools.json`.
- [ ] **Barge-in / interruption event** — does Hydra emit an event when the
      user talks over it, so we can duck/clear the output buffer?
- [ ] **Concurrent tool calls** while speaking, or only at turn boundaries?

## 5. Where these values are consumed

- `worker/src/index.ts` → `HYDRA_WS_URL`, `HYDRA_API_KEY` (env/secrets)
- `vision/.env` / `worker` → `GEMINI_API_KEY`
- `macos/HydraClicky/HydraClient.swift` → audio format + message types
- `prompts/tools.json` → tool-calling schema
