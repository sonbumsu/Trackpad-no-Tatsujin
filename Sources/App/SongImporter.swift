import AVFoundation
import Foundation

/// 음악 파일이나 TJA 곡 폴더를 곡 폴더(Songs/)로 가져온다
enum SongImporter {
    struct Outcome {
        var title: String
        var message: String
        var ok: Bool
    }

    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "mp4"]

    /// 오래 걸릴 수 있으니 백그라운드에서 부른다
    static func importItems(_ urls: [URL], spans: Bool = true) -> [Outcome] {
        var outcomes: [Outcome] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                outcomes += importFolder(url, spans: spans)
            } else if ext == "tja" {
                outcomes.append(importTJA(url))
            } else if audioExtensions.contains(ext) {
                outcomes.append(importAudio(url, spans: spans))
            } else if ext == "ogg" {
                outcomes.append(Outcome(title: url.lastPathComponent,
                                        message: "ogg는 macOS에서 열 수 없어요. mp3나 m4a로 바꿔 주세요", ok: false))
            } else {
                outcomes.append(Outcome(title: url.lastPathComponent, message: "지원하지 않는 파일이에요", ok: false))
            }
        }
        return outcomes
    }

    private static func importFolder(_ folder: URL, spans: Bool) -> [Outcome] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        if let tja = files.first(where: { $0.pathExtension.lowercased() == "tja" }) {
            return [importTJA(tja)]
        }
        let audio = files.filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        if audio.isEmpty {
            return [Outcome(title: folder.lastPathComponent, message: "음악 파일이나 TJA가 없어요", ok: false)]
        }
        return audio.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { importAudio($0, spans: spans) }
    }

    /// TJA와 그 TJA가 가리키는 음악 파일을 새 폴더로 복사한다
    private static func importTJA(_ tja: URL) -> Outcome {
        guard let data = try? Data(contentsOf: tja) else {
            return Outcome(title: tja.lastPathComponent, message: "파일을 읽을 수 없어요", ok: false)
        }
        let info = TJAParser.parse(TJAParser.decode(data))
        let title = info.title.isEmpty ? tja.deletingPathExtension().lastPathComponent : info.title
        guard !info.charts.isEmpty else { return Outcome(title: title, message: "채보가 비어 있어요", ok: false) }
        let source = tja.deletingLastPathComponent()
        if source.standardizedFileURL.path.hasPrefix(SongLibrary.songsFolder.standardizedFileURL.path) {
            return Outcome(title: title, message: "이미 곡 폴더에 있어요", ok: true)
        }
        do {
            let dest = try makeSongFolder(title)
            try FileManager.default.copyItem(at: tja, to: dest.appendingPathComponent(tja.lastPathComponent))
            if let wave = info.wave {
                let audio = source.appendingPathComponent(wave)
                if FileManager.default.fileExists(atPath: audio.path) {
                    try FileManager.default.copyItem(at: audio, to: dest.appendingPathComponent(wave))
                } else {
                    return Outcome(title: title, message: "채보는 넣었지만 음악 파일(\(wave))이 없어요", ok: false)
                }
            }
            return Outcome(title: title, message: "TJA 채보 추가", ok: true)
        } catch {
            return Outcome(title: title, message: "복사 실패: \(error.localizedDescription)", ok: false)
        }
    }

    /// 음악 파일을 분석해 자동 채보를 만든다
    private static func importAudio(_ url: URL, spans: Bool) -> Outcome {
        let title = url.deletingPathExtension().lastPathComponent
        let samples: [Float]
        let sampleRate: Double
        do {
            (samples, sampleRate) = try readMono(url)
        } catch {
            return Outcome(title: title, message: "음악 파일을 열 수 없어요", ok: false)
        }
        guard Double(samples.count) / sampleRate >= 15 else {
            return Outcome(title: title, message: "15초보다 짧은 음악은 채보를 만들 수 없어요", ok: false)
        }
        let (tja, analysis) = AutoCharter.makeTJA(samples: samples, sampleRate: sampleRate,
                                                  title: title, wave: url.lastPathComponent, spans: spans)
        do {
            let dest = try makeSongFolder(title)
            try FileManager.default.copyItem(at: url, to: dest.appendingPathComponent(url.lastPathComponent))
            try tja.write(to: dest.appendingPathComponent("song.tja"), atomically: true, encoding: .utf8)
            return Outcome(title: title, message: "자동 채보 · BPM \(String(format: "%g", analysis.bpm))", ok: true)
        } catch {
            return Outcome(title: title, message: "저장 실패: \(error.localizedDescription)", ok: false)
        }
    }

    private static func readMono(_ url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let chunk: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var out: [Float] = []
        out.reserveCapacity(Int(file.length))
        let channels = Int(format.channelCount)
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: chunk)
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let data = buffer.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }
            for i in 0..<n {
                var s: Float = 0
                for c in 0..<channels { s += data[c][i] }
                out.append(s / Float(channels))
            }
        }
        return (out, format.sampleRate)
    }

    private static func makeSongFolder(_ title: String) throws -> URL {
        let fm = FileManager.default
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "_")
        var dest = SongLibrary.songsFolder.appendingPathComponent(safe, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = SongLibrary.songsFolder.appendingPathComponent("\(safe) \(n)", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        return dest
    }
}
