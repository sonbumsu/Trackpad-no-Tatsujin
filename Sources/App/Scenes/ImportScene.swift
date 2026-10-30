import AppKit
import SpriteKit

/// 가져오기 진행과 결과를 보여준다
final class ImportScene: BaseScene {
    private let urls: [URL]
    private var outcomes: [SongImporter.Outcome]?
    private let status = makeLabel("음악 분석 중…", size: 34)
    private let results = SKNode()

    init(app: AppContext, urls: [URL]) {
        self.urls = urls
        super.init(app: app)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        let header = makeLabel("음악 추가", size: 34)
        header.position = CGPoint(x: 640, y: 660)
        addChild(header)

        status.position = CGPoint(x: 640, y: 520)
        addChild(status)
        status.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))

        let names = urls.prefix(6).map(\.lastPathComponent).joined(separator: "\n")
        let files = makeLabel(names + (urls.count > 6 ? "\n외 \(urls.count - 6)개" : ""), size: 18,
                              color: Palette.dim, bold: false)
        files.numberOfLines = 0
        files.position = CGPoint(x: 640, y: 400)
        addChild(files)
        results.zPosition = 1
        addChild(results)

        let urls = self.urls
        let spans = app.settings.autoSpans
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcomes = SongImporter.importItems(urls, spans: spans)
            DispatchQueue.main.async {
                files.removeFromParent()
                self?.show(outcomes)
            }
        }
    }

    private func show(_ outcomes: [SongImporter.Outcome]) {
        self.outcomes = outcomes
        status.removeAllActions()
        status.alpha = 1
        let added = outcomes.filter(\.ok).count
        status.text = added > 0 ? "\(added)곡을 추가했어요" : "추가하지 못했어요"
        for (i, o) in outcomes.prefix(8).enumerated() {
            let y = 440 - CGFloat(i) * 40
            let title = makeLabel((o.ok ? "✓  " : "✗  ") + o.title, size: 22, color: o.ok ? .white : Palette.don,
                                  align: .left)
            title.position = CGPoint(x: 200, y: y)
            results.addChild(title)
            let msg = makeLabel(o.message, size: 17, color: Palette.dim, bold: false, align: .right)
            msg.position = CGPoint(x: 1080, y: y)
            results.addChild(msg)
        }
        let hint = makeLabel("자동 채보는 곡 폴더의 song.tja 파일이라 직접 고칠 수도 있어요   ·   동 / Enter 곡 선택으로",
                             size: 17, color: Palette.dim, bold: false)
        hint.position = CGPoint(x: 640, y: 60)
        results.addChild(hint)

        app.reloadLibrary()
        if let first = outcomes.first(where: \.ok) { SongSelectScene.focus(title: first.title) }
    }

    override func command(_ command: Command) {
        guard outcomes != nil, command == .confirm || command == .back else { return }
        app.present(SongSelectScene(app: app))
    }
}
