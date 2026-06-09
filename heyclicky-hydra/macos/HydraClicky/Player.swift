import Foundation
import AVFoundation

/// Gapless playback of Hydra's downlink audio (PCM16, 24 kHz, mono).
/// Decodes each base64-decoded chunk to a float buffer and schedules it on an
/// AVAudioPlayerNode, which queues them seamlessly. `flush()` stops everything
/// instantly for barge-in.
final class Player: AudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 24000, channels: 1, interleaved: false)!
    private var started = false

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func enqueue(_ pcm: Data) {
        ensureRunning()
        guard let buf = makeBuffer(pcm) else { return }
        node.scheduleBuffer(buf, completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    /// Barge-in: drop everything queued/playing right now.
    func flush() {
        node.stop()      // clears scheduled buffers
        // node is ready to accept new buffers again on next enqueue/play
    }

    private func ensureRunning() {
        guard !started else { return }
        do { try engine.start(); started = true } catch { NSLog("player engine start: \(error)") }
    }

    private func makeBuffer(_ pcm: Data) -> AVAudioPCMBuffer? {
        let count = pcm.count / MemoryLayout<Int16>.size
        guard count > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let dst = buf.floatChannelData else { return nil }
        buf.frameLength = AVAudioFrameCount(count)
        pcm.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for i in 0..<count { dst[0][i] = Float(src[i]) / 32768.0 }
        }
        return buf
    }
}
