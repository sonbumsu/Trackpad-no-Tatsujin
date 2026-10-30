import SpriteKit

final class TitleScene: BaseScene {
    private let map = TrackpadMapNode(size: CGSize(width: 300, height: 190))

    override func didMove(to view: SKView) {
        let drum = SKSpriteNode(texture: Textures.bigDon, size: CGSize(width: 150, height: 150))
        drum.position = CGPoint(x: 640, y: 545)
        addChild(drum)
        drum.run(.repeatForever(.sequence([.scale(to: 1.06, duration: 0.4), .scale(to: 1, duration: 0.4)])))

        let title = makeLabel("트릭패드의 달인", size: 84)
        title.position = CGPoint(x: 640, y: 410)
        addChild(title)

        let start = makeLabel("트랙패드를 두드려 시작", size: 28, color: Palette.gold)
        start.position = CGPoint(x: 640, y: 340)
        addChild(start)
        start.run(.repeatForever(.sequence([.fadeAlpha(to: 0.3, duration: 0.7), .fadeAlpha(to: 1, duration: 0.7)])))

        map.position = CGPoint(x: 640 - map.size.width / 2, y: 110)
        addChild(map)

        let hints = [
            "\(Settings.shared.layout.displayName)   ·   키보드: F J = 동, D K = 캇",
            "세 손가락 제스처는 시스템 설정 › 트랙패드에서 끄면 더 편해요   ·   ⌘L 커서 고정 해제   ·   ⌘Q 종료",
        ]
        for (i, h) in hints.enumerated() {
            let l = makeLabel(h, size: 16, color: Palette.dim, bold: false)
            l.position = CGPoint(x: 640, y: 70 - CGFloat(i) * 26)
            addChild(l)
        }
    }

    override func drumHit(_ hit: DrumHit) {
        map.flash(hit)
        run(.wait(forDuration: 0.15)) { [weak self] in self?.goNext() }
    }

    override func touchesUpdated(_ points: [CGPoint]) { map.show(touches: points) }

    override func command(_ command: Command) {
        if command == .confirm { goNext() }
    }

    private var leaving = false
    private func goNext() {
        guard !leaving else { return }
        leaving = true
        app.present(SongSelectScene(app: app))
    }
}
