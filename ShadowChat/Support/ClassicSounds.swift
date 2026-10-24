import AppKit
import Foundation

/// Buddy-list sound cues in the spirit of a 1990s messenger: a door creaking open when
/// someone signs on, a door shutting when they leave, a bloop for an incoming message, and
/// a soft blip when you send. Every sound is synthesized here, so no third-party audio ships.
enum ClassicSound: String, CaseIterable {
    case doorOpen
    case doorClose
    case imReceive
    case imSend
}

enum ClassicSoundSynth {
    static let sampleRate = 22_050

    /// Samples in -1...1 for a cue.
    static func samples(for sound: ClassicSound) -> [Float] {
        switch sound {
        case .doorOpen:
            // A rising creak, then a light knock against the frame.
            return sweep(from: 170, to: 420, seconds: 0.32, volume: 0.32, wobble: 22, harmonics: true)
                + silence(0.02)
                + knock(freq: 150, seconds: 0.09, volume: 0.55)
        case .doorClose:
            // A falling creak, then the door thuds shut twice.
            return sweep(from: 380, to: 160, seconds: 0.22, volume: 0.28, wobble: 18, harmonics: true)
                + knock(freq: 110, seconds: 0.10, volume: 0.65)
                + silence(0.03)
                + knock(freq: 90, seconds: 0.08, volume: 0.45)
        case .imReceive:
            // Two quick rising bubbles.
            return sweep(from: 520, to: 880, seconds: 0.09, volume: 0.42)
                + silence(0.015)
                + sweep(from: 700, to: 1_180, seconds: 0.11, volume: 0.38)
        case .imSend:
            // One short falling blip.
            return sweep(from: 980, to: 560, seconds: 0.08, volume: 0.30)
        }
    }

    /// A 16-bit mono PCM WAV file for a cue.
    static func wav(for sound: ClassicSound) -> Data {
        wav(samples: samples(for: sound))
    }

    static func wav(samples: [Float]) -> Data {
        var data = Data()
        let byteCount = UInt32(samples.count * 2)
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        put32(36 + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        put32(16)
        put16(1)
        put16(1)
        put32(UInt32(sampleRate))
        put32(UInt32(sampleRate * 2))
        put16(2)
        put16(16)
        data.append(contentsOf: Array("data".utf8))
        put32(byteCount)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            put16(UInt16(bitPattern: Int16(clamped * Float(Int16.max))))
        }
        return data
    }

    private static func silence(_ seconds: Double) -> [Float] {
        Array(repeating: 0, count: Int(seconds * Double(sampleRate)))
    }

    private static func sweep(
        from start: Double,
        to end: Double,
        seconds: Double,
        volume: Float,
        wobble: Double = 0,
        harmonics: Bool = false
    ) -> [Float] {
        let count = Int(seconds * Double(sampleRate))
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        for index in 0..<count {
            let t = Double(index) / Double(count)
            let vibrato = wobble > 0 ? sin(Double(index) / Double(sampleRate) * 2 * .pi * 31) * wobble : 0
            let freq = start + (end - start) * t + vibrato
            phase += 2 * .pi * freq / Double(sampleRate)
            var value = sin(phase)
            if harmonics {
                value = value * 0.6 + sin(phase * 2) * 0.25 + sin(phase * 3) * 0.15
            }
            out[index] = Float(value) * volume * envelope(t)
        }
        return out
    }

    private static func knock(freq: Double, seconds: Double, volume: Float) -> [Float] {
        let count = Int(seconds * Double(sampleRate))
        var out = [Float](repeating: 0, count: count)
        var seed: UInt32 = 0x5EED
        for index in 0..<count {
            let t = Double(index) / Double(count)
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(Int32(bitPattern: seed)) / Double(Int32.max)
            let tone = sin(2 * .pi * freq * Double(index) / Double(sampleRate))
            let decay = exp(-t * 7)
            out[index] = Float((tone * 0.8 + noise * 0.2) * decay) * volume
        }
        return out
    }

    /// Short attack and release so cues never click.
    private static func envelope(_ t: Double) -> Float {
        let attack = min(1, t / 0.08)
        let release = min(1, (1 - t) / 0.25)
        return Float(max(0, min(attack, release)))
    }
}

@MainActor
final class ClassicSoundPlayer {
    static let shared = ClassicSoundPlayer()

    private var cache: [ClassicSound: NSSound] = [:]
    private var lastPlayed: [ClassicSound: Date] = [:]

    func play(_ sound: ClassicSound) {
        let now = Date()
        // A roundtable can finish several replies at once; one cue per beat is enough.
        if let last = lastPlayed[sound], now.timeIntervalSince(last) < 0.45 { return }
        lastPlayed[sound] = now
        let player: NSSound?
        if let cached = cache[sound] {
            player = cached
        } else {
            player = NSSound(data: ClassicSoundSynth.wav(for: sound))
            cache[sound] = player
        }
        player?.stop()
        player?.play()
    }
}
