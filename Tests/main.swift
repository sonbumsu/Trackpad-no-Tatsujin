import Foundation

// XCTest 없이 돌아가는 최소 테스트 러너 (Command Line Tools 환경용)
var failures = 0
var checks = 0

func expect(_ cond: @autoclosure () -> Bool, _ msg: String, line: Int = #line) {
    checks += 1
    if !cond() {
        failures += 1
        print("  ✗ \(msg) (line \(line))")
    }
}

func near(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) < eps }

func test(_ name: String, _ body: () -> Void) {
    print("• \(name)")
    body()
}

// MARK: - TJA

test("기본 마디와 노트 시각") {
    let info = TJAParser.parse("""
    TITLE:Test
    BPM:120
    OFFSET:-1.0
    COURSE:Oni
    LEVEL:9
    #START
    1020,
    3,
    #END
    """)
    let c = info.charts[.oni]!
    expect(info.title == "Test", "제목")
    expect(c.level == 9, "레벨")
    expect(c.hitNotes.count == 3, "노트 3개")
    expect(near(c.hitNotes[0].time, 1.0), "첫 노트는 -OFFSET 시각")
    expect(near(c.hitNotes[1].time, 2.0), "4분음표 간격 0.5초 × 2")
    expect(c.hitNotes[1].type == .ka, "캇")
    expect(c.hitNotes[2].isBig && near(c.hitNotes[2].time, 3.0), "대동은 다음 마디 시작")
    expect(c.barLines.count == 2, "마디선 2개")
}

test("BPM 변경, 박자, 지연, 고고타임") {
    let c = TJAParser.parse("""
    BPM:120
    #START
    #MEASURE 2/4
    11,
    #BPMCHANGE 240
    #GOGOSTART
    1,
    #GOGOEND
    #DELAY 0.5
    1,
    #END
    """).charts[.oni]!
    expect(c.hitNotes.count == 4, "노트 4개")
    expect(near(c.hitNotes[1].time, 0.5), "2/4 마디의 두 번째 노트")
    expect(near(c.hitNotes[2].time, 1.0), "2/4 마디 길이 1초")
    expect(c.hitNotes[2].isGogo && !c.hitNotes[3].isGogo, "고고 구간")
    expect(near(c.hitNotes[3].time, 1.0 + 0.5 + 0.5), "BPM 240 2/4 마디 0.5초 + DELAY 0.5")
}

test("마디 중간 BPM 변경") {
    let c = TJAParser.parse("""
    BPM:120
    #START
    11
    #BPMCHANGE 60
    11,
    1,
    #END
    """).charts[.oni]!
    // 4분음표 4개: 0.5, 0.5 간격 이후 BPM 60에서 1초 간격
    expect(near(c.hitNotes[2].time, 1.0), "변경 전 두 노트")
    expect(near(c.hitNotes[3].time, 2.0), "변경 후 1초 간격")
    expect(near(c.hitNotes[4].time, 3.0), "다음 마디")
}

test("연타와 풍선") {
    let c = TJAParser.parse("""
    BPM:120
    BALLOON:7
    #START
    5008,
    7008,
    #END
    """).charts[.oni]!
    expect(c.spans.count == 2, "구간 2개")
    expect(c.spans[0].kind == .roll && near(c.spans[0].endTime, 1.5), "연타 끝")
    expect(c.spans[1].kind == .balloon(required: 7), "풍선 횟수")
}

test("분기는 달인 분기만") {
    let c = TJAParser.parse("""
    BPM:120
    #START
    #BRANCHSTART p,1,2
    #N
    1,
    #E
    11,
    #M
    1111,
    #BRANCHEND
    2,
    #END
    """).charts[.oni]!
    expect(c.hitNotes.count == 5, "달인 4개 + 공통 1개")
    expect(near(c.hitNotes[4].time, 2.0), "분기 뒤 시각 유지")
}

