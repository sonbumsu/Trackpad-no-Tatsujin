import Foundation

/// 코드로 만든 기본 수록곡. 채보(TJA 텍스트)와 음악을 같은 마디 구성에서 만든다.
struct DemoSong {
    enum Layer: Hashable { case kick, snare, hat, bass, arp, lead, pad, finale }

    struct Section {
        var bpm: Double
        var measures: Int
        var layers: Set<Layer>
        var gogo = false
        var patterns: [Course: [String]]
    }

    struct Chord {
        var root: Int
        var minor: Bool
        var tones: [Int] { [root, root + (minor ? 3 : 4), root + 7] }
    }

    var title: String
    var subtitle: String
    var levels: [Course: Int]
    var balloon: [Course: Int]
    var progression: [Chord]
    var sections: [Section]

    private var courses: [Course] { levels.keys.sorted() }

    private var sectionStarts: [Double] {
        var t = 0.0
        return sections.map { s in
            defer { t += Double(s.measures) * 240 / s.bpm }
            return t
        }
    }

    var duration: Double {
        zip(sections, sectionStarts).map { $1 + Double($0.measures) * 240 / $0.bpm }.last! + 2.5
    }

    var tja: String {
        let chorus = sections.firstIndex { $0.gogo }.map { sectionStarts[$0] } ?? 0
        var out = """
        TITLE:\(title)
        SUBTITLE:--\(subtitle)
        BPM:\(sections[0].bpm)
        OFFSET:0
        DEMOSTART:\(chorus)

        """
        for course in courses {
            let patterns = sections.flatMap { $0.patterns[course] ?? [] }
            let balloons = patterns.joined().filter { $0 == "7" }.map { _ in String(balloon[course] ?? 5) }
            out += "\nCOURSE:\(course.rawValue)\nLEVEL:\(levels[course]!)\n"
            if !balloons.isEmpty { out += "BALLOON:\(balloons.joined(separator: ","))\n" }
            out += "#START\n"
            var bpm = sections[0].bpm
            for s in sections {
                if s.bpm != bpm { out += "#BPMCHANGE \(s.bpm)\n"; bpm = s.bpm }
                if s.gogo { out += "#GOGOSTART\n" }
                let measures = s.patterns[course] ?? Array(repeating: "0", count: s.measures)
                precondition(measures.count == s.measures, "\(title) \(course) 마디 수 불일치")
                for m in measures { out += m + ",\n" }
                if s.gogo { out += "#GOGOEND\n" }
            }
            out += "#END\n"
        }
        return out
    }

    func renderAudio() -> [Float] {
        var synth = Synth(duration: duration)
        var measureIndex = 0
        for (s, start) in zip(sections, sectionStarts) {
            let beat = 60 / s.bpm
            for m in 0..<s.measures {
                let t0 = start + Double(m) * 4 * beat
                let chord = progression[measureIndex % progression.count]
                measureIndex += 1
                render(s.layers, chord: chord, at: t0, beat: beat, into: &synth)
            }
        }
        synth.normalize()
        return synth.samples
    }

    private func render(_ layers: Set<Layer>, chord: Chord, at t0: Double, beat: Double, into s: inout Synth) {
        let eighth = beat / 2
        if layers.contains(.finale) {
            s.add(at: t0, duration: 0.5, Synth.kick)
            s.add(at: t0, duration: 0.4, Synth.snare)
            let tones = chord.tones.map { $0 + 12 } + [chord.root]
            s.add(at: t0, duration: 2.4) { Synth.pad($0, midis: tones, length: 2.4) * 2.2 }
            s.add(at: t0, duration: 1.2) { Synth.bass($0, midi: chord.root - 24) }
            return
        }
        for b in 0..<4 {
            let t = t0 + Double(b) * beat
            if layers.contains(.kick) { s.add(at: t, duration: 0.4, Synth.kick) }
            if layers.contains(.snare), b % 2 == 1 { s.add(at: t, duration: 0.3, Synth.snare) }
        }
        if layers.contains(.kick), layers.contains(.lead) {
            s.add(at: t0 + 3.5 * beat, duration: 0.4, Synth.kick)
        }
        for e in 0..<8 {
            let t = t0 + Double(e) * eighth
            if layers.contains(.hat) { s.add(at: t, duration: 0.1, Synth.hat) }
            if layers.contains(.bass) {
                let note = chord.root - 24 + (e % 4 == 2 ? 12 : 0)
                s.add(at: t, duration: eighth * 0.95) { Synth.bass($0, midi: note) }
            }
            if layers.contains(.lead) {
                let melody = [3, 2, 1, 2, 0, 1, 2, 1]
                let tones = chord.tones + [chord.root + 12]
                let note = tones[melody[e]] + 12
                let len = eighth * 0.92
                s.add(at: t, duration: len) { Synth.lead($0, midi: note, length: len) }
            }
        }
        if layers.contains(.arp) {
            let up = chord.tones + [chord.root + 12]
            let seq = up + up.reversed()
            for i in 0..<16 {
                let note = seq[i % seq.count] + 12
                s.add(at: t0 + Double(i) * beat / 4, duration: 0.3) { Synth.pluck($0, midi: note) }
            }
        }
        if layers.contains(.pad) {
            let len = beat * 4
            s.add(at: t0, duration: len) { Synth.pad($0, midis: chord.tones, length: len) }
        }
    }
}

extension DemoSong {
    static let all: [DemoSong] = [festival, stroll]

