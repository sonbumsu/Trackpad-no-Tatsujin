import AppKit
import SpriteKit

/// 설정은 키보드로 조작한다. 트랙패드는 오른쪽 미리보기에서 입력 확인용으로 쓴다.
final class SettingsScene: BaseScene {
    private struct Row {
        var name: String
        var value: (Settings) -> String
        var change: (Settings, Int) -> Void
    }

    private let rows: [Row] = [
        Row(name: "입력 방식", value: { $0.layout.displayName }) { s, d in
            let all = InputLayout.allCases
            s.layout = all[(s.layout.rawValue + d + all.count) % all.count]
        },
        Row(name: "판정 폭", value: { s in
            let w = JudgeWindows.forCourse(.oni, scale: s.judgeScale)
            let tag = s.judgeScale == 1 ? "원작" : String(format: "%g×", s.judgeScale)
            return "\(tag)  (귀신 良 ±\(Int(w.good * 1000))ms · 可 ±\(Int(w.ok * 1000))ms)"
        }) { s, d in
            let all = Settings.judgeScales
            let i = all.firstIndex(of: s.judgeScale) ?? 2
            s.judgeScale = all[(i + (d > 0 ? 1 : -1) + all.count) % all.count]
        },
        Row(name: "테 두께", value: { "\(Int(($0.rimSize * 100).rounded()))%" }) { s, d in s.rimSize += Double(d) * 0.01 },
        Row(name: "양손 동시 인정", value: { "\(Int($0.bigHitWindowMs))ms" }) { s, d in s.bigHitWindowMs += Double(d) * 5 },
        Row(name: "스크롤 속도", value: { String(format: "%.1f×", $0.scrollSpeed) }) { s, d in s.scrollSpeed += Double(d) * 0.1 },
        Row(name: "판정 오프셋", value: { String(format: "%+dms", Int($0.offsetMs)) }) { s, d in s.offsetMs += Double(d) },
        Row(name: "음악 볼륨", value: { "\(Int(($0.musicVolume * 100).rounded()))%" }) { s, d in s.musicVolume += Double(d) * 0.05 },
        Row(name: "효과음 볼륨", value: { "\(Int(($0.sfxVolume * 100).rounded()))%" }) { s, d in s.sfxVolume += Double(d) * 0.05 },
        Row(name: "트랙패드 미니맵", value: { $0.showMinimap ? "켜짐" : "꺼짐" }) { s, _ in s.showMinimap.toggle() },
        Row(name: "자동 채보 연타·풍선", value: { $0.autoSpans ? "넣음" : "안 넣음" }) { s, _ in s.autoSpans.toggle() },
        Row(name: "자동 연주", value: { $0.autoplay ? "켜짐" : "꺼짐" }) { s, _ in s.autoplay.toggle() },
        Row(name: "타이밍 보정 하기", value: { _ in "→" }) { _, _ in },
        Row(name: "돌아가기", value: { _ in "" }) { _, _ in },
    ]

    private var index = 0
    private let list = SKNode()
    private let map = TrackpadMapNode(size: CGSize(width: 400, height: 250))
    private let lastHit = makeLabel("트랙패드를 두드려 보세요", size: 22, color: Palette.dim)

    override func didMove(to view: SKView) {
        let header = makeLabel("설정", size: 34)
        header.position = CGPoint(x: 640, y: 676)
        addChild(header)
        let hint = makeLabel("↑↓ 항목 · ←→ 값 바꾸기 (Shift 누르면 10배) · Enter 선택 · Esc 뒤로",
                             size: 16, color: Palette.dim, bold: false)
        hint.position = CGPoint(x: 640, y: 28)
        addChild(hint)

        addChild(list)
        map.position = CGPoint(x: 800, y: 300)
        addChild(map)
        lastHit.position = CGPoint(x: 1000, y: 255)
        addChild(lastHit)
        let note = makeLabel("입력 미리보기", size: 18, color: Palette.dim)
        note.position = CGPoint(x: 1000, y: 575)
        addChild(note)
        refresh()
    }

    private func refresh() {
        list.removeAllChildren()
        for (i, row) in rows.enumerated() {
            let y = 590 - CGFloat(i) * 44
            if i == index {
                let bg = SKShapeNode(rect: CGRect(x: 50, y: y - 20, width: 700, height: 40), cornerRadius: 10)
                bg.fillColor = Palette.don.withAlphaComponent(0.85)
                bg.strokeColor = .clear
                list.addChild(bg)
            }
            let name = makeLabel(row.name, size: 20, align: .left)
            name.position = CGPoint(x: 70, y: y)
            list.addChild(name)
            let value = makeLabel(row.value(app.settings), size: 17, color: i == index ? .white : Palette.dim,
                                  bold: false, align: .right)
            value.position = CGPoint(x: 730, y: y)
            list.addChild(value)
        }
        map.refresh()
        app.audio.applyVolumes()
    }

    override func drumHit(_ hit: DrumHit) {
        map.flash(hit)
        lastHit.text = hit.type == .don ? "동!" : "캇!"
        lastHit.fontColor = hit.type == .don ? Palette.don : Palette.ka
    }

    override func touchesUpdated(_ points: [CGPoint]) { map.show(touches: points) }

    override func command(_ command: Command) {
        let fine = NSEvent.modifierFlags.contains(.shift) ? 10 : 1
        switch command {
        case .up: index = (index + rows.count - 1) % rows.count
        case .down: index = (index + 1) % rows.count
        case .left: rows[index].change(app.settings, -fine)
        case .right: rows[index].change(app.settings, fine)
        case .confirm:
            switch rows[index].name {
            case "타이밍 보정 하기": app.present(CalibrationScene(app: app)); return
            case "돌아가기": app.present(SongSelectScene(app: app)); return
            default: rows[index].change(app.settings, 1)
            }
        case .back:
            app.present(SongSelectScene(app: app))
            return
        default: return
        }
        refresh()
    }
}
