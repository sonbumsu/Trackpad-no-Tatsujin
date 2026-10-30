import Foundation

/// 음악 파일만으로 채보를 만든다. 템포가 일정한 곡을 가정한다.
///
/// 1. 저음/고음/전체 대역의 에너지 변화로 온셋(소리가 시작되는 세기) 곡선을 만든다
/// 2. 온셋 곡선의 주기 성분으로 BPM과 박 위치를 찾고, 저음이 강한 박을 마디 첫 박으로 본다
/// 3. 16분음표 격자마다 온셋 세기를 재서, 난이도별 밀도에 맞게 강한 곳부터 노트를 놓는다
/// 4. 마디 끝 두 박에 16분 온셋이 빽빽한 곳(필인, 드럼 롤)에 연타를, 그중 소리가 커지는 곳에 풍선을 놓는다
enum AutoCharter {
    struct Analysis {
        var bpm: Double
        /// 첫 마디가 시작되는 시각(초)
        var firstBar: Double
        var duration: Double
    }

    struct Envelope {
        var full: [Double]
        var low: [Double]
        var high: [Double]
        var rms: [Double]
        var frameRate: Double
    }

    static let hop = 512

    // MARK: - 온셋

    static func envelope(_ samples: [Float], sampleRate: Double) -> Envelope {
        let frames = samples.count / hop
        let aLow = exp(-2 * .pi * 150 / sampleRate)
        let aHigh = exp(-2 * .pi * 3_000 / sampleRate)
        var lp = 0.0, hp = 0.0
        var eFull = [Double](repeating: 0, count: frames)
        var eLow = eFull, eHigh = eFull
        for f in 0..<frames {
            var sf = 0.0, sl = 0.0, sh = 0.0
            for i in (f * hop)..<((f + 1) * hop) {
                let x = Double(samples[i])
                lp = (1 - aLow) * x + aLow * lp
                hp = (1 - aHigh) * x + aHigh * hp
                let h = x - hp
                sf += x * x
                sl += lp * lp
                sh += h * h
            }
            eFull[f] = sf
            eLow[f] = sl
            eHigh[f] = sh
        }
        let rms = eFull.map { sqrt($0 / Double(hop)) }
        return Envelope(full: flux(eFull), low: flux(eLow), high: flux(eHigh), rms: rms,
                        frameRate: sampleRate / Double(hop))
    }

    /// 로그 에너지가 늘어난 만큼만 남긴다. 아주 작은 소리의 흔들림은 바닥값으로 누른다.
    private static func flux(_ energy: [Double]) -> [Double] {
        guard !energy.isEmpty else { return [] }
        let floor = max(1e-9, energy.reduce(0, +) / Double(energy.count) * 1e-3)
        let logE = energy.map { log($0 + floor) }
        var out = [Double](repeating: 0, count: energy.count)
        for i in 1..<energy.count {
            out[i] = max(0, logE[i] - logE[i - 1])
        }
        return out
    }

    // MARK: - 템포

