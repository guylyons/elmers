#if DEBUG
import AVFoundation
import ElmersCore

/// Checks the capture → sound routing and the shape of each synthesized effect. With `ELMERS_CAPTURE_DIR`
/// set, also writes each effect as a WAV file so it can be auditioned.
@MainActor
enum SoundChecks {
    static func run() {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

        expect(SoundEffects.effect(forCaptured: .image) == .image, "image capture should click-click")
        expect(SoundEffects.effect(forCaptured: .screenshot) == nil, "saved screenshots should stay silent")
        for kind in [ContentKind.text, .link, .file, .other] {
            expect(SoundEffects.effect(forCaptured: kind) == .copy, "\(kind.rawValue) capture should play the copy tone")
        }

        let rate = 44_100.0
        var rendered: [SoundEffects.Effect: [Float]] = [:]
        for effect in SoundEffects.Effect.allCases {
            let samples = SoundEffects.samples(for: effect)
            rendered[effect] = samples
            let peak = samples.map(abs).max() ?? 0
            expect(!samples.isEmpty && samples.count < Int(0.3 * rate), "\(effect) should be a short sound")
            expect(peak > 0.1 && peak < 0.95, "\(effect) peak \(peak) should be audible without clipping")
            expect(abs(samples.last ?? 1) < 0.001, "\(effect) should end at silence")
        }
        let clickOnsets = onsets(rendered[.image] ?? [], rate: rate)
        expect(clickOnsets.count == 2, "image effect should have two clicks, found \(clickOnsets.count)")
        if clickOnsets.count == 2 {
            let gap = clickOnsets[1] - clickOnsets[0]
            expect(gap > 0.05 && gap < 0.1, "clicks should be 50–100 ms apart, were \(Int(gap * 1000)) ms")
        }
        expect(onsets(rendered[.copy] ?? [], rate: rate).count == 2, "copy tone should have two notes")
        expect(onsets(rendered[.paste] ?? [], rate: rate).count == 1, "paste tick should be a single burst")
        expect(rendered[.copy] != rendered[.image] && rendered[.copy] != rendered[.paste], "copy tone should be distinct")

        if let directory = ProcessInfo.processInfo.environment["ELMERS_CAPTURE_DIR"] {
            for (effect, samples) in rendered {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("sound-\(effect).wav")
                do { try write(samples, rate: rate, to: url) } catch { failures.append("could not write \(url.lastPathComponent): \(error)") }
            }
        }

        if failures.isEmpty { print("PASS: sound routing and \(SoundEffects.Effect.allCases.count) synthesized effects") }
        else { failures.forEach { print("FAIL: \($0)") } }
        fflush(stdout); exit(failures.isEmpty ? 0 : 1)
    }

    /// Start times of energy bursts: 2 ms windows whose RMS jumps above a third of the loudest window
    /// after at least 20 ms below it.
    private static func onsets(_ samples: [Float], rate: Double) -> [Double] {
        let window = Int(0.002 * rate)
        let levels = stride(from: 0, to: samples.count, by: window).map { start in
            let slice = samples[start..<min(start + window, samples.count)]
            return (slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count)).squareRoot()
        }
        let threshold = (levels.max() ?? 0) / 3
        var result: [Double] = [], quiet = 10, previous: Float = 0
        for (index, level) in levels.enumerated() {
            // A new note may start while the previous one is still ringing, so a sharp rise also counts.
            if level >= threshold, quiet >= 10 || level > previous * 1.6 && previous < threshold * 2 {
                if result.last.map({ Double(index * window) / rate - $0 > 0.02 }) ?? true { result.append(Double(index * window) / rate) }
            }
            quiet = level < threshold ? quiet + 1 : 0
            previous = level
        }
        return result
    }

    private static func write(_ samples: [Float], rate: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        try AVAudioFile(forWriting: url, settings: format.settings).write(from: buffer)
    }
}
#endif
