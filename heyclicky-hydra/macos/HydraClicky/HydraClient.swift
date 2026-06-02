import Foundation

/// Events surfaced from Hydra to the orchestrator.
enum HydraEvent {
    case audio(Data)                                   // downlink audio to play
    case toolCall(id: String, name: String, args: [String: Any])
    case userInterrupted                               // barge-in: stop playback
    case transcript(String)                            // optional captions
    case closed(reason: String)
}

/// WebSocket client to the Cloudflare Worker `/hydra` passthrough (which adds
/// the Hydra key server-side). Full-duplex: uplink mic audio streams while
/// downlink audio/events arrive concurrently.
///
/// TODO(hydra): the message framing below is the assumed contract from
/// docs/HYDRA_CONTRACT.md. Adjust `encode*` / `decode` to Hydra's real wire
/// format once confirmed. Everything else (orchestrator, overlay) is unaffected.
final class HydraClient {
    private let proxyURL: URL          // e.g. wss://your-worker.workers.dev/hydra
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)

    var onEvent: ((HydraEvent) -> Void)?

    init(proxyURL: URL) { self.proxyURL = proxyURL }

    func connect(systemPrompt: String, tools: Any, voice: String = "warm_tutor") {
        let task = session.webSocketTask(with: proxyURL)
        self.task = task
        task.resume()

        // First message configures the session (see HYDRA_CONTRACT §3).
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "system_prompt": systemPrompt,
                "voice": voice,
                "tools": tools,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
            ],
        ]
        sendJSON(config)
        receiveLoop()
    }

    /// Stream a chunk of mic audio (PCM16 @16k mono by default).
    func sendAudio(_ pcm: Data) {
        task?.send(.data(pcm)) { if let e = $0 { NSLog("hydra send audio: \(e)") } }
    }

    /// Push the latest Gemini scene summary as mid-stream context.
    func appendContext(_ text: String) {
        sendJSON(["type": "context.append", "role": "system", "text": text])
    }

    /// Return the result of a client-executed tool call back to Hydra.
    func sendToolResult(id: String, output: [String: Any]) {
        sendJSON(["type": "tool.result", "tool_call_id": id, "output": output])
    }

    func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - wire

    private func sendJSON(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { if let e = $0 { NSLog("hydra send json: \(e)") } }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                self.onEvent?(.closed(reason: err.localizedDescription))
                return
            case .success(let msg):
                switch msg {
                case .data(let d):
                    // Default contract: raw binary frames are downlink audio.
                    self.onEvent?(.audio(d))
                case .string(let s):
                    self.handleJSON(s)
                @unknown default: break
                }
                self.receiveLoop()
            }
        }
    }

    private func handleJSON(_ s: String) {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "tool.call":
            let id = obj["id"] as? String ?? UUID().uuidString
            let name = obj["name"] as? String ?? ""
            let args = obj["arguments"] as? [String: Any] ?? [:]
            onEvent?(.toolCall(id: id, name: name, args: args))
        case "speech.interrupted":
            onEvent?(.userInterrupted)
        case "transcript.delta":
            if let t = obj["text"] as? String { onEvent?(.transcript(t)) }
        default:
            break // audio.delta etc. — handle if Hydra sends audio as JSON
        }
    }
}
