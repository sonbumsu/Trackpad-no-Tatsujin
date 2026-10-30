import AppKit
import SpriteKit

final class ResultScene: BaseScene {
    private let result: GameResult

    init(app: AppContext, result: GameResult) {
        self.result = result
        super.init(app: app)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        let r = result
        let title = makeLabel(r.entry.info.title, size: 34)
        title.position = CGPoint(x: 640, y: 650)
        addChild(title)
        let course = makeLabel("\(r.course.displayName) ★\(r.entry.info.charts[r.course]?.level ?? 0)"
                               + (r.autoplay ? "  ·  자동 연주 (기록 안 함)" : ""),
                               size: 20, color: Palette.gold)
        course.position = CGPoint(x: 640, y: 608)
        addChild(course)

        let crownColor: NSColor = {
            switch r.crown {
            case .failed: return Palette.ka
            case .cleared: return .white
            case .fullCombo: return Palette.gold
            case .allGood: return Palette.roll
            }
        }()
        let crown = makeLabel(r.crown.displayName, size: 64, color: crownColor)
        crown.position = CGPoint(x: 640, y: 520)
        addChild(crown)
        crown.setScale(0.3)
        crown.run(.sequence([.wait(forDuration: 1.0), .scale(to: 1.1, duration: 0.15), .scale(to: 1, duration: 0.1)]))
        crown.alpha = 0
        crown.run(.sequence([.wait(forDuration: 1.0), .fadeIn(withDuration: 0.1)]))

        let score = makeLabel("0", size: 72)
        score.position = CGPoint(x: 640, y: 420)
        addChild(score)
        let final = r.score
        score.run(.customAction(withDuration: 0.9) { node, t in
            (node as? SKLabelNode)?.text = "\(Int(Double(final) * Double(t / 0.9)))"
        })
        if r.isBest {
            let best = makeLabel("최고 기록!", size: 24, color: Palette.gold)
            best.position = CGPoint(x: 640, y: 365)
            best.alpha = 0
            addChild(best)
            best.run(.sequence([.wait(forDuration: 1.0), .fadeIn(withDuration: 0.2)]))
        }

        let stats: [(String, String, NSColor)] = [
            ("良", "\(r.good)", Palette.gold), ("可", "\(r.ok)", .white), ("不可", "\(r.bad)", Palette.ka),
            ("최대 콤보", "\(r.maxCombo)", .white), ("연타", "\(r.rolls)", Palette.roll),
            ("혼 게이지", "\(Int(r.gauge))%", r.gauge >= r.course.clearThreshold ? Palette.gold : Palette.don),
        ]
        for (i, s) in stats.enumerated() {
            let col = CGFloat(i % 3), row = CGFloat(i / 3)
            let p = CGPoint(x: 400 + col * 240, y: 280 - row * 70)
            let name = makeLabel(s.0, size: 20, color: s.2)
            name.position = CGPoint(x: p.x, y: p.y + 16)
            addChild(name)
            let value = makeLabel(s.1, size: 30)
            value.position = CGPoint(x: p.x, y: p.y - 16)
            addChild(value)
        }

        let hint = makeLabel("동 / Enter  곡 선택   ·   R  다시 하기", size: 18, color: Palette.dim, bold: false)
        hint.position = CGPoint(x: 640, y: 50)
        addChild(hint)
    }

    private let shownAt = Clock.now()

    override func command(_ command: Command) {
        // 마지막 노트를 친 손이 바로 넘기지 않도록 잠깐 기다린다
        guard Clock.now() - shownAt > 1.0 else { return }
        switch command {
        case .confirm, .back: app.present(SongSelectScene(app: app))
        case .retry: app.present(GameScene(app: app, entry: result.entry, course: result.course))
        default: break
        }
    }
}
