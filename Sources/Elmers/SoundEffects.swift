import AVFoundation

/// Short, original UI sounds synthesized at launch so the app bundle needs no audio assets.
/// `copy` is a soft, rounded "pop" played when a new clipboard item is captured;
/// `paste` is a brighter, shorter "tick" played when an item is delivered.
@MainActor
final class SoundEffects {
    static let shared = SoundEffects()
    enum Effect { case copy, paste }
    var enabled = true
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private lazy var buffers: [Effect: AVAudioPCMBuffer] = [.copy: render(Self.copySamples()), .paste: render(Self.pasteSamples())]
    private var started = false

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ effect: Effect) {
        guard enabled, let buffer = buffers[effect] else { return }
        if !started {
            do { try engine.start(); started = true } catch { return }
        }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    private func render(_ samples: [Float]) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for channel in 0..<Int(format.channelCount) {
            let data = buffer.floatChannelData![channel]
            for (index, sample) in samples.enumerated() { data[index] = sample }
        }
        return buffer
    }

    // MARK: - Synthesis

    private static let rate: Double = 44_100

    /// A mallet-like "pop": a fundamental that dips slightly as it decays, a quiet octave partial,
    /// and a soft transient so the onset reads as a tap rather than a tone.
    static func copySamples() -> [Float] {
        let duration = 0.17
        return synthesize(duration: duration) { t in
            let pitch = 540.0 - 70.0 * min(t / 0.06, 1)
            let decay = exp(-t / 0.045)
            let body = sin(2 * .pi * pitch * t) * decay
            let partial = sin(2 * .pi * pitch * 2.02 * t) * exp(-t / 0.02) * 0.3
            let transient = noise(t) * exp(-t / 0.0025) * 0.35
            return (body + partial + transient) * 0.42
        }
    }

    /// A crisp "tick": a short high sweep over a faint low thump.
    static func pasteSamples() -> [Float] {
        let duration = 0.09
        return synthesize(duration: duration) { t in
            let pitch = 1_480.0 - 380.0 * min(t / 0.03, 1)
            let tick = sin(2 * .pi * pitch * t) * exp(-t / 0.014)
            let thump = sin(2 * .pi * 330 * t) * exp(-t / 0.03) * 0.45
            let transient = noise(t) * exp(-t / 0.0015) * 0.25
            return (tick + thump + transient) * 0.36
        }
    }

    private static func synthesize(duration: Double, _ sample: (Double) -> Double) -> [Float] {
        let count = Int(duration * rate)
        let attack = 0.003, release = 0.02
        return (0..<count).map { index in
            let t = Double(index) / rate
            let envelope = min(t / attack, 1) * min((duration - t) / release, 1)
            return Float(sample(t) * envelope)
        }
    }

    /// Deterministic noise so both channels and every launch produce identical samples.
    private static func noise(_ t: Double) -> Double {
        let x = sin(t * 12_345.678 + 0.5) * 43_758.5453
        return (x - floor(x)) * 2 - 1
    }
}
