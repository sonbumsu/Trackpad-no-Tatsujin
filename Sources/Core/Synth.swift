import Foundation

/// 아주 단순한 오프라인 신시사이저. 기본 수록곡 음악과 효과음을 코드로 만든다.
struct Synth {
    let sampleRate: Double
    private(set) var samples: [Float]

    init(duration: Double, sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
        samples = Array(repeating: 0, count: Int(duration * sampleRate))
    }

    /// start 초부터 duration 동안 f(경과 시간)을 더한다
    mutating func add(at start: Double, duration: Double, _ f: (Double) -> Double) {
        let first = max(0, Int(start * sampleRate))
        let last = min(samples.count, Int((start + duration) * sampleRate))
        guard first < last else { return }
        for i in first..<last {
            let tau = Double(i) / sampleRate - start
            samples[i] += Float(f(tau))
        }
    }

    mutating func normalize(peak: Float = 0.9) {
        let m = samples.reduce(0) { max($0, abs($1)) }
        guard m > 0 else { return }
        let k = peak / m
        for i in samples.indices { samples[i] *= k }
    }

    // MARK: - 재료

    static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    static func noise(_ x: Double) -> Double {
        var h = UInt64(bitPattern: Int64(x * 96_000)) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Double(h & 0xFFFF) / 32_768 - 1
    }

    /// f0에서 f1로 rate 속도로 떨어지는 사인파의 위상
    static func sweepPhase(_ t: Double, from f0: Double, to f1: Double, rate: Double) -> Double {
        2 * .pi * (f1 * t + (f0 - f1) / rate * (1 - exp(-rate * t)))
    }

    static func kick(_ t: Double) -> Double {
        sin(sweepPhase(t, from: 130, to: 45, rate: 30)) * exp(-t * 8) * 0.9
    }

    static func snare(_ t: Double) -> Double {
        noise(t) * exp(-t * 18) * 0.35 + sin(2 * .pi * 185 * t) * exp(-t * 30) * 0.3
    }

    static func hat(_ t: Double) -> Double {
        (noise(t) - noise(t + 1 / 44_100)) * exp(-t * 70) * 0.09
    }

    static func bass(_ t: Double, midi: Int) -> Double {
        let p = 2 * .pi * hz(midi) * t
        let env = min(1, t / 0.005) * exp(-t * 5)
        return (sin(p) + 0.45 * sin(2 * p) + 0.2 * sin(3 * p)) * env * 0.28
    }

    static func pluck(_ t: Double, midi: Int) -> Double {
        let p = hz(midi) * t
        let tri = 2 * abs(2 * (p - floor(p + 0.5))) - 1
        return tri * min(1, t / 0.003) * exp(-t * 11) * 0.12
    }

    static func lead(_ t: Double, midi: Int, length: Double) -> Double {
        let p = 2 * .pi * hz(midi) * t
        let vibrato = sin(2 * .pi * 5.5 * t) * 0.004 * min(1, t * 4)
        let q = p * (1 + vibrato)
        let wave = sin(q) + sin(3 * q) / 3 + sin(5 * q) / 6
        let env = min(1, t / 0.012) * (t > length - 0.03 ? max(0, (length - t) / 0.03) : 1) * exp(-t * 1.5)
        return wave * env * 0.11
    }

    static func pad(_ t: Double, midis: [Int], length: Double) -> Double {
        let env = min(1, t / 0.25) * min(1, max(0, length - t) / 0.4)
        return midis.reduce(0) { $0 + sin(2 * .pi * hz($1) * t) + 0.3 * sin(4 * .pi * hz($1) * t) } * env * 0.05
    }

    // MARK: - 효과음

    static func render(_ duration: Double, _ f: (Double) -> Double) -> [Float] {
        var s = Synth(duration: duration)
        s.add(at: 0, duration: duration, f)
        return s.samples
    }

    static let donSound: [Float] = render(0.35) { t in
        sin(sweepPhase(t, from: 190, to: 68, rate: 22)) * exp(-t * 11) * 0.95
            + noise(t) * exp(-t * 90) * 0.25
    }

    static let kaSound: [Float] = render(0.12) { t in
        sin(2 * .pi * 880 * t) * exp(-t * 45) * 0.45
            + sin(2 * .pi * 1_760 * t) * exp(-t * 70) * 0.25
            + noise(t) * exp(-t * 110) * 0.35
    }

    static let popSound: [Float] = render(0.3) { t in
        noise(t) * exp(-t * 14) * 0.6 + sin(2 * .pi * (500 + 1_500 * t) * t) * exp(-t * 20) * 0.2
    }

    static let clickSound: [Float] = render(0.06) { t in
        sin(2 * .pi * 1_500 * t) * exp(-t * 60) * 0.6
    }
}