    /// 150 BPM, 가 단조. 네 난이도 모두 있다.
    static let festival = DemoSong(
        title: "트랙패드 페스티벌",
        subtitle: "트랙패드의 달인 기본 수록곡",
        levels: [.easy: 3, .normal: 5, .hard: 7, .oni: 8],
        balloon: [.easy: 5, .normal: 8, .hard: 12, .oni: 16],
        progression: [Chord(root: 57, minor: true), Chord(root: 53, minor: false),
                      Chord(root: 48, minor: false), Chord(root: 55, minor: false)],
        sections: [
            Section(bpm: 150, measures: 2, layers: [.kick, .hat], patterns: [
                .easy: ["0", "1010"],
                .normal: ["0", "10101020"],
                .hard: ["0", "10101020"],
                .oni: ["0", "1011102010112000"],
            ]),
            Section(bpm: 150, measures: 8, layers: [.kick, .snare, .hat, .bass], patterns: [
                .easy: ["1010", "1010", "1020", "1000", "1010", "1020", "2020", "1000"],
                .normal: ["10101020", "10101000", "10201020", "10002000",
                          "10101020", "10101000", "20202020", "30000000"],
                .hard: ["1010102010101020", "1000102010002020", "1010201010102000", "3000200020000000",
                        "1010102010101020", "1000102010002020", "1122112010102000", "3000300030000000"],
                .oni: ["1011102010112020", "1011102011102000", "1121102011211020", "3000202010102020",
                       "1011102010112020", "1011102011102000", "1122112211221120", "3000400030004000"],
            ]),
            Section(bpm: 150, measures: 8, layers: [.kick, .snare, .hat, .bass, .arp], patterns: [
                .easy: ["1020", "1020", "1120", "1000", "2010", "2010", "1122", "3000"],
                .normal: ["11201120", "10201000", "11201120", "30003000",
                          "22102210", "20102000", "11221122", "30000000"],
                .hard: ["1120112011201020", "1000202010002000", "1120112011202020", "3000300030000000",
                        "2210221022101020", "2000101020002000", "1122112211221122", "3000000040000000"],
                .oni: ["1121112111211120", "1020112010201120", "1121112111222020", "3000300030003000",
                       "2212221222122210", "2010221020102210", "1122112211221122", "3000304030003040"],
            ]),
            Section(bpm: 150, measures: 8, layers: [.kick, .snare, .hat, .bass, .arp, .lead], gogo: true, patterns: [
                .easy: ["3010", "2010", "3010", "2000", "1010", "2020", "5000", "0080"],
                .normal: ["30101020", "10201120", "30101020", "11201000",
                          "30102010", "20101120", "60000000", "00008000"],
                .hard: ["3010102010201120", "1010201011202000", "3010102010201120", "1120112030000000",
                        "3011201030112010", "1120112011201120", "5000000000000000", "0000000080000000"],
                .oni: ["3011102010211120", "1011201011221020", "3011102010211120", "1122112230003000",
                       "3011201130112011", "1122112211221122", "6000000000000000", "0000000080003030"],
            ]),
            Section(bpm: 150, measures: 2, layers: [.kick, .hat, .bass, .arp], patterns: [
                .easy: ["7000", "0080"], .normal: ["7000", "0080"],
                .hard: ["7000", "0080"], .oni: ["7000", "0080"],
            ]),
            Section(bpm: 150, measures: 1, layers: [.finale], patterns: [
                .easy: ["3000"], .normal: ["3000"], .hard: ["3000"], .oni: ["3000"],
            ]),
        ])

    /// 112 BPM, 다 장조. 끝부분에서 96 BPM으로 느려진다.
    static let stroll = DemoSong(
        title: "느긋한 산책",
        subtitle: "트랙패드의 달인 기본 수록곡",
        levels: [.easy: 2, .normal: 4, .hard: 6],
        balloon: [.easy: 4, .normal: 6, .hard: 10],
        progression: [Chord(root: 48, minor: false), Chord(root: 55, minor: false),
                      Chord(root: 57, minor: true), Chord(root: 53, minor: false)],
        sections: [
            Section(bpm: 112, measures: 2, layers: [.kick, .hat, .pad], patterns: [
                .easy: ["0", "1000"],
                .normal: ["0", "10101000"],
                .hard: ["0", "10101020"],
            ]),
            Section(bpm: 112, measures: 8, layers: [.kick, .snare, .hat, .bass, .pad], patterns: [
                .easy: ["1000", "1000", "2000", "1010", "1000", "2000", "1010", "2000"],
                .normal: ["10101000", "20202000", "10102020", "10000000",
                          "10101000", "20202000", "11221000", "30000000"],
                .hard: ["10101020", "10201120", "10101020", "11202000",
                        "10101020", "10201120", "11221122", "30003000"],
            ]),
            Section(bpm: 112, measures: 8, layers: [.kick, .snare, .hat, .bass, .arp, .lead], gogo: true, patterns: [
                .easy: ["1010", "2020", "1010", "2000", "1020", "1020", "5000", "0080"],
                .normal: ["30102010", "10201020", "30102010", "22201000",
                          "30102010", "10201022", "50000000", "00008000"],
                .hard: ["3010102010201120", "1020102011201000", "3010102010201120", "1122112030000000",
                        "3010201030102010", "1120112011201120", "6000000000000000", "0000000080000000"],
            ]),
            Section(bpm: 96, measures: 2, layers: [.kick, .hat, .bass, .pad], patterns: [
                .easy: ["7000", "0080"], .normal: ["7000", "0080"], .hard: ["7000", "0080"],
            ]),
            Section(bpm: 96, measures: 1, layers: [.finale], patterns: [
                .easy: ["3000"], .normal: ["3000"], .hard: ["3000"],
            ]),
        ])
}