    static func analyze(_ env: Envelope) -> Analysis {
        let fr = env.frameRate
        let n = env.full.count
        // 박 검출용 곡선: 세 대역 합에서 0.5초 이동평균을 빼서 큰 음량 변화를 지운다
        var onset = zip(env.full, zip(env.low, env.high)).map { $0 + $1.0 + $1.1 }
        let win = Int(fr / 2)
        var acc = 0.0
        var smooth = [Double](repeating: 0, count: n)
        for i in 0..<n {
            acc += onset[i]
            if i >= win { acc -= onset[i - win] }
            smooth[i] = acc / Double(min(i + 1, win))
        }
        for i in 0..<n { onset[i] = max(0, onset[i] - smooth[min(n - 1, i + win / 2)]) }

        func strength(_ bpm: Double) -> (mag: Double, phase: Double) {
            let w = 2 * .pi * bpm / 60 / fr
            var re = 0.0, im = 0.0
            // 프레임 시각은 구간의 가운데로 본다
            for i in 0..<n where onset[i] > 0 {
                re += onset[i] * cos(w * (Double(i) + 0.5))
                im -= onset[i] * sin(w * (Double(i) + 0.5))
            }
            return ((re * re + im * im).squareRoot(), atan2(im, re))
        }

        // 70~210 BPM을 훑되, 사람이 박자로 느끼기 쉬운 130 근처를 조금 더 믿는다
        var best = (bpm: 120.0, score: -1.0)
        var bpm = 70.0
        while bpm <= 210 {
            let prior = exp(-0.5 * pow(log2(bpm / 130) / 0.5, 2))
            let score = strength(bpm).mag * prior
            if score > best.score { best = (bpm, score) }
            bpm += 0.5
        }
        var fine = (bpm: best.bpm, mag: -1.0, phase: 0.0)
        bpm = best.bpm - 0.6
        while bpm <= best.bpm + 0.6 {
            let s = strength(bpm)
            if s.mag > fine.mag { fine = (bpm, s.mag, s.phase) }
            bpm += 0.01
        }

        let period = 60 / fine.bpm
        // X = Σ o·e^{-iωt}에서 박이 φ + k·p에 있으면 arg X = -ωφ
        var beat = (-fine.phase / (2 * .pi)).truncatingRemainder(dividingBy: 1) * period
        if beat < 0 { beat += period }

        // 네 박 중 저음 온셋이 가장 강한 박을 마디 첫 박으로
        var sums = [Double](repeating: 0, count: 4)
        var k = 0
        while true {
            let f = Int(((beat + Double(k) * period) * fr).rounded())
            if f >= n { break }
            sums[k % 4] += peak(env.low, f, 1)
            k += 1
        }
        let down = sums.indices.max { sums[$0] < sums[$1] }!
        var firstBar = (beat + Double(down) * period).truncatingRemainder(dividingBy: 4 * period)
        if firstBar < 0 { firstBar += 4 * period }

        return Analysis(bpm: (fine.bpm * 1000).rounded() / 1000, firstBar: firstBar, duration: Double(n) / fr)
    }

    private static func peak(_ a: [Double], _ center: Int, _ radius: Int) -> Double {
        var m = 0.0
        for i in max(0, center - radius)...min(a.count - 1, center + radius) { m = max(m, a[i]) }
        return m
    }

    // MARK: - 채보

    private struct Profile {
        var course: Course
        var notesPerBeat: Double
        var step: Int // 허용하는 가장 잘게 쪼갠 격자 (16분 기준)
        var levels: ClosedRange<Int>
        var rollEvery: Int // 이 마디 수마다 연타 하나까지
        var maxRolls: Int
        var maxBalloons: Int
        var balloonRate: Double // 풍선을 터뜨리는 데 필요한 초당 타수
    }

    private static let profiles = [
        Profile(course: .easy, notesPerBeat: 0.55, step: 4, levels: 1...5,
                rollEvery: 48, maxRolls: 1, maxBalloons: 0, balloonRate: 0),
        Profile(course: .normal, notesPerBeat: 1.0, step: 2, levels: 2...7,
                rollEvery: 32, maxRolls: 3, maxBalloons: 0, balloonRate: 0),
        Profile(course: .hard, notesPerBeat: 1.5, step: 2, levels: 3...8,
                rollEvery: 24, maxRolls: 4, maxBalloons: 1, balloonRate: 5),
        Profile(course: .oni, notesPerBeat: 2.2, step: 1, levels: 4...10,
                rollEvery: 16, maxRolls: 6, maxBalloons: 2, balloonRate: 8),
    ]

    /// 연타나 풍선을 놓을 만한 마디. 마디의 뒤쪽 두 박(격자 8~15)을 쓴다.
    struct Fill {
        var measure: Int
        var score: Double
        var rising: Bool // 필인을 지나며 소리가 커진다
        var beforeGogo: Bool
    }

