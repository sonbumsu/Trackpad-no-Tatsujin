import Foundation

/// TJA 채보 파서. 분기 채보는 달인(#M) 분기만 읽는다.
enum TJAParser {

    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) {
            return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
        }
        if let s = String(data: data, encoding: .shiftJIS) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(_ text: String) -> SongInfo {
        var info = SongInfo()
        var course: Course = .oni
        var level = 0
        var balloons: [Int] = []
        var body: [String]?
        var discardBody = false

        for raw in text.components(separatedBy: .newlines) {
            var line = raw
            if let r = line.range(of: "//") { line = String(line[..<r.lowerBound]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let upper = line.uppercased()

            if body != nil {
                if upper.hasPrefix("#END") {
                    if !discardBody, info.charts[course] == nil {
                        info.charts[course] = buildChart(lines: body!, course: course, level: level,
                                                         balloons: balloons, bpm: info.bpm, offset: info.offset)
                    }
                    body = nil
                } else {
                    body!.append(line)
                }
                continue
            }

            if upper.hasPrefix("#START") {
                let arg = upper.dropFirst(6).trimmingCharacters(in: .whitespaces)
                discardBody = arg == "P2"
                body = []
                continue
            }

            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "TITLE": info.title = value
            case "SUBTITLE":
                var v = value
                if v.hasPrefix("--") || v.hasPrefix("++") { v = String(v.dropFirst(2)) }
                info.subtitle = v
            case "BPM": info.bpm = Double(value) ?? info.bpm
            case "WAVE": info.wave = value.isEmpty ? nil : value
            case "OFFSET": info.offset = Double(value) ?? 0
            case "DEMOSTART": info.demoStart = Double(value) ?? 0
            case "COURSE":
                course = Course.parse(value) ?? .oni
                level = 0
                balloons = []
            case "LEVEL": level = Int(value) ?? 0
            case "BALLOON", "BALLOONMAS":
                if key == "BALLOON" || balloons.isEmpty {
                    balloons = value.split(separator: ",").compactMap {
                        Int($0.trimmingCharacters(in: .whitespaces))
                    }
                }
            default: break
            }
        }
        return info
    }

    private enum Item {
        case note(Character)
        case command(String, String)
    }

    private static func buildChart(lines: [String], course: Course, level: Int,
                                   balloons: [Int], bpm initialBPM: Double, offset: Double) -> Chart {
        var chart = Chart(course: course, level: level)
        var t = -offset
        var bpm = initialBPM
        var scroll = 1.0
        var measureBeats = 4.0
        var gogoStart: Double?
        var barlineOn = true
        var skipBranch = false
        var balloonIndex = 0
        var pending: (time: Double, kind: SpanKind, bpm: Double, scroll: Double, gogo: Bool)?
        var items: [Item] = []

        func apply(_ name: String, _ arg: String) {
            switch name {
            case "#BPMCHANGE": bpm = Double(arg) ?? bpm
            case "#MEASURE":
                let parts = arg.split(separator: "/").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if parts.count == 2, parts[1] > 0 { measureBeats = 4 * parts[0] / parts[1] }
            case "#SCROLL":
                // 복소수 스크롤("1+2i")은 실수부만 쓴다
                let real = arg.split(whereSeparator: { $0 == "+" || $0 == "i" }).first.map(String.init) ?? arg
                scroll = Double(real) ?? 1
            case "#DELAY": t += Double(arg) ?? 0
            case "#GOGOSTART": if gogoStart == nil { gogoStart = t }
            case "#GOGOEND":
                if let s = gogoStart { chart.gogoRanges.append(s...t) }
                gogoStart = nil
            case "#BARLINEOFF": barlineOn = false
            case "#BARLINEON": barlineOn = true
            default: break
            }
        }

        func place(_ ch: Character) {
            let gogo = gogoStart != nil
            func hit(_ type: DrumType, big: Bool) {
                chart.hitNotes.append(HitNote(time: t, type: type, isBig: big, bpm: bpm, scroll: scroll, isGogo: gogo))
            }
            func startSpan(_ kind: SpanKind) {
                if pending == nil { pending = (t, kind, bpm, scroll, gogo) }
            }
            switch ch {
            case "1": hit(.don, big: false)
            case "2": hit(.ka, big: false)
            case "3", "A": hit(.don, big: true)
            case "4", "B": hit(.ka, big: true)
            case "5": startSpan(.roll)
            case "6": startSpan(.bigRoll)
            case "7", "9":
                let required = balloonIndex < balloons.count ? balloons[balloonIndex] : 5
                balloonIndex += 1
                startSpan(.balloon(required: max(1, required)))
            case "8":
                if let p = pending {
                    chart.spans.append(SpanNote(time: p.time, endTime: max(t, p.time), kind: p.kind,
                                                bpm: p.bpm, scroll: p.scroll, isGogo: p.gogo))
                    pending = nil
                }
            default: break
            }
        }

        func flushMeasure() {
            var index = 0
            // 마디 앞쪽 명령(BPM, 박자 변경 등)을 먼저 적용하고 마디선을 긋는다
            while index < items.count, case let .command(name, arg) = items[index] {
                apply(name, arg)
                index += 1
            }
            if barlineOn { chart.barLines.append(BarLine(time: t, bpm: bpm, scroll: scroll)) }
            let noteCount = items.reduce(0) { n, item in
                if case .note = item { return n + 1 }
                return n
            }
            if noteCount == 0 {
                t += measureBeats * 60 / bpm
            } else {
                for item in items[index...] {
                    switch item {
                    case let .command(name, arg): apply(name, arg)
                    case let .note(ch):
                        place(ch)
                        t += measureBeats / Double(noteCount) * 60 / bpm
                    }
                }
            }
            items.removeAll()
        }

        for line in lines {
            if line.hasPrefix("#") {
                let parts = line.split(separator: " ", maxSplits: 1)
                let name = parts[0].uppercased()
                let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                switch name {
                case "#N", "#E": skipBranch = true
                case "#M", "#BRANCHEND": skipBranch = false
                default: if !skipBranch { items.append(.command(name, arg)) }
                }
                continue
            }
            if skipBranch { continue }
            for ch in line {
                if ch == "," {
                    flushMeasure()
                } else if ch.isNumber || "AB".contains(ch) {
                    items.append(.note(ch))
                }
            }
        }
        if items.contains(where: { if case .note = $0 { return true } else { return false } }) {
            flushMeasure()
        }
        if let s = gogoStart { chart.gogoRanges.append(s...t) }
        return chart
    }
}
