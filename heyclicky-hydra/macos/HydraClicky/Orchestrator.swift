import Foundation
import CoreGraphics

/// Bridges the voice loop (Hydra) and the vision loop (Gemini). Owns the
/// policy: when to inject screen context, how to execute Hydra's tool calls,
/// and how to drive the pointing overlay.
///
/// This is the heart of the app — and the part that replaces Clicky's
/// AssemblyAI + Claude + ElevenLabs glue.
final class Orchestrator {
    private let hydra: HydraClient
    private let vision: VisionLoop
    private let overlay: PointingOverlay   // reuse Clicky's NSPanel cursor overlay
    private let mic: MicCapture            // reuse/adapt Clicky's audio capture
    private let player: AudioPlayer        // PCM16 playback

    /// Throttle context injection: only push when the scene meaningfully changed.
    private var lastContextHash: Int = 0

    init(hydra: HydraClient, vision: VisionLoop, overlay: PointingOverlay,
         mic: MicCapture, player: AudioPlayer) {
        self.hydra = hydra
        self.vision = vision
        self.overlay = overlay
        self.mic = mic
        self.player = player
    }

    func start(systemPrompt: String, tools: Any) {
        hydra.onEvent = { [weak self] in self?.handle($0) }
        vision.onUpdate = { [weak self] scene in self?.maybeInjectContext(scene) }

        hydra.connect(systemPrompt: systemPrompt, tools: tools)
        vision.start()

        // Full-duplex: stream mic continuously, no push-to-talk.
        mic.onChunk = { [weak self] pcm in self?.hydra.sendAudio(pcm) }
        mic.start()
    }

    // MARK: - Hydra events

    private func handle(_ event: HydraEvent) {
        switch event {
        case .audio(let pcm):
            player.enqueue(pcm)
        case .userInterrupted:
            // Barge-in: dump whatever we were about to say.
            player.flush()
        case .toolCall(let id, let name, let args):
            Task { await self.execute(toolCall: id, name: name, args: args) }
        case .transcript(let t):
            overlay.showCaption(t)
        case .closed(let reason):
            NSLog("hydra closed: \(reason)")
        }
    }

    private func maybeInjectContext(_ scene: SceneGraph) {
        let block = scene.contextBlock
        let h = block.hashValue
        guard h != lastContextHash else { return }   // unchanged screen → skip
        lastContextHash = h
        hydra.appendContext(block)
    }

    // MARK: - tool execution (client-side)

    private func execute(toolCall id: String, name: String, args: [String: Any]) async {
        switch name {
        case "point_at":
            let label = args["label"] as? String ?? ""
            let ok = resolveAndPoint(label: label, highlight: false)
            hydra.sendToolResult(id: id, output: ["ok": ok, "label": label])

        case "highlight":
            let label = args["label"] as? String ?? ""
            let ok = resolveAndPoint(label: label, highlight: true)
            hydra.sendToolResult(id: id, output: ["ok": ok, "label": label])

        case "look":
            let scene = await vision.refreshNow()
            hydra.sendToolResult(id: id, output: [
                "elements": scene?.elements.map { $0.label } ?? [],
                "summary": scene?.summary ?? "",
            ])

        case "book_flight":
            // Phase 5: forward to the booking MCP server and relay its result.
            let result = await BookingMCP.shared.bookFlight(args)
            hydra.sendToolResult(id: id, output: result)

        default:
            hydra.sendToolResult(id: id, output: ["ok": false, "error": "unknown tool \(name)"])
        }
    }

    /// Resolve a semantic label to a point via the latest scene-graph and drive
    /// the overlay. Returns false if the label couldn't be grounded (Hydra can
    /// then call look() and retry).
    private func resolveAndPoint(label: String, highlight: Bool) -> Bool {
        guard let scene = vision.latest,
              let pt = scene.point(for: label, in: vision.displayBounds) else { return false }
        if highlight { overlay.highlight(at: pt, label: label) }
        else { overlay.point(at: pt, label: label) }
        return true
    }
}
