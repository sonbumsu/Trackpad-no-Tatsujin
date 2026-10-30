import AppKit
import SpriteKit

enum Palette {
    static let background = NSColor(red: 0.11, green: 0.10, blue: 0.17, alpha: 1)
    static let panel = NSColor(red: 0.18, green: 0.16, blue: 0.26, alpha: 1)
    static let lane = NSColor(red: 0.22, green: 0.20, blue: 0.28, alpha: 1)
    static let laneGogo = NSColor(red: 0.45, green: 0.22, blue: 0.20, alpha: 1)
    static let don = NSColor(red: 0.96, green: 0.30, blue: 0.20, alpha: 1)
    static let ka = NSColor(red: 0.27, green: 0.72, blue: 0.82, alpha: 1)
    static let roll = NSColor(red: 1.00, green: 0.78, blue: 0.10, alpha: 1)
    static let balloon = NSColor(red: 1.00, green: 0.55, blue: 0.15, alpha: 1)
    static let gold = NSColor(red: 1.00, green: 0.84, blue: 0.30, alpha: 1)
    static let text = NSColor.white
    static let dim = NSColor(white: 1, alpha: 0.55)
}

func makeLabel(_ text: String, size: CGFloat, color: NSColor = Palette.text, bold: Bool = true,
               align: SKLabelHorizontalAlignmentMode = .center) -> SKLabelNode {
    let l = SKLabelNode(text: text)
    l.fontName = bold ? "AppleSDGothicNeo-Bold" : "AppleSDGothicNeo-Regular"
    l.fontSize = size
    l.fontColor = color
    l.horizontalAlignmentMode = align
    l.verticalAlignmentMode = .center
    return l
}

enum Textures {
    /// 태고 노트 모양: 검은 테두리 + 흰 링 + 색 원
    static func note(_ diameter: CGFloat, _ fill: NSColor) -> SKTexture {
        let s = diameter * 2
        let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { r in
            NSColor(white: 0.08, alpha: 1).setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: s * 0.06, dy: s * 0.06)).fill()
            fill.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: s * 0.13, dy: s * 0.13)).fill()
            NSColor(white: 1, alpha: 0.28).setFill()
            NSBezierPath(ovalIn: NSRect(x: s * 0.30, y: s * 0.58, width: s * 0.30, height: s * 0.16)).fill()
            return true
        }
        return SKTexture(image: image)
    }

    static let don = note(68, Palette.don)
    static let ka = note(68, Palette.ka)
    static let bigDon = note(102, Palette.don)
    static let bigKa = note(102, Palette.ka)
    static let roll = note(68, Palette.roll)
    static let bigRoll = note(102, Palette.roll)
    static let balloon = note(84, Palette.balloon)
}

/// 트랙패드 영역과 지금 닿은 손가락을 보여주는 작은 지도
final class TrackpadMapNode: SKNode {
    let size: CGSize
    private let zones = SKNode()
    private let dots = SKNode()

    init(size: CGSize) {
        self.size = size
        super.init()
        addChild(zones)
        addChild(dots)
        dots.zPosition = 2
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        zones.removeAllChildren()
        let s = Settings.shared
        let w = size.width, h = size.height
        func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ c: NSColor) {
            let n = SKShapeNode(rect: CGRect(x: x, y: y, width: rw, height: rh))
            n.fillColor = c.withAlphaComponent(0.45)
            n.strokeColor = .clear
            zones.addChild(n)
        }
        let rim = CGFloat(s.rimSize)
        switch s.layout {
        case .border:
            rect(0, 0, w, h, Palette.ka)
            rect(w * rim, h * rim, w * (1 - 2 * rim), h * (1 - 2 * rim), Palette.don)
        case .columns:
            rect(0, 0, w, h, Palette.ka)
            rect(w * rim, 0, w * (1 - 2 * rim), h, Palette.don)
        case .split:
            rect(0, 0, w / 2, h, Palette.ka)
            rect(w / 2, 0, w / 2, h, Palette.don)
        case .fingers:
            rect(0, 0, w, h, Palette.don)
            let l = makeLabel("1손가락 동 · 2손가락 캇", size: 13)
            l.position = CGPoint(x: w / 2, y: h / 2)
            zones.addChild(l)
        }
        let frame = SKShapeNode(rect: CGRect(origin: .zero, size: size), cornerRadius: 10)
        frame.strokeColor = NSColor(white: 1, alpha: 0.7)
        frame.lineWidth = 2
        frame.fillColor = .clear
        zones.addChild(frame)
    }

    func show(touches: [CGPoint]) {
        dots.removeAllChildren()
        for p in touches {
            let d = SKShapeNode(circleOfRadius: 7)
            d.fillColor = .white
            d.strokeColor = .clear
            d.position = CGPoint(x: p.x * size.width, y: p.y * size.height)
            dots.addChild(d)
        }
    }

    func flash(_ hit: DrumHit) {
        guard let p = hit.position else { return }
        let c = SKShapeNode(circleOfRadius: 14)
        c.fillColor = hit.type == .don ? Palette.don : Palette.ka
        c.strokeColor = .white
        c.position = CGPoint(x: p.x * size.width, y: p.y * size.height)
        c.zPosition = 1
        addChild(c)
        c.run(.sequence([.group([.scale(to: 1.8, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
    }
}

class BaseScene: SKScene, InputReceiver {
    unowned let app: AppContext

    init(app: AppContext) {
        self.app = app
        super.init(size: CGSize(width: 1280, height: 720))
        scaleMode = .aspectFit
        anchorPoint = .zero
        backgroundColor = Palette.background
    }

    required init?(coder: NSCoder) { fatalError() }

    func drumHit(_ hit: DrumHit) {
        // 메뉴에서는 동 = 결정, 캇 = 좌우 이동
        switch (hit.type, hit.side) {
        case (.don, _): command(.confirm)
        case (.ka, .left): command(.left)
        case (.ka, .right): command(.right)
        }
    }

    func command(_ command: Command) {}
    func touchesUpdated(_ points: [CGPoint]) {}
}
