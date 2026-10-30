import CryptoKit
import Foundation

struct SongEntry {
    enum Audio {
        case demo(DemoSong)
        case file(URL?)
    }

    var id: String
    var info: SongInfo
    var audio: Audio

    var isBuiltIn: Bool {
        if case .demo = audio { return true }
        return false
    }

    static func id(for tja: String) -> String {
        SHA256.hash(data: Data(tja.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}

enum SongLibrary {
    /// TATSUJIN_DATA 환경변수로 저장 위치를 바꿀 수 있다 (시험용)
    static let supportFolder: URL = {
        if let custom = ProcessInfo.processInfo.environment["TATSUJIN_DATA"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("Trackpad-no-Tatsujin", isDirectory: true)
        // 예전 이름(리듬트릭) 시절의 곡과 기록을 옮겨 온다
        let legacy = base.appendingPathComponent("RhythmTrick", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: folder.path), fm.fileExists(atPath: legacy.path) {
            try? fm.moveItem(at: legacy, to: folder)
        }
        return folder
    }()

    static var songsFolder: URL { supportFolder.appendingPathComponent("Songs", isDirectory: true) }

    static func load() -> [SongEntry] {
        let demos = DemoSong.all.map { song in
            let tja = song.tja
            return SongEntry(id: SongEntry.id(for: tja), info: TJAParser.parse(tja), audio: .demo(song))
        }
        return demos + scanUserSongs()
    }

    private static func scanUserSongs() -> [SongEntry] {
        let fm = FileManager.default
        try? fm.createDirectory(at: songsFolder, withIntermediateDirectories: true)
        guard let walker = fm.enumerator(at: songsFolder, includingPropertiesForKeys: nil) else { return [] }
        var songs: [SongEntry] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "tja" {
            guard let data = try? Data(contentsOf: url) else { continue }
            let text = TJAParser.decode(data)
            var info = TJAParser.parse(text)
            guard !info.charts.isEmpty else { continue }
            if info.title.isEmpty { info.title = url.deletingPathExtension().lastPathComponent }
            let audio = info.wave.map { url.deletingLastPathComponent().appendingPathComponent($0) }
            songs.append(SongEntry(id: SongEntry.id(for: text), info: info,
                                   audio: .file(audio.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil })))
        }
        return songs.sorted { $0.info.title.localizedStandardCompare($1.info.title) == .orderedAscending }
    }
}

/// 기본 수록곡 음악은 처음 쓸 때 한 번 합성해서 보관한다
enum DemoAudioCache {
    private static var cache: [String: [Float]] = [:]
    private static let lock = NSLock()

    static func prewarm() {
        DispatchQueue.global(qos: .userInitiated).async {
            for song in DemoSong.all { _ = samples(for: song) }
        }
    }

    /// 합성 중이면 끝날 때까지 기다린다
    static func samples(for song: DemoSong) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        if let s = cache[song.title] { return s }
        let s = song.renderAudio()
        cache[song.title] = s
        return s
    }
}
