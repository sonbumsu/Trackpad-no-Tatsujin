import AppKit
import SpriteKit

struct GameResult {
    var entry: SongEntry
    var course: Course
    var score: Int
    var good: Int
    var ok: Int
    var bad: Int
    var maxCombo: Int
    var rolls: Int
    var gauge: Double
    var crown: Crown
    var isBest: Bool
    var autoplay: Bool
}

final class GameScene: BaseScene {
    private let entry: SongEntry
    private let course: Course
    private let chart: Chart
    private let session: GameSession
    private let autoplay: Bool
    private let offset: Double
    private let pxPerBeat: Double

    // 배치
    private let judgeX: CGFloat = 300
    private let laneY: CGFloat = 430
    private let laneHeight: CGFloat = 150
    private let gaugeFrame = CGRect(x: 420, y: 588, width: 820, height: 22)

    // 노드
    private let lane = SKSpriteNode()
    private var noteNodes: [SKSpriteNode] = []
    private var spanNodes: [SKNode] = []
    private var barNodes: [SKSpriteNode] = []
    private let scoreLabel = makeLabel("0000000", size: 40, align: .right)
    private let comboLabel = makeLabel("", size: 34)
    private let countsLabel = makeLabel("", size: 16, color: Palette.dim, bold: false, align: .left)
    private let rollLabel = makeLabel("", size: 26, color: Palette.roll)
    private let gaugeFill = SKSpriteNode(color: Palette.don, size: .zero)
    private let drumFace = SKShapeNode(circleOfRadius: 40)
    private let drumRim = SKShapeNode(circleOfRadius: 58)
    private let judgeFlash = SKShapeNode(circleOfRadius: 40)
    private let map = TrackpadMapNode(size: CGSize(width: 200, height: 125))
    private let pauseOverlay = SKNode()
    private let errorLabel = makeLabel("", size: 22, color: Palette.don)

    // 진행 상태
    private var started = false
    private var finished = false
    private var pausedAt: Double?
    private var inGogo = false
    private var autoNext = 0
    private var autoRollNext = -Double.infinity

