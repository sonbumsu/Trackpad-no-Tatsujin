import Foundation

/// 난이도
enum Course: Int, CaseIterable, Codable, Comparable {
    case easy = 0, normal, hard, oni, ura

    var displayName: String {
        ["쉬움", "보통", "어려움", "귀신", "귀신(뒷)"][rawValue]
    }

    static func < (a: Course, b: Course) -> Bool { a.rawValue < b.rawValue }

    static func parse(_ s: String) -> Course? {
        switch s.trimmingCharacters(in: .whitespaces).lowercased() {
        case "easy", "0": return .easy
        case "normal", "1": return .normal
        case "hard", "2": return .hard
        case "oni", "3": return .oni
        case "edit", "ura", "4": return .ura
        default: return nil
        }
    }

    /// 어려움 이상은 판정이 엄격하다
    var usesStrictWindows: Bool { self >= .hard }

    /// 곡이 끝났을 때 이 % 이상이면 클리어
    var clearThreshold: Double {
        switch self {
        case .easy: return 60
        case .normal, .hard: return 70
        case .oni, .ura: return 80
        }
    }
}

enum DrumType: Equatable {
    case don, ka
}

struct HitNote: Equatable {
    var time: Double
    var type: DrumType
    var isBig: Bool
    var bpm: Double
    var scroll: Double
    var isGogo: Bool
}

enum SpanKind: Equatable {
    case roll
    case bigRoll
    case balloon(required: Int)
}

/// 연타·풍선처럼 시작과 끝이 있는 노트
struct SpanNote: Equatable {
    var time: Double
    var endTime: Double
    var kind: SpanKind
    var bpm: Double
    var scroll: Double
    var isGogo: Bool
}

struct BarLine: Equatable {
    var time: Double
    var bpm: Double
    var scroll: Double
}

struct Chart {
    var course: Course
    var level: Int
    var hitNotes: [HitNote] = []
    var spans: [SpanNote] = []
    var barLines: [BarLine] = []
    var gogoRanges: [ClosedRange<Double>] = []

    var endTime: Double {
        max(hitNotes.last?.time ?? 0, spans.map(\.endTime).max() ?? 0)
    }

    func isGogo(at t: Double) -> Bool {
        gogoRanges.contains { $0.contains(t) }
    }
}

struct SongInfo {
    var title = ""
    var subtitle = ""
    var bpm = 120.0
    var wave: String?
    var offset = 0.0
    var demoStart = 0.0
    var charts: [Course: Chart] = [:]

    var courses: [Course] { charts.keys.sorted() }
}
