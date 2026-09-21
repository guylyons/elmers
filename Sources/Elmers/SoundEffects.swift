import AVFoundation
import ElmersCore

/// Short, original UI sounds synthesized at launch so the app bundle needs no audio assets.
/// `copy` is a short two-note confirmation chime played when something is copied (captured from the
/// clipboard, or copied out of Elmers); `image` is a quick "click-click" played when an image is grabbed
/// from the clipboard; `paste` is a brighter, shorter "tick" played when an item is pasted directly.
@MainActor
final class SoundEffects {
    static let shared = SoundEffects()
    enum Effect: CaseIterable { case copy, image, paste }
    /// The sound for a newly captured clipboard item. Screenshots saved to disk arrive silently, as before.
    static func effect(forCaptured kind: ContentKind) -> Effect? {
        switch kind {
        case .image: .image
        case .screenshot: nil
        default: .copy
        }
    }
    var enabled = true
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private lazy var buffers: [Effect: AVAudioPCMBuffer] = Dictionary(uniqueKeysWithValues: Effect.allCases.map { ($0, render(Self.samples(for: $0))) })
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

    static func samples(for effect: Effect) -> [Float] {
        switch effect {
        case .copy: copySamples()
        case .image: imageSamples()
        case .paste: pasteSamples()
        }
    }

    /// A soft rising fifth (G5 → D6): two bell-like notes, the second entering 70 ms after the first,
    /// each with a quiet octave partial so it reads as a confirmation rather than a beep.
    static func copySamples() -> [Float] {
        synthesize(duration: 0.24) { t in
            func note(_ pitch: Double, at start: Double, level: Double) -> Double {
                let local = t - start
                guard local >= 0 else { return 0 }
                let onset = min(local / 0.004, 1)
                let body = sin(2 * .pi * pitch * local) * exp(-local / 0.06)
                let partial = sin(2 * .pi * pitch * 2 * local) * exp(-local / 0.025) * 0.18
                return (body + partial) * onset * level
            }
            return (note(784, at: 0, level: 0.8) + note(1_174.66, at: 0.07, level: 1)) * 0.3
        }
    }

    /// "Click-click": two short, dry clicks 75 ms apart, the second a touch lower and softer,
    /// like a camera shutter or a mouse double-click.
    static func imageSamples() -> [Float] {
        synthesize(duration: 0.14, attack: 0.0005) { t in
            func click(at start: Double, pitch: Double, level: Double) -> Double {
                let local = t - start
                guard local >= 0 else { return 0 }
                let snap = noise(local + start) * exp(-local / 0.0018)
                let ring = sin(2 * .pi * pitch * local) * exp(-local / 0.005) * 0.7
                let knock = sin(2 * .pi * 620 * local) * exp(-local / 0.009) * 0.35
                return (snap + ring + knock) * level
            }
            return (click(at: 0, pitch: 2_600, level: 1) + click(at: 0.075, pitch: 2_300, level: 0.85)) * 0.4
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

    private static func synthesize(duration: Double, attack: Double = 0.003, _ sample: (Double) -> Double) -> [Float] {
        let count = Int(duration * rate)
        let release = 0.02
        return (0..<count).map { index in
            let t = Double(index) / rate
            let envelope = min(t / attack, 1) * min((duration - t) / release, 1)
            return Float(sample(t) * envelope)
        }
    }

    /// Deterministic noise so both channels and every launch produce identical samples.
    nonisolated private static func noise(_ t: Double) -> Double {
        let x = sin(t * 12_345.678 + 0.5) * 43_758.5453
        return (x - floor(x)) * 2 - 1
    }
}