    init(app: AppContext, entry: SongEntry, course: Course) {
        self.entry = entry
        self.course = course
        chart = entry.info.charts[course]!
        session = GameSession(chart: chart, bigHitWindow: app.settings.bigHitWindowMs / 1000,
                              judgeScale: app.settings.judgeScale)
        autoplay = app.settings.autoplay
        offset = app.settings.offsetMs / 1000
        pxPerBeat = 245 * app.settings.scrollSpeed
        super.init(app: app)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 화면 구성

    override func didMove(to view: SKView) {
        buildHUD()
        buildLane()
        buildNotes()
        buildPauseOverlay()

        if let error = app.loadAudio(for: entry) {
            errorLabel.text = error
            errorLabel.numberOfLines = 0
            errorLabel.position = CGPoint(x: 640, y: 220)
            errorLabel.zPosition = 30
            addChild(errorLabel)
            pausedAt = 0
            showPause(true)
            return
        }
        start(from: -2.0)
    }

    private func buildHUD() {
        let title = makeLabel(entry.info.title, size: 28, align: .left)
        title.position = CGPoint(x: 40, y: 676)
        addChild(title)
        var sub = "\(course.displayName) ★\(chart.level)"
        if autoplay { sub += "  ·  자동 연주" }
        let courseLabel = makeLabel(sub, size: 18, color: Palette.gold, align: .left)
        courseLabel.position = CGPoint(x: 40, y: 640)
        addChild(courseLabel)

        scoreLabel.position = CGPoint(x: 1240, y: 668)
        addChild(scoreLabel)

        let gaugeBg = SKShapeNode(rect: gaugeFrame, cornerRadius: 6)
        gaugeBg.fillColor = NSColor(white: 0, alpha: 0.5)
        gaugeBg.strokeColor = NSColor(white: 1, alpha: 0.4)
        addChild(gaugeBg)
        gaugeFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        gaugeFill.position = CGPoint(x: gaugeFrame.minX + 2, y: gaugeFrame.midY)
        gaugeFill.zPosition = 1
        addChild(gaugeFill)
        let line = SKSpriteNode(color: .white, size: CGSize(width: 3, height: gaugeFrame.height + 10))
        line.position = CGPoint(x: gaugeFrame.minX + gaugeFrame.width * course.clearThreshold / 100, y: gaugeFrame.midY)
        line.zPosition = 2
        addChild(line)
        let soul = makeLabel("혼", size: 20, color: Palette.gold)
        soul.position = CGPoint(x: gaugeFrame.minX - 24, y: gaugeFrame.midY)
        addChild(soul)

        countsLabel.position = CGPoint(x: 40, y: 290)
        addChild(countsLabel)

        if app.settings.showMinimap {
            map.position = CGPoint(x: 1240 - map.size.width, y: 110)
            addChild(map)
            let l = makeLabel("트랙패드", size: 14, color: Palette.dim, bold: false)
            l.position = CGPoint(x: map.position.x + map.size.width / 2, y: 90)
            addChild(l)
        }
        let hint = makeLabel("Esc 일시정지 · R 처음부터", size: 15, color: Palette.dim, bold: false, align: .left)
        hint.position = CGPoint(x: 40, y: 40)
        addChild(hint)
        updateHUD()
    }

    private func buildLane() {
        lane.color = Palette.lane
        lane.size = CGSize(width: 1280 - 150, height: laneHeight)
        lane.anchorPoint = CGPoint(x: 0, y: 0.5)
        lane.position = CGPoint(x: 150, y: laneY)
        addChild(lane)

        let panel = SKSpriteNode(color: Palette.panel, size: CGSize(width: 150, height: laneHeight))
        panel.anchorPoint = CGPoint(x: 0, y: 0.5)
        panel.position = CGPoint(x: 0, y: laneY)
        panel.zPosition = 40
        addChild(panel)

        drumRim.fillColor = Palette.ka.withAlphaComponent(0.25)
        drumRim.strokeColor = .white
        drumRim.lineWidth = 3
        drumRim.position = CGPoint(x: 75, y: laneY)
        drumRim.zPosition = 41
        addChild(drumRim)
        drumFace.fillColor = Palette.don.withAlphaComponent(0.25)
        drumFace.strokeColor = NSColor(white: 1, alpha: 0.6)
        drumFace.position = drumRim.position
        drumFace.zPosition = 42
        addChild(drumFace)
        comboLabel.position = drumRim.position
        comboLabel.zPosition = 43
        addChild(comboLabel)

        let outer = SKShapeNode(circleOfRadius: 52)
        outer.strokeColor = NSColor(white: 1, alpha: 0.55)
        outer.lineWidth = 3
        outer.position = CGPoint(x: judgeX, y: laneY)
        outer.zPosition = 2
        addChild(outer)
        let inner = SKShapeNode(circleOfRadius: 34)
        inner.strokeColor = NSColor(white: 1, alpha: 0.35)
        inner.lineWidth = 2
        inner.position = outer.position
        inner.zPosition = 2
        addChild(inner)
        judgeFlash.strokeColor = .clear
        judgeFlash.position = outer.position
        judgeFlash.zPosition = 3
        judgeFlash.alpha = 0
        addChild(judgeFlash)

        rollLabel.position = CGPoint(x: judgeX, y: laneY + 125)
        rollLabel.zPosition = 30
        addChild(rollLabel)
    }

    private func buildNotes() {
        for _ in chart.barLines {
            let n = SKSpriteNode(color: NSColor(white: 1, alpha: 0.35), size: CGSize(width: 2, height: laneHeight))
            n.position = CGPoint(x: -100, y: laneY)
            n.zPosition = 1
            n.isHidden = true
            addChild(n)
            barNodes.append(n)
        }
        for (i, span) in chart.spans.enumerated() {
            let node = SKNode()
            node.zPosition = 5 - CGFloat(i) * 0.001
            node.isHidden = true
            switch span.kind {
            case .roll, .bigRoll:
                let big = span.kind == .bigRoll
                let d: CGFloat = big ? 102 : 68
                let length = CGFloat(span.endTime - span.time) * CGFloat(pps(span.bpm, span.scroll))
                let body = SKSpriteNode(color: Palette.roll, size: CGSize(width: length, height: d * 0.74))
                body.anchorPoint = CGPoint(x: 0, y: 0.5)
                node.addChild(body)
                let tail = SKSpriteNode(texture: big ? Textures.bigRoll : Textures.roll, size: CGSize(width: d, height: d))
                tail.position.x = length
                tail.zPosition = -0.0001
                node.addChild(tail)
                let head = SKSpriteNode(texture: big ? Textures.bigRoll : Textures.roll, size: CGSize(width: d, height: d))
                node.addChild(head)
            case let .balloon(required):
                let head = SKSpriteNode(texture: Textures.balloon, size: CGSize(width: 84, height: 84))
                node.addChild(head)
                let count = makeLabel("\(required)", size: 26)
                count.name = "count"
                count.zPosition = 1
                node.addChild(count)
            }
            addChild(node)
            spanNodes.append(node)
        }
        for (i, note) in chart.hitNotes.enumerated() {
            let tex: SKTexture
            switch (note.type, note.isBig) {
            case (.don, false): tex = Textures.don
            case (.ka, false): tex = Textures.ka
            case (.don, true): tex = Textures.bigDon
            case (.ka, true): tex = Textures.bigKa
            }
            let d: CGFloat = note.isBig ? 102 : 68
            let n = SKSpriteNode(texture: tex, size: CGSize(width: d, height: d))
            n.zPosition = 10 - CGFloat(i) * 0.0001
            n.isHidden = true
            addChild(n)
            noteNodes.append(n)
        }
    }

    private func buildPauseOverlay() {
        pauseOverlay.zPosition = 100
        pauseOverlay.isHidden = true
        let dim = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 1280, height: 720))
        dim.fillColor = NSColor(white: 0, alpha: 0.65)
        dim.strokeColor = .clear
        pauseOverlay.addChild(dim)
        let t = makeLabel("일시정지", size: 48)
        t.position = CGPoint(x: 640, y: 450)
        pauseOverlay.addChild(t)
        let lines = ["동 / Enter  계속하기", "R  처음부터", "Esc  곡 선택으로"]
        for (i, s) in lines.enumerated() {
            let l = makeLabel(s, size: 24, color: Palette.dim)
            l.position = CGPoint(x: 640, y: 370 - CGFloat(i) * 44)
            pauseOverlay.addChild(l)
        }
        addChild(pauseOverlay)
    }

    // MARK: 진행

    private func pps(_ bpm: Double, _ scroll: Double) -> Double { bpm / 60 * scroll * pxPerBeat }

    private func x(at time: Double, bpm: Double, scroll: Double, now: Double) -> CGFloat {
        judgeX + CGFloat((time - now) * pps(bpm, scroll))
    }

    private func start(from songTime: Double) {
        app.audio.play(from: songTime)
        started = true
    }

    /// 판정 기준 곡 시각 (오프셋 반영)
    private var now: Double { app.audio.songTime - offset }

    override func update(_ currentTime: TimeInterval) {
        guard started, pausedAt == nil, !finished else { return }
        let t = now
        if autoplay { runAutoplay(t) }
        for e in session.update(now: t) { handle(e) }
        render(t)
        if t > chart.endTime + 2.0 { finish() }
    }

    private func render(_ now: Double) {
        let visible: ClosedRange<CGFloat> = 100...1400
        for (i, note) in chart.hitNotes.enumerated() {
            let node = noteNodes[i]
            if let r = session.results[i], r != .bad {
                node.isHidden = true
                continue
            }
            let px = x(at: note.time, bpm: note.bpm, scroll: note.scroll, now: now)
            node.isHidden = !visible.contains(px)
            if !node.isHidden { node.position = CGPoint(x: px, y: laneY) }
        }
        for (i, bar) in chart.barLines.enumerated() {
            let px = x(at: bar.time, bpm: bar.bpm, scroll: bar.scroll, now: now)
            barNodes[i].isHidden = !visible.contains(px)
            barNodes[i].position.x = px
        }
        var activeRoll: Int?
        for (i, span) in chart.spans.enumerated() {
            let node = spanNodes[i]
            let head = x(at: span.time, bpm: span.bpm, scroll: span.scroll, now: now)
            if case .balloon = span.kind {
                if session.balloonPopped[i] || now > span.endTime {
                    node.isHidden = true
                } else {
                    node.position = CGPoint(x: max(head, judgeX), y: laneY)
                    node.isHidden = head > 1400
                }
            } else {
                let tail = head + CGFloat((span.endTime - span.time) * pps(span.bpm, span.scroll))
                node.position = CGPoint(x: head, y: laneY)
                node.isHidden = head > 1400 || tail < 100
                if now >= span.time, now <= span.endTime { activeRoll = i }
            }
        }
        if activeRoll == nil, rollLabel.action(forKey: "fade") == nil, rollLabel.alpha > 0 {
            rollLabel.run(.sequence([.wait(forDuration: 0.6), .fadeOut(withDuration: 0.2)]), withKey: "fade")
        }

        let gogo = chart.isGogo(at: now)
        if gogo != inGogo {
            inGogo = gogo
            lane.run(.colorize(with: gogo ? Palette.laneGogo : Palette.lane, colorBlendFactor: 1, duration: 0.15))
        }
    }

    private func runAutoplay(_ now: Double) {
        while autoNext < chart.hitNotes.count, chart.hitNotes[autoNext].time <= now {
            let note = chart.hitNotes[autoNext]
            if session.results[autoNext] == nil {
                autoHit(note.type, at: note.time)
                if note.isBig { autoHit(note.type, at: note.time + 0.01) }
            }
            autoNext += 1
        }
        if session.activeSpan(at: now) != nil, now - autoRollNext >= 1.0 / 16 {
            autoRollNext = now
            autoHit(.don, at: now)
        }
    }

    private func autoHit(_ type: DrumType, at t: Double) {
        app.audio.play(type == .don ? .don : .ka)
        flashDrum(type)
        for e in session.hit(type, at: t) { handle(e) }
    }

    private func finish() {
        finished = true
        app.audio.stop()
        let crown = session.crown
        let isBest = autoplay ? false : app.records.submit(song: entry.id, course: course, score: session.score,
                                                           maxCombo: session.maxCombo, crown: crown)
        let result = GameResult(entry: entry, course: course, score: session.score, good: session.goodCount,
                                ok: session.okCount, bad: session.badCount, maxCombo: session.maxCombo,
                                rolls: session.rollCount, gauge: session.gauge, crown: crown,
                                isBest: isBest, autoplay: autoplay)
        app.present(ResultScene(app: app, result: result))
    }

    // MARK: 입력

    override func drumHit(_ hit: DrumHit) {
        map.flash(hit)
        if pausedAt != nil {
            if hit.type == .don { command(.confirm) }
            return
        }
        flashDrum(hit.type)
        guard started, !finished, !autoplay else { return }
        let t = app.audio.songTime(atUptime: hit.timestamp) - offset
        for e in session.hit(hit.type, at: t) { handle(e) }
    }

    override func touchesUpdated(_ points: [CGPoint]) { map.show(touches: points) }

    override func command(_ command: Command) {
        guard !finished else { return }
        if let pausedTime = pausedAt {
            switch command {
            case .confirm:
                guard errorLabel.parent == nil else { return }
                showPause(false)
                pausedAt = nil
                start(from: max(-2.0, pausedTime - 2.0))
            case .retry: restart()
            case .back: app.present(SongSelectScene(app: app))
            default: break
            }
            return
        }
        switch command {
        case .back:
            pausedAt = app.audio.songTime
            app.audio.stop()
            showPause(true)
        case .retry: restart()
        default: break
        }
    }

    private func restart() {
        app.present(GameScene(app: app, entry: entry, course: course))
    }

    private func showPause(_ on: Bool) {
        pauseOverlay.isHidden = !on
    }

    // MARK: 연출

    private func handle(_ event: GameEvent) {
        switch event {
        case let .judged(i, j):
            showJudgement(j)
            if j != .bad {
                flyAway(i)
                burst(chart.hitNotes[i].isBig ? 80 : 60, color: j == .good ? Palette.gold : .white)
            }
            if session.combo > 0, session.combo % 50 == 0 { celebrateCombo() }
        case .missed:
            showJudgement(.bad)
        case .bigBonus:
            burst(100, color: Palette.gold)
        case let .rollHit(_, count):
            showRoll("\(count) 연타")
        case let .balloonHit(span, remaining):
            if let label = spanNodes[span].childNode(withName: "count") as? SKLabelNode {
                label.text = "\(remaining)"
            }
            spanNodes[span].run(.sequence([.scale(to: 1.15, duration: 0.04), .scale(to: 1, duration: 0.06)]))
            showRoll("\(session.balloonHits[span]) 타")
        case .balloonPopped:
            app.audio.play(.pop)
            burst(110, color: Palette.balloon)
            showRoll("펑!")
        }
        updateHUD()
    }

    private func updateHUD() {
        scoreLabel.text = String(format: "%07d", session.score)
        comboLabel.text = session.combo >= 10 ? "\(session.combo)" : ""
        countsLabel.text = "良 \(session.goodCount)   可 \(session.okCount)   不可 \(session.badCount)   연타 \(session.rollCount)"
        let w = (gaugeFrame.width - 4) * CGFloat(session.gauge / 100)
        gaugeFill.size = CGSize(width: w, height: gaugeFrame.height - 4)
        gaugeFill.color = session.isCleared ? Palette.gold : Palette.don
    }

    private func flashDrum(_ type: DrumType) {
        let node = type == .don ? drumFace : drumRim
        let base = type == .don ? Palette.don : Palette.ka
        node.removeAction(forKey: "flash")
        node.fillColor = base
        node.run(.sequence([.wait(forDuration: 0.08), .run { node.fillColor = base.withAlphaComponent(0.25) }]),
                 withKey: "flash")
        judgeFlash.fillColor = base.withAlphaComponent(0.6)
        judgeFlash.removeAllActions()
        judgeFlash.alpha = 1
        judgeFlash.run(.fadeOut(withDuration: 0.12))
    }

    private func showJudgement(_ j: Judgement) {
        let (text, color): (String, NSColor) = {
            switch j {
            case .good: return ("良", Palette.gold)
            case .ok: return ("可", .white)
            case .bad: return ("不可", Palette.ka)
            }
        }()
        let l = makeLabel(text, size: 34, color: color)
        l.position = CGPoint(x: judgeX, y: laneY + 85)
        l.zPosition = 30
        addChild(l)
        l.run(.sequence([.group([.moveBy(x: 0, y: 18, duration: 0.3), .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.15)])]),
                         .removeFromParent()]))
    }

    private func flyAway(_ i: Int) {
        let src = noteNodes[i]
        let n = SKSpriteNode(texture: src.texture, size: src.size)
        n.position = CGPoint(x: judgeX, y: laneY)
        n.zPosition = 50
        addChild(n)
        let target = CGPoint(x: gaugeFrame.minX + gaugeFrame.width * CGFloat(session.gauge / 100), y: gaugeFrame.midY)
        n.run(.sequence([.group([.move(to: target, duration: 0.35), .scale(to: 0.5, duration: 0.35),
                                 .sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.1)])]),
                         .removeFromParent()]))
    }

    private func burst(_ radius: CGFloat, color: NSColor) {
        let ring = SKShapeNode(circleOfRadius: radius / 2)
        ring.strokeColor = color
        ring.lineWidth = 6
        ring.position = CGPoint(x: judgeX, y: laneY)
        ring.zPosition = 25
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1.8, duration: 0.2), .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
    }

    private func showRoll(_ text: String) {
        rollLabel.removeAction(forKey: "fade")
        rollLabel.alpha = 1
        rollLabel.text = text
        rollLabel.setScale(1.15)
        rollLabel.run(.scale(to: 1, duration: 0.08))
    }

    private func celebrateCombo() {
        let l = makeLabel("\(session.combo) 콤보!", size: 40, color: Palette.gold)
        l.position = CGPoint(x: 740, y: laneY)
        l.zPosition = 35
        l.setScale(0.6)
        addChild(l)
        l.run(.sequence([.scale(to: 1.1, duration: 0.15), .wait(forDuration: 0.5), .fadeOut(withDuration: 0.25), .removeFromParent()]))
    }
}
