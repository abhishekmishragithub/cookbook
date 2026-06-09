import Foundation

/// Coarse UI state for the menu-bar orb.
enum AgentState: String { case idle, connecting, listening, thinking, speaking }

/// The app core: Hydra full-duplex voice in/out + routing tool calls to the
/// macOS `ActionRouter`. This is the "voice that runs your Mac" loop — the
/// screen-vision/pointing pieces (VisionLoop/SceneGraph) are optional and not
/// required here.
final class Orchestrator {
    private let hydra: HydraClient
    private let mic: MicCapture          // reuse/adapt Clicky's audio capture
    private let player: AudioPlayer      // PCM16 24k playback with flush() for barge-in
    private let actions = ActionRouter()

    /// UI hooks (main-thread).
    var onState: ((AgentState) -> Void)?
    var onActivity: ((String) -> Void)?   // human-readable line for the log

    init(hydra: HydraClient, mic: MicCapture, player: AudioPlayer) {
        self.hydra = hydra
        self.mic = mic
        self.player = player
    }

    func start(systemPrompt: String, tools: [[String: Any]], voice: String = "wren") {
        hydra.onEvent = { [weak self] in self?.handle($0) }
        emit(.connecting)
        hydra.connect(systemPrompt: systemPrompt, tools: tools, voice: voice)

        // Full-duplex: stream mic continuously, no push-to-talk.
        mic.onChunk = { [weak self] pcm in self?.hydra.sendAudio(pcm) }
        mic.start()
        emit(.listening)
    }

    func stop() {
        mic.stop()
        player.flush()
        hydra.close()
        emit(.idle)
    }

    private func handle(_ event: HydraEvent) {
        switch event {
        case .audioDelta(let pcm):
            player.enqueue(pcm)
            emit(.speaking)
        case .userInterrupted:                 // barge-in: drop queued speech
            player.flush()
            emit(.listening)
        case .toolCall(let callId, let name, let args):
            emit(.thinking)
            onActivity?("→ \(name)(\(args))")
            Task {
                let output = await self.actions.run(name, args)
                self.onActivity?("← \(output)")
                self.hydra.sendToolResult(callId: callId, output: output)
            }
        case .transcript(let t):
            onActivity?("clicky: \(t)")
        case .closed(let reason):
            onActivity?("hydra closed: \(reason)")
            emit(.idle)
        }
    }

    private func emit(_ s: AgentState) {
        DispatchQueue.main.async { self.onState?(s) }
    }
}