test("여러 난이도와 P2 무시") {
    let info = TJAParser.parse("""
    BPM:120
    COURSE:Easy
    #START
    1,
    #END
    COURSE:Hard
    #START P1
    11,
    #END
    #START P2
    1111,
    #END
    """)
    expect(info.courses == [.easy, .hard], "난이도 목록")
    expect(info.charts[.hard]!.hitNotes.count == 2, "P1만 사용")
}

// MARK: - 판정

func session(_ tja: String, course: String = "Oni") -> GameSession {
    GameSession(chart: TJAParser.parse("BPM:120\nCOURSE:\(course)\n#START\n\(tja)\n#END").charts.values.first!)
}

test("판정 범위") {
    let s = session("1111,")
    expect(s.hit(.don, at: 0.010) == [.judged(note: 0, .good)], "良")
    expect(s.hit(.don, at: 0.560) == [.judged(note: 1, .ok)], "可")
    expect(s.hit(.don, at: 1.100) == [.judged(note: 2, .bad)], "不可")
    expect(s.hit(.don, at: 1.300).isEmpty, "너무 이른 입력은 무시")
    expect(s.combo == 0 && s.maxCombo == 2, "不可에서 콤보 끊김")
    expect(s.update(now: 1.7) == [.missed(note: 3)], "놓침")
}

test("쉬움은 판정이 넉넉하다") {
    let s = session("1,", course: "Easy")
    expect(s.hit(.don, at: 0.040) == [.judged(note: 0, .good)], "쉬움 良 ±42ms")
}

test("판정 폭 배율") {
    let chart = TJAParser.parse("BPM:120\n#START\n11,\n#END").charts[.oni]!
    let s = GameSession(chart: chart, judgeScale: 1.5)
    expect(s.hit(.don, at: 0.035) == [.judged(note: 0, .good)], "1.5배면 ±37.5ms까지 良")
    expect(s.hit(.don, at: 1.150) == [.judged(note: 1, .bad)], "1.5배면 ±162ms까지 판정")
}

test("색이 다르면 같은 색 노트를 먼저 찾는다") {
    let s = session("1200000000000000,")
    // 16분 간격(0.125초): 캇을 조금 일찍 쳐도 캇 노트에 맞는다
    expect(s.hit(.ka, at: 0.090) == [.judged(note: 1, .ok)], "캇 노트")
    expect(s.hit(.ka, at: 0.0).isEmpty == false, "남은 동 노트에 캇 → 不可")
    expect(s.results[0] == .bad, "동 노트 不可")
}

test("대음표 양손 보너스") {
    let s = session("3030,")
    _ = s.hit(.don, at: 0)
    let before = s.score
    expect(s.hit(.don, at: 0.03) == [.bigBonus(note: 0)], "50ms 안 두 번째 타격")
    expect(s.score == before * 2, "점수 두 배")
    _ = s.hit(.don, at: 1.0)
    expect(s.hit(.don, at: 1.08) != [.bigBonus(note: 1)], "50ms 넘으면 보너스 없음")
}

test("연타·풍선") {
    let s = GameSession(chart: TJAParser.parse("BPM:120\nBALLOON:3\n#START\n5008,\n7008,\n#END").charts[.oni]!)
    expect(s.hit(.ka, at: 0.2) == [.rollHit(span: 0, count: 1)], "연타")
    expect(s.hit(.don, at: 0.3) == [.rollHit(span: 0, count: 2)], "연타 2")
    expect(s.hit(.ka, at: 2.1).isEmpty, "풍선은 캇 무시")
    expect(s.hit(.don, at: 2.1) == [.balloonHit(span: 1, remaining: 2)], "풍선")
    _ = s.hit(.don, at: 2.2)
    expect(s.hit(.don, at: 2.3) == [.balloonPopped(span: 1)], "풍선 터짐")
    expect(s.hit(.don, at: 2.4).isEmpty, "터진 뒤 입력 없음")
}

