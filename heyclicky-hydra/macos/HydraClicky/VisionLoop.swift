import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Periodically captures the screen and asks the Worker `/vision` route (Gemini)
/// for a scene-graph. Runs independently of the voice loop so vision latency
/// never blocks Hydra. The orchestrator reads `latest` and decides when to
/// inject it as context.
final class VisionLoop {
    private let visionURL: URL          // e.g. https://your-worker.workers.dev/vision
    private let prompt: String          // prompts/scene_graph_prompt.md (text block)
    private let intervalSeconds: Double
    private var timer: Timer?

    /// Most recent scene-graph + the display it came from (for coord scaling).
    private(set) var latest: SceneGraph?
    private(set) var displayBounds: CGRect = .zero

    var onUpdate: ((SceneGraph) -> Void)?

    init(visionURL: URL, prompt: String, intervalSeconds: Double = 1.0) {
        self.visionURL = visionURL
        self.prompt = prompt
        self.intervalSeconds = intervalSeconds
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { await self?.captureOnce() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// On-demand read (used by the Hydra `look()` tool).
    func refreshNow() async -> SceneGraph? { await captureOnce() }

    @discardableResult
    private func captureOnce() async -> SceneGraph? {
        guard let (jpeg, bounds) = await grabMainDisplayJPEG() else { return nil }
        displayBounds = bounds
        do {
            let scene = try await analyze(jpeg)
            latest = scene
            onUpdate?(scene)
            return scene
        } catch {
            NSLog("vision: \(error)")
            return nil
        }
    }

    /// Capture the main display as JPEG. TODO(clicky): the original app already
    /// has multi-monitor capture in its *AssemblyAI/ScreenCaptureKit* code —
    /// reuse that and iterate displays for `screenN` support.
    private func grabMainDisplayJPEG() async -> (Data, CGRect)? {
        guard let content = try? await SCShareableContent.current,
              let display = content.displays.first else { return nil }

        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        let filter = SCContentFilter(display: display, excludingWindows: [])

        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        else { return nil }

        let rep = NSBitmapImageRep(cgImage: cg)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        return (jpeg, bounds)
    }

    private func analyze(_ jpeg: Data) async throws -> SceneGraph {
        var req = URLRequest(url: visionURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "image": jpeg.base64EncodedString(),
            "mimeType": "image/jpeg",
            "prompt": prompt,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: req)
        // Worker wraps the result as { "scene": {...} }
        struct Wrapper: Decodable { let scene: SceneGraph }
        return try JSONDecoder().decode(Wrapper.self, from: data).scene
    }
}