    static func findFills(norm: [Double], measureRMS: [Double], gogo: [Bool], silent: Double) -> [Fill] {
        var fills: [Fill] = []
        for m in 1..<max(1, measureRMS.count) where measureRMS[m] > silent {
            let window = (m * 16 + 8)..<(m * 16 + 16)
            // 16분 자리 거의 전부에 소리가 있고, 엇박 16분도 평소보다 세야 필인으로 본다
            guard window.filter({ norm[$0] > 0.6 }).count >= 7 else { continue }
            let offbeat = stride(from: window.lowerBound + 1, to: window.upperBound, by: 2)
                .map { norm[$0] }.reduce(0, +) / 4
            guard offbeat >= 0.9 else { continue }
            let beforeGogo = m + 1 < gogo.count && gogo[m + 1] && !gogo[m]
            var score = offbeat
            if beforeGogo { score *= 1.4 } else if m % 4 == 3 { score *= 1.15 }
            // 필인 자체도 소리를 키우니, 필인 앞 마디와 뒤 마디를 비교한다
            let rising = m + 1 < measureRMS.count && measureRMS[m + 1] > measureRMS[m - 1] * 1.3
            fills.append(Fill(measure: m, score: score, rising: rising, beforeGogo: beforeGogo))
        }
        return fills.sorted { $0.score > $1.score }
    }

    static func makeTJA(samples: [Float], sampleRate: Double, title: String, wave: String,
                        spans: Bool = true) -> (tja: String, analysis: Analysis) {
        let env = envelope(samples, sampleRate: sampleRate)
        let a = analyze(env)
        let fr = env.frameRate
        let beat = 60 / a.bpm
        let measures = max(1, Int((a.duration - a.firstBar) / (4 * beat)))
        let grid = measures * 16

        // 격자마다 세기와 저음 비율
        var strength = [Double](repeating: 0, count: grid)
        var lowRatio = strength
        for g in 0..<grid {
            let f = Int(((a.firstBar + Double(g) * beat / 4) * fr).rounded())
            guard f < env.full.count else { break }
            let lo = peak(env.low, f, 1), hi = peak(env.high, f, 1), full = peak(env.full, f, 1)
            strength[g] = full + 0.5 * (lo + hi)
            lowRatio[g] = lo / (lo + hi + 1e-9)
        }
        // 앞뒤 두 마디 평균으로 나눠서 조용한 구간에도 노트가 생기게 한다
        var norm = strength
        for g in 0..<grid {
            let lo = max(0, g - 32), hi = min(grid, g + 32)
            let mean = strength[lo..<hi].reduce(0, +) / Double(hi - lo)
            norm[g] = strength[g] / (mean + 1e-9)
        }
        // 마디 음량. 아주 조용한 마디는 비우고, 큰 마디가 이어지면 고고타임
        let measureRMS = (0..<measures).map { m -> Double in
            let f0 = Int((a.firstBar + Double(m) * 4 * beat) * fr)
            let f1 = min(env.rms.count, Int((a.firstBar + Double(m + 1) * 4 * beat) * fr))
            guard f0 < f1 else { return 0 }
            return env.rms[f0..<f1].reduce(0, +) / Double(f1 - f0)
        }
        let loud = measureRMS.sorted()
        let silent = (loud.last ?? 0) * 0.08
        let gogoLevel = loud[min(loud.count - 1, loud.count * 3 / 4)]
        var gogo = measureRMS.map { $0 >= gogoLevel && $0 > silent }
        markRuns(&gogo, minLength: 4)

        func weight(_ g: Int) -> Double {
            g % 16 == 0 ? 1.3 : g % 4 == 0 ? 1.0 : g % 2 == 0 ? 0.75 : 0.5
        }

        let fills = spans ? findFills(norm: norm, measureRMS: measureRMS, gogo: gogo, silent: silent) : []

        var charts: [(Profile, [Character], Int, [Int])] = []
        for p in profiles {
            let candidates = (0..<grid).filter { g in
                g % p.step == 0 && measureRMS[g / 16] > silent && norm[g] > 0.35
            }
            let scores = candidates.map { norm[$0] * weight($0) }
            let target = Int(Double(measures * 4) * p.notesPerBeat)
            let threshold = scores.sorted(by: >).dropFirst(max(0, min(target, scores.count) - 1)).first ?? .infinity
            var row = [Character](repeating: "0", count: grid)
            let chosen = zip(candidates, scores).filter { $0.1 >= threshold }.map(\.0)
            let medianRatio = chosen.map { lowRatio[$0] }.sorted()[safe: chosen.count / 2] ?? 0.5
            let bigLine = chosen.filter { $0 % 16 == 0 }.map { norm[$0] }.sorted(by: >)[safe: max(0, chosen.count / 25)] ?? .infinity
            for g in chosen {
                let don = lowRatio[g] >= medianRatio
                let big = g % 16 == 0 && norm[g] >= bigLine
                row[g] = big ? (don ? "3" : "4") : (don ? "1" : "2")
            }
            let balloons = placeSpans(&row, fills: fills, profile: p, measures: measures, beat: beat)
            let nps = Double(chosen.count) / max(1, Double(measures) * 4 * beat)
            let level = min(p.levels.upperBound, max(p.levels.lowerBound, Int((nps * 1.5).rounded())))
            charts.append((p, row, level, balloons))
        }

        let demo = gogo.firstIndex(of: true).map { a.firstBar + Double($0) * 4 * beat } ?? a.duration * 0.3
        var out = """
        TITLE:\(title)
        SUBTITLE:--자동 채보
        BPM:\(a.bpm)
        WAVE:\(wave)
        OFFSET:\(String(format: "%.3f", -a.firstBar))
        DEMOSTART:\(String(format: "%.1f", demo))

        """
        for (p, row, level, balloons) in charts {
            out += "\nCOURSE:\(p.course.rawValue)\nLEVEL:\(level)\n"
            if !balloons.isEmpty { out += "BALLOON:\(balloons.map(String.init).joined(separator: ","))\n" }
            out += "#START\n"
            for m in 0..<measures {
                if gogo[m], m == 0 || !gogo[m - 1] { out += "#GOGOSTART\n" }
                out += String(row[(m * 16)..<(m * 16 + 16)]) + ",\n"
                if gogo[m], m == measures - 1 || !gogo[m + 1] { out += "#GOGOEND\n" }
            }
            out += "#END\n"
        }
        return (out, a)
    }

