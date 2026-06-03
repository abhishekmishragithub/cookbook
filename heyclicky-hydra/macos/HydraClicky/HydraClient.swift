import Foundation

/// Events surfaced from Hydra to the orchestrator.
enum HydraEvent {
    case audioDelta(Data)                              // PCM16 24kHz to play (gapless)
    case toolCall(callId: String, name: String, args: [String: Any])
    case userInterrupted                               // speech_started → barge-in
    case transcript(String)
    case closed(reason: String)
}

/// Hydra speech-to-speech client. Speaks the OpenAI-Realtime-style protocol
/// verified against smallest-inc/hydra_agents (see docs/HYDRA_CONTRACT.md).
///
/// Connect either directly
/// (`wss://api.smallest.ai/waves/v1/s2s?model=hydra&api_key=KEY`) or via the
/// Worker `/hydra` passthrough (which injects the key). Uplink audio is PCM16
/// 16kHz mono, base64 in `input_audio_buffer.append`.
final class HydraClient {
    private let url: URL
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    // Accumulate streamed function-call argument deltas by call_id.
    private var fnArgs: [String: (name: String, args: String)] = [:]

    var onEvent: ((HydraEvent) -> Void)?

    /// Session config to send on `session.created`.
    private var pendingConfig: [String: Any] = [:]

    /// - Parameter url: direct Hydra URL (with api_key) or your Worker `/hydra`.
    init(url: URL) { self.url = url }

    func connect(systemPrompt: String, tools: [[String: Any]], voice: String = "wren",
                 speaksFirst: Bool = true) {
        pendingConfig = [
            "instructions": systemPrompt,
            "voice": voice,
            "tools": tools.map { t -> [String: Any] in var x = t; x["type"] = "function"; return x },
            "generate_initial_response": speaksFirst,
        ]
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveLoop()
    }

    /// Stream a mic chunk (PCM16 @16k mono) as base64.
    func sendAudio(_ pcm: Data) {
        send(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
    }

    /// Inject the Gemini scene summary as a system message item.
    func appendContext(_ text: String) {
        send(["type": "conversation.item.create",
              "item": ["type": "message", "role": "system",
                       "content": [["type": "input_text", "text": text]]]])
    }

    /// Return a tool result, then ask Hydra to resume narrating.
    func sendToolResult(callId: String, output: String) {
        send(["type": "conversation.item.create",
              "item": ["type": "function_call_output", "call_id": callId, "output": output]])
        send(["type": "response.create"])
    }

    func cancelResponse() { send(["type": "response.cancel"]) }

    func close() { task?.cancel(with: .goingAway, reason: nil); task = nil }

    // MARK: - wire

    private func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { if let e = $0 { NSLog("hydra send: \(e)") } }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                self.onEvent?(.closed(reason: err.localizedDescription))
            case .success(let msg):
                if case .string(let s) = msg { self.handle(s) }
                self.receiveLoop()
            }
        }
    }

    private func handle(_ s: String) {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "session.created":
            send(["type": "session.configure", "session": pendingConfig])

        case "input_audio_buffer.speech_started":
            onEvent?(.userInterrupted)

        case "response.output_audio.delta":
            if let b64 = obj["delta"] as? String, let pcm = Data(base64Encoded: b64) {
                onEvent?(.audioDelta(pcm))
            }

        case "response.function_call_arguments.delta":
            if let id = obj["call_id"] as? String {
                var st = fnArgs[id] ?? (name: obj["name"] as? String ?? "", args: "")
                if let n = obj["name"] as? String { st.name = n }
                st.args += obj["delta"] as? String ?? ""
                fnArgs[id] = st
            }

        case "response.function_call_arguments.done":
            guard let id = obj["call_id"] as? String else { return }
            let st = fnArgs[id]
            let name = (obj["name"] as? String) ?? st?.name ?? ""
            let argStr = (obj["arguments"] as? String) ?? st?.args ?? "{}"
            fnArgs[id] = nil
            let args = (try? JSONSerialization.jsonObject(with: Data(argStr.utf8))) as? [String: Any] ?? [:]
            onEvent?(.toolCall(callId: id, name: name, args: args))

        case "conversation.item.done":
            if let item = obj["item"] as? [String: Any],
               let content = item["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                onEvent?(.transcript(text))
            }

        case "error":
            let e = obj["error"] as? [String: Any]
            NSLog("hydra error: \(e?["message"] ?? "unknown")")

        default:
            break // session.configured, response.created/done, etc.
        }
    }
}