test("점수·게이지·왕관") {
    let s = session("1111,1111,")
    for i in 0..<8 { _ = s.hit(.don, at: Double(i) * 0.5) }
    expect(s.score == s.noteScore * 8, "전부 良")
    expect(s.noteScore == 125_000, "1노트 점수")
    expect(s.gauge == 100, "게이지 가득")
    expect(s.crown == .allGood, "전량")
}

// MARK: - 기본 수록곡

test("기본 수록곡 채보") {
    for song in DemoSong.all {
        let info = TJAParser.parse(song.tja)
        expect(info.title == song.title, "\(song.title) 제목")
        expect(info.courses.count == song.levels.count, "\(song.title) 난이도 수")
        for (course, chart) in info.charts {
            expect(!chart.hitNotes.isEmpty, "\(song.title) \(course) 노트")
            expect(chart.endTime < song.duration, "\(song.title) \(course) 음악 길이 안")
            expect(chart.spans.contains { if case .balloon = $0.kind { return true } else { return false } },
                   "\(song.title) \(course) 풍선")
            expect(!chart.gogoRanges.isEmpty, "\(song.title) 고고")
        }
    }
    let audio = DemoSong.stroll.renderAudio()
    expect(audio.count == Int(DemoSong.stroll.duration * 44_100), "음악 길이")
    expect(audio.contains { abs($0) > 0.5 }, "음악 소리 있음")
}

// MARK: - 자동 채보

test("자동 채보: 데모곡 템포와 박 위치") {
    for (song, bpm) in [(DemoSong.festival, 150.0)] {
        let audio = song.renderAudio()
        let start = Date()
        let (tja, a) = AutoCharter.makeTJA(samples: audio, sampleRate: 44_100, title: "t", wave: "a.wav")
        print("    BPM \(a.bpm), 첫 마디 \(String(format: "%.3f", a.firstBar))s, \(String(format: "%.2f", Date().timeIntervalSince(start)))초")
        expect(abs(a.bpm - bpm) < 0.3, "BPM \(bpm) 검출")
        let beat = 60 / bpm
        let phase = a.firstBar.truncatingRemainder(dividingBy: beat)
        expect(min(phase, beat - phase) < 0.025, "박 위치 ±25ms")
        let info = TJAParser.parse(tja)
        expect(info.courses == [.easy, .normal, .hard, .oni], "네 난이도")
        let counts = info.courses.map { info.charts[$0]!.hitNotes.count }
        expect(counts == counts.sorted() && counts[0] > 10, "난이도 순으로 노트 증가 \(counts)")
        // 생성한 노트가 실제 박(16분 격자)에 붙어 있는지
        let oni = info.charts[.oni]!
        let off = oni.hitNotes.filter { n in
            let r = n.time.truncatingRemainder(dividingBy: beat / 4)
            return min(r, beat / 4 - r) > 0.03
        }
        expect(off.isEmpty, "노트가 16분 격자 위에 있음")
    }
}