    /// 점수가 높은 필인부터, 서로 8마디 이상 떨어지게 연타·풍선을 놓는다. 풍선 타수를 순서대로 돌려준다.
    private static func placeSpans(_ row: inout [Character], fills: [Fill], profile p: Profile,
                                   measures: Int, beat: Double) -> [Int] {
        let maxSpans = min(p.maxRolls, max(1, Int((Double(measures) / Double(p.rollEvery)).rounded())))
        var placed: [Int: Int?] = [:] // 마디 → 풍선 타수 (연타면 nil)
        var balloonCount = 0
        for fill in fills where placed.count < maxSpans {
            guard placed.keys.allSatisfy({ abs($0 - fill.measure) >= 8 }) else { continue }
            let start = fill.measure * 16 + 8, end = fill.measure * 16 + 15
            for g in start...end { row[g] = "0" }
            if fill.rising, balloonCount < p.maxBalloons {
                balloonCount += 1
                let required = max(3, Int((Double(end - start) * beat / 4 * p.balloonRate).rounded()))
                row[start] = "7"
                placed[fill.measure] = required
            } else {
                row[start] = fill.beforeGogo && p.course != .easy ? "6" : "5"
                placed[fill.measure] = .some(nil)
            }
            row[end] = "8"
        }
        return placed.sorted { $0.key < $1.key }.compactMap { $0.value }
    }

    /// minLength보다 짧게 이어진 true 구간은 지운다
    private static func markRuns(_ flags: inout [Bool], minLength: Int) {
        var i = 0
        while i < flags.count {
            guard flags[i] else { i += 1; continue }
            var j = i
            while j < flags.count, flags[j] { j += 1 }
            if j - i < minLength { for k in i..<j { flags[k] = false } }
            i = j
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
