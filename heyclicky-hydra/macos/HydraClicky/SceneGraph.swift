import Foundation
import CoreGraphics

/// One element Gemini found on screen. `box2d` is normalized 0–1000 in
/// [ymin, xmin, ymax, xmax] order (Gemini's convention).
struct SceneElement: Decodable {
    let label: String
    let kind: String
    let box2d: [Int]
    let desc: String

    enum CodingKeys: String, CodingKey {
        case label, kind, desc
        case box2d = "box_2d"
    }
}

struct SceneGraph: Decodable {
    let summary: String
    let elements: [SceneElement]

    /// The compact "ON SCREEN NOW" block injected into Hydra as context.
    var contextBlock: String {
        let lines = elements.map { "- \"\($0.label)\" (\($0.kind)) — \($0.desc)" }
        return "ON SCREEN NOW: \(summary)\n" + lines.joined(separator: "\n")
    }

    /// Resolve a semantic label (from a Hydra `point_at` call) to a screen
    /// point in the pixel space of `displayBounds`. Center of the element box.
    /// Case-insensitive exact match first, then a contains() fallback.
    func point(for label: String, in displayBounds: CGRect) -> CGPoint? {
        let needle = label.lowercased()
        let match = elements.first { $0.label.lowercased() == needle }
            ?? elements.first { $0.label.lowercased().contains(needle) || needle.contains($0.label.lowercased()) }
        guard let e = match, e.box2d.count == 4 else { return nil }

        let ymin = CGFloat(e.box2d[0]) / 1000.0
        let xmin = CGFloat(e.box2d[1]) / 1000.0
        let ymax = CGFloat(e.box2d[2]) / 1000.0
        let xmax = CGFloat(e.box2d[3]) / 1000.0
        let cx = (xmin + xmax) / 2.0
        let cy = (ymin + ymax) / 2.0

        return CGPoint(
            x: displayBounds.origin.x + cx * displayBounds.width,
            y: displayBounds.origin.y + cy * displayBounds.height
        )
    }
}
