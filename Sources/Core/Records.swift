import Foundation

struct PlayRecord: Codable, Equatable {
    var bestScore = 0
    var maxCombo = 0
    var crown: Crown = .failed
    var playCount = 0
}

/// 곡ID → 난이도 → 최고 기록. JSON 파일 하나에 저장한다.
final class RecordStore {
    private let url: URL
    private var records: [String: [String: PlayRecord]] = [:]

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [String: PlayRecord]].self, from: data) {
            records = decoded
        }
    }

    func record(song: String, course: Course) -> PlayRecord? {
        records[song]?[key(course)]
    }

    /// 기록을 반영하고 최고 점수를 갱신했는지 돌려준다
    @discardableResult
    func submit(song: String, course: Course, score: Int, maxCombo: Int, crown: Crown) -> Bool {
        var r = records[song]?[key(course)] ?? PlayRecord()
        let isBest = score > r.bestScore
        r.bestScore = max(r.bestScore, score)
        r.maxCombo = max(r.maxCombo, maxCombo)
        r.crown = max(r.crown, crown)
        r.playCount += 1
        records[song, default: [:]][key(course)] = r
        save()
        return isBest
    }

    private func key(_ c: Course) -> String { String(c.rawValue) }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(records).write(to: url, options: .atomic)
    }
}
