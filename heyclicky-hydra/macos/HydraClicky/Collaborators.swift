import Foundation

// Audio interfaces the Orchestrator depends on. Both already exist in some form
// inside farzaa/clicky — adapt those rather than writing new ones.
// See docs/INTEGRATION.md for the mapping.

/// Continuous mic capture as PCM16 16kHz mono chunks (base64'd by HydraClient).
/// Clicky streams mic to AssemblyAI; retarget that tap to emit chunks here.
protocol MicCapture: AnyObject {
    var onChunk: ((Data) -> Void)? { get set }
    func start()
    func stop()
}

/// PCM16 24kHz downlink playback with flush() for barge-in. Replaces Clicky's
/// ElevenLabs playback path. Mirror the gapless scheduler in web/hydra.js.
protocol AudioPlayer: AnyObject {
    func enqueue(_ pcm: Data)
    func flush()
}

// NOTE: screen-awareness (SceneGraph.swift / VisionLoop.swift) and the pointing
// overlay are OPTIONAL for the voice-OS-agent and not wired into Orchestrator.
// Re-introduce them only if you want the tutor "point at my screen" behavior.
