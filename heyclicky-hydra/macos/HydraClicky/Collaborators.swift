import Foundation
import CoreGraphics

// Interfaces the Orchestrator depends on. The first three already exist in
// some form inside farzaa/clicky — adapt those rather than writing new ones.
// See docs/INTEGRATION.md for the mapping.

/// The blue-cursor overlay. Clicky already renders this from its `[POINT:x,y]`
/// handling — point it at a CGPoint instead of parsing tags out of text.
protocol PointingOverlay {
    func point(at: CGPoint, label: String)
    func highlight(at: CGPoint, label: String)
    func showCaption(_ text: String)
}

/// Continuous mic capture as PCM16 chunks. Clicky streams mic to AssemblyAI;
/// retarget that tap to emit chunks here instead.
protocol MicCapture {
    var onChunk: ((Data) -> Void)? { get set }
    func start()
    func stop()
}

/// PCM16 downlink playback with a flush() for barge-in. Replaces Clicky's
/// ElevenLabs playback path.
protocol AudioPlayer {
    func enqueue(_ pcm: Data)
    func flush()
}

/// Phase 5 — booking via an MCP server (Zomato / Goibibo / etc).
/// Stub for now: wire to the real MCP client when the server is available.
/// Returns a plain dict that becomes Hydra's tool.result; never fabricates.
final class BookingMCP {
    static let shared = BookingMCP()
    func bookFlight(_ args: [String: Any]) async -> [String: Any] {
        // TODO(phase5): connect to the booking MCP server, call its flight tool,
        // handle the login/auth handoff, and return the real response.
        return ["ok": false, "error": "booking MCP not yet connected", "echo": args]
    }
}
