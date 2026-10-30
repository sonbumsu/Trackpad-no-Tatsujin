import Foundation

enum Judgement {
    case good, ok, bad
}

struct JudgeWindows {
    var good: Double
    var ok: Double
    var bad: Double

    /// scale 1.0이 원작 기준. 크게 할수록 판정이 너그럽다.
    static func forCourse(_ course: Course, scale: Double = 1) -> JudgeWindows {
        let w = course.usesStrictWindows
            ? JudgeWindows(good: 0.025, ok: 0.075, bad: 0.108)
            : JudgeWindows(good: 0.042, ok: 0.108, bad: 0.125)
        return JudgeWindows(good: w.good * scale, ok: w.ok * scale, bad: w.bad * scale)
    }
}

enum GameEvent: Equatable {
    case judged(note: Int, Judgement)
    case missed(note: Int)
    case bigBonus(note: Int)
    case rollHit(span: Int, count: Int)
    case balloonHit(span: Int, remaining: Int)
    case balloonPopped(span: Int)
}

enum Crown: String, Codable, Comparable {
    case failed, cleared, fullCombo, allGood

    private var rank: Int { [.failed: 0, .cleared: 1, .fullCombo: 2, .allGood: 3][self]! }
    static func < (a: Crown, b: Crown) -> Bool { a.rank < b.rank }

    var displayName: String {
        switch self {
        case .failed: return "실패"
        case .cleared: return "클리어"
        case .fullCombo: return "풀콤보"
        case .allGood: return "전량"
        }
    }
}

/// 한 판의 판정·점수·게이지 상태. 시각은 모두 곡 시작 기준 초 단위.
final class GameSession {
    let chart: Chart
    let windows: JudgeWindows
    var bigHitWindow: Double

    private(set) var results: [Judgement?]
    private(set) var score = 0
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var gauge = 0.0
    private(set) var goodCount = 0
    private(set) var okCount = 0
    private(set) var badCount = 0
    private(set) var rollCount = 0
    private(set) var balloonHits: [Int]
    private(set) var balloonPopped: [Bool]

    let noteScore: Int
    private let gaugeStep: Double
    private var cursor = 0
    private var lastBig: (note: Int, type: DrumType, time: Double)?

    init(chart: Chart, bigHitWindow: Double = 0.05, judgeScale: Double = 1) {
        self.chart = chart
        self.windows = .forCourse(chart.course, scale: judgeScale)
        self.bigHitWindow = bigHitWindow
        let n = max(1, chart.hitNotes.count)
        results = Array(repeating: nil, count: chart.hitNotes.count)
        balloonHits = Array(repeating: 0, count: chart.spans.count)
        balloonPopped = Array(repeating: false, count: chart.spans.count)
        noteScore = 1_000_000 / n / 10 * 10
        // 전체의 75%를 良으로 치면 게이지가 가득 찬다
        gaugeStep = 100 / (Double(n) * 0.75)
    }

    var isCleared: Bool { gauge >= chart.course.clearThreshold }

    var crown: Crown {
        guard isCleared else { return .failed }
        if goodCount == chart.hitNotes.count { return .allGood }
        if badCount == 0 { return .fullCombo }
        return .cleared
    }

    func hit(_ type: DrumType, at t: Double) -> [GameEvent] {
        // 대음표를 한 손으로 친 직후 같은 종류가 또 들어오면 양손 보너스
        if let big = lastBig, big.type == type, t - big.time <= bigHitWindow {
            lastBig = nil
            score += scaled(results[big.note] == .good ? noteScore : noteScore / 2, gogo: chart.hitNotes[big.note].isGogo)
            return [.bigBonus(note: big.note)]
        }

        var firstInWindow: Int?
        var match: Int?
        var i = cursor
        while i < chart.hitNotes.count, chart.hitNotes[i].time - t <= windows.bad {
            if results[i] == nil, abs(chart.hitNotes[i].time - t) <= windows.bad {
                if firstInWindow == nil { firstInWindow = i }
                if chart.hitNotes[i].type == type { match = i; break }
            }
            i += 1
        }

        if let m = match {
            let dt = abs(chart.hitNotes[m].time - t)
            let j: Judgement = dt <= windows.good ? .good : dt <= windows.ok ? .ok : .bad
            judge(m, j)
            if j != .bad, chart.hitNotes[m].isBig { lastBig = (m, type, t) }
            return [.judged(note: m, j)]
        }

        if let s = activeSpan(at: t) {
            return spanHit(s, type: type)
        }

        if let f = firstInWindow {
            judge(f, .bad)
            return [.judged(note: f, .bad)]
        }
        return []
    }

    /// 판정 범위를 지난 노트를 놓침 처리한다
    func update(now: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        while cursor < chart.hitNotes.count {
            if results[cursor] != nil {
                cursor += 1
            } else if now - chart.hitNotes[cursor].time > windows.bad {
                judge(cursor, .bad)
                events.append(.missed(note: cursor))
                cursor += 1
            } else {
                break
            }
        }
        if let big = lastBig, now - big.time > bigHitWindow { lastBig = nil }
        return events
    }

    func activeSpan(at t: Double) -> Int? {
        chart.spans.indices.first { i in
            let s = chart.spans[i]
            return t >= s.time && t <= s.endTime && !balloonPopped[i]
        }
    }

    private func spanHit(_ index: Int, type: DrumType) -> [GameEvent] {
        let span = chart.spans[index]
        switch span.kind {
        case .roll, .bigRoll:
            rollCount += 1
            balloonHits[index] += 1
            score += scaled(span.kind == .bigRoll ? 200 : 100, gogo: span.isGogo)
            return [.rollHit(span: index, count: balloonHits[index])]
        case let .balloon(required):
            guard type == .don else { return [] }
            rollCount += 1
            balloonHits[index] += 1
            score += scaled(300, gogo: span.isGogo)
            if balloonHits[index] >= required {
                balloonPopped[index] = true
                score += scaled(5000, gogo: span.isGogo)
                return [.balloonPopped(span: index)]
            }
            return [.balloonHit(span: index, remaining: required - balloonHits[index])]
        }
    }

    private func judge(_ i: Int, _ j: Judgement) {
        results[i] = j
        let gogo = chart.hitNotes[i].isGogo
        switch j {
        case .good:
            goodCount += 1
            combo += 1
            score += scaled(noteScore, gogo: gogo)
            gauge += gaugeStep
        case .ok:
            okCount += 1
            combo += 1
            score += scaled(noteScore / 2, gogo: gogo)
            gauge += gaugeStep / 2
        case .bad:
            badCount += 1
            combo = 0
            gauge -= gaugeStep * 2
        }
        gauge = min(100, max(0, gauge))
        maxCombo = max(maxCombo, combo)
    }

    private func scaled(_ points: Int, gogo: Bool) -> Int {
        gogo ? points * 12 / 10 : points
    }
}
