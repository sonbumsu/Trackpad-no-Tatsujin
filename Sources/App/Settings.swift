import CoreGraphics
import Foundation

enum InputLayout: Int, CaseIterable {
    case border, columns, split, fingers

    var displayName: String {
        switch self {
        case .border: return "테두리형 (가운데 동 · 테두리 캇)"
        case .columns: return "세로 띠형 (가운데 동 · 좌우 끝 캇)"
        case .split: return "좌우 분할형 (왼쪽 캇 · 오른쪽 동)"
        case .fingers: return "손가락 수형 (한 손가락 동 · 두 손가락 캇)"
        }
    }

    /// 트랙패드 정규화 좌표(0~1, 왼쪽 아래 원점)를 동/캇으로 나눈다
    func classify(_ p: CGPoint, rim: Double) -> DrumType {
        let x = Double(p.x), y = Double(p.y)
        switch self {
        case .border: return (x < rim || x > 1 - rim || y < rim || y > 1 - rim) ? .ka : .don
        case .columns: return (x < rim || x > 1 - rim) ? .ka : .don
        case .split: return x < 0.5 ? .ka : .don
        case .fingers: return .don
        }
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    init() {
        // 예전 번들 ID(리듬트릭) 시절의 설정을 한 번 옮겨 온다
        guard let id = Bundle.main.bundleIdentifier, d.persistentDomain(forName: id) == nil,
              let legacy = d.persistentDomain(forName: "app.rhythmtrick.mac") else { return }
        d.setPersistentDomain(legacy, forName: id)
    }

    private func double(_ key: String, _ fallback: Double) -> Double {
        d.object(forKey: key) == nil ? fallback : d.double(forKey: key)
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
    }

    var layout: InputLayout {
        get { InputLayout(rawValue: d.integer(forKey: "layout")) ?? .border }
        set { d.set(newValue.rawValue, forKey: "layout") }
    }

    /// 테 두께 (트랙패드 한 변 대비 비율)
    var rimSize: Double {
        get { double("rimSize", 0.18) }
        set { d.set(min(0.35, max(0.08, newValue)), forKey: "rimSize") }
    }

    static let judgeScales = [1.0, 1.25, 1.5, 1.75, 2.0]

    /// 판정 범위 배율 (1.0 = 원작)
    var judgeScale: Double {
        get { double("judgeScale", 1.5) }
        set { d.set(min(2, max(1, newValue)), forKey: "judgeScale") }
    }

    var bigHitWindowMs: Double {
        get { double("bigHitWindowMs", 50) }
        set { d.set(min(100, max(20, newValue)), forKey: "bigHitWindowMs") }
    }

    var scrollSpeed: Double {
        get { double("scrollSpeed", 1.0) }
        set { d.set(min(4, max(0.5, (newValue * 10).rounded() / 10)), forKey: "scrollSpeed") }
    }

    /// 양수면 판정·화면을 그만큼 늦춘다 (늦게 치는 경향 보정)
    var offsetMs: Double {
        get { double("offsetMs", 0) }
        set { d.set(min(300, max(-300, newValue.rounded())), forKey: "offsetMs") }
    }

    var musicVolume: Double {
        get { double("musicVolume", 0.8) }
        set { d.set(min(1, max(0, newValue)), forKey: "musicVolume") }
    }

    var sfxVolume: Double {
        get { double("sfxVolume", 0.8) }
        set { d.set(min(1, max(0, newValue)), forKey: "sfxVolume") }
    }

    var showMinimap: Bool {
        get { bool("showMinimap", true) }
        set { d.set(newValue, forKey: "showMinimap") }
    }

    /// 자동 채보에 연타·풍선을 넣을지
    var autoSpans: Bool {
        get { bool("autoSpans", true) }
        set { d.set(newValue, forKey: "autoSpans") }
    }

    var autoplay: Bool {
        get { bool("autoplay", false) }
        set { d.set(newValue, forKey: "autoplay") }
    }
}