test("자동 채보: 필인에 연타·풍선") {
    // 128 BPM, 24마디. 박마다 킥, 8분마다 하이햇, 8·16·24번째 마디 뒤 두 박은 16분 스네어 필인.
    // 16번째 마디는 점점 커지고 17마디부터 크게(고고타임 후보).
    let sr = 44_100.0, bpm = 128.0, beat = 60 / bpm, measures = 24
    var audio = [Float](repeating: 0, count: Int(Double(measures) * 4 * beat * sr) + Int(sr))
    var seed: UInt32 = 1
    func noise() -> Double { seed = seed &* 1_664_525 &+ 1_013_904_223; return Double(seed) / Double(UInt32.max) * 2 - 1 }
    func add(at t: Double, length: Double, gain: Double, _ f: (Double) -> Double) {
        let s0 = Int(t * sr)
        for i in 0..<Int(length * sr) where s0 + i < audio.count {
            let x = Double(i) / sr
            audio[s0 + i] += Float(gain * exp(-x / (length / 4)) * f(x))
        }
    }
    let lead = 0.5
    for m in 0..<measures {
        let gain = m >= 16 ? 1.0 : m == 15 ? 0.8 : 0.45
        for b in 0..<4 {
            let t = lead + (Double(m * 4 + b)) * beat
            add(at: t, length: 0.25, gain: gain) { sin(2 * .pi * 60 * $0) }
            for e in 0..<2 { add(at: t + Double(e) * beat / 2, length: 0.05, gain: gain * 0.3) { _ in noise() } }
        }
        if m % 8 == 7 {
            for k in 0..<8 {
                let t = lead + (Double(m * 4 + 2) + Double(k) / 4) * beat
                add(at: t, length: 0.08, gain: gain * 0.8) { sin(2 * .pi * 220 * $0) * 0.5 + noise() * 0.5 }
            }
        }
    }
    let (tja, a) = AutoCharter.makeTJA(samples: audio, sampleRate: sr, title: "t", wave: "a.wav")
    expect(abs(a.bpm - bpm) < 0.3, "BPM 검출 \(a.bpm)")
    let info = TJAParser.parse(tja)
    let oni = info.charts[.oni]!
    print("    귀신 연타·풍선: \(oni.spans.map { "\(String(format: "%.2f", $0.time))s \($0.kind)" })")
    expect(oni.spans.count >= 2, "귀신에 연타가 들어감")
    let isBalloon = { (s: SpanNote) -> Bool in if case .balloon = s.kind { return true } else { return false } }
    expect(oni.spans.filter(isBalloon).map { Int(($0.time - oni.barLines[0].time) / beat / 4) } == [15], "커지는 곳(16번째 마디)만 풍선")
    for course in info.courses {
        let chart = info.charts[course]!
        let inside = chart.hitNotes.filter { n in chart.spans.contains { n.time >= $0.time - 0.001 && n.time <= $0.endTime + 0.001 } }
        expect(inside.isEmpty, "\(course) 연타 구간 안에 노트 없음")
        // 연타는 필인이 있는 마디의 3박째에서 시작
        for span in chart.spans {
            let rel = (span.time - info.charts[course]!.barLines[0].time) / beat
            expect(abs(rel.truncatingRemainder(dividingBy: 32) - 30) < 0.1, "\(course) 연타가 필인 위치 \(rel)")
        }
    }
    expect(info.charts[.easy]!.spans.count <= 1, "쉬움은 연타 하나까지")
    let noBalloon = [Course.easy, .normal].allSatisfy { c in
        !info.charts[c]!.spans.contains(where: isBalloon)
    }
    expect(noBalloon, "쉬움·보통엔 풍선 없음")
    let off = TJAParser.parse(AutoCharter.makeTJA(samples: audio, sampleRate: sr, title: "t", wave: "a.wav", spans: false).tja)
    expect(off.courses.allSatisfy { off.charts[$0]!.spans.isEmpty }, "끄면 연타 없음")
}

// MARK: - 기록

test("기록 저장") {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt-test-\(UUID()).json")
    let store = RecordStore(url: url)
    expect(store.submit(song: "a", course: .oni, score: 100, maxCombo: 5, crown: .cleared), "첫 기록은 최고")
    expect(!store.submit(song: "a", course: .oni, score: 50, maxCombo: 9, crown: .failed), "낮은 점수")
    let r = RecordStore(url: url).record(song: "a", course: .oni)!
    expect(r.bestScore == 100 && r.maxCombo == 9 && r.crown == .cleared && r.playCount == 2, "다시 읽기")
    try? FileManager.default.removeItem(at: url)
}

print(failures == 0 ? "\n✓ \(checks)개 통과" : "\n✗ \(failures)/\(checks)개 실패")
exit(failures == 0 ? 0 : 1)
