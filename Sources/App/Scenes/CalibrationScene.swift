import AppKit
import SpriteKit

/// 일정한 박자 소리에 맞춰 두드리게 하고, 평균적으로 얼마나 늦게/일찍 치는지 잰다
final class CalibrationScene: BaseScene {
    private let interval = 0.5
    private let leadIn = 2.0
    private let beats = 40
    private let warmupBeats = 4
    private let needed = 16

    private var diffs: [Double] = []
    private var measured: Double?
    private let pulse = SKShapeNode(circleOfRadius: 70)
    private let status = makeLabel("", size: 26)
    private let detail = makeLabel("", size: 18, color: Palette.dim, bold: false)
    private var lastBeat = -1

    override func didMove(to view: SKView) {
        let header = makeLabel("타이밍 보정", size: 34)
        header.position = CGPoint(x: 640, y: 660)
        addChild(header)
        let guide = makeLabel("화면 말고 소리에 집중해서, '틱' 소리에 맞춰 트랙패드(또는 F/J)를 두드리세요",
                              size: 20, color: Palette.dim)
        guide.position = CGPoint(x: 640, y: 610)
        addChild(guide)

        pulse.fillColor = Palette.don.withAlphaComponent(0.3)
        pulse.strokeColor = .white
        pulse.lineWidth = 3
        pulse.position = CGPoint(x: 640, y: 400)
        addChild(pulse)
        status.position = CGPoint(x: 640, y: 250)
        addChild(status)
        detail.position = CGPoint(x: 640, y: 205)
        addChild(detail)
        let hint = makeLabel("Esc 취소 · R 다시 측정", size: 16, color: Palette.dim, bold: false)
        hint.position = CGPoint(x: 640, y: 40)
        addChild(hint)
        begin()
    }

    private func begin() {
        diffs = []
        measured = nil
        lastBeat = -1
        var synth = Synth(duration: leadIn + Double(beats) * interval + 0.5)
        for k in 0..<beats {
            synth.add(at: leadIn + Double(k) * interval, duration: 0.06) { t in
                sin(2 * .pi * (k < self.warmupBeats ? 1_000 : 1_500) * t) * exp(-t * 60) * 0.7
            }
        }
        app.audio.load(samples: synth.samples)
        app.audio.play(from: 0)
        status.text = "준비…"
        detail.text = "처음 \(warmupBeats)번은 낮은 소리로 박자만 들려줘요"
    }

    override func update(_ currentTime: TimeInterval) {
        guard measured == nil else { return }
        let t = app.audio.songTime
        let beat = Int(floor((t - leadIn) / interval + 0.0001))
        if beat >= 0, beat < beats, beat != lastBeat {
            lastBeat = beat
            pulse.removeAllActions()
            pulse.setScale(1.25)
            pulse.run(.scale(to: 1, duration: 0.15))
        }
        if t > leadIn + Double(beats) * interval + 0.3 { conclude() }
    }

    override func drumHit(_ hit: DrumHit) {
        if measured != nil {
            if hit.type == .don { command(.confirm) }
            return
        }
        let t = app.audio.songTime(atUptime: hit.timestamp)
        let k = ((t - leadIn) / interval).rounded()
        guard k >= Double(warmupBeats), k < Double(beats) else { return }
        let diff = t - (leadIn + k * interval)
        guard abs(diff) < 0.2 else { return }
        diffs.append(diff)
        status.text = "\(diffs.count) / \(needed)"
        let avg = diffs.reduce(0, +) / Double(diffs.count) * 1000
        detail.text = String(format: "지금까지 평균 %+.0fms", avg)
        if diffs.count >= needed { conclude() }
    }

    private func conclude() {
        guard measured == nil else { return }
        app.audio.stop()
        guard diffs.count >= 6 else {
            measured = .nan
            status.text = "입력이 너무 적어요"
            detail.text = "R을 눌러 다시 해 주세요"
            return
        }
        let sorted = diffs.sorted()
        let median = sorted[sorted.count / 2]
        measured = median
        status.text = String(format: "측정된 오프셋: %+.0fms", median * 1000)
        detail.text = String(format: "지금 설정 %+.0fms  ·  동 / Enter 적용 · Esc 취소", app.settings.offsetMs)
    }

    override func command(_ command: Command) {
        switch command {
        case .confirm:
            if let m = measured, !m.isNaN {
                app.settings.offsetMs = m * 1000
                app.present(SettingsScene(app: app))
            }
        case .retry: begin()
        case .back: app.present(SettingsScene(app: app))
        default: break
        }
    }
}
