import Foundation
import AVFoundation

/// Microphone capture → PCM16, 16 kHz, mono — the format Hydra expects.
/// Taps the input node and resamples hardware audio (usually 44.1/48k float)
/// down to 16k Int16 with AVAudioConverter, emitting Data chunks.
///
/// TODO(mac): test on-device; tune the tap buffer size if you hear gaps.
final class Mic: MicCapture {
    var onChunk: ((Data) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 16000, channels: 1, interleaved: true)!

    func start() {
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inFormat) { [weak self] buffer, _ in
            self?.process(buffer, inFormat: inFormat)
        }
        do { try engine.start() } catch { NSLog("mic engine start failed: \(error)") }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func process(_ buffer: AVAudioPCMBuffer, inFormat: AVAudioFormat) {
        guard let converter else { return }
        // Output capacity scaled by the sample-rate ratio.
        let ratio = targetFormat.sampleRate / inFormat.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap) else { return }

        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return buffer
        }
        if let err { NSLog("mic convert: \(err)"); return }
        guard out.frameLength > 0, let ch = out.int16ChannelData else { return }
        let data = Data(bytes: ch[0], count: Int(out.frameLength) * MemoryLayout<Int16>.size)
        onChunk?(data)
    }
}
