import AppKit
import SpriteKit

final class SongSelectScene: BaseScene {
    private enum Item {
        case song(SongEntry)
        case addSongs
        case settings
        case calibration
    }

    private static var lastIndex = 0
    private static var lastCourse: Course = .oni
    private static var pendingFocus: String?

    /// 다음에 곡 선택 화면을 열 때 이 제목의 곡을 고른다
    static func focus(title: String) { pendingFocus = title }

    private var items: [Item] = []
    private var index = 0
    private var choosingCourse = false
    private var courseIndex = 0

    private let list = SKNode()
    private let detail = SKNode()
    private let coursePanel = SKNode()

    override func didMove(to view: SKView) {
        app.reloadLibrary()
        items = app.library.map { .song($0) } + [.addSongs, .settings, .calibration]
        if let title = Self.pendingFocus,
           let i = app.library.lastIndex(where: { $0.info.title == title }) {
            Self.lastIndex = i
        }
        Self.pendingFocus = nil
        index = min(Self.lastIndex, items.count - 1)

        let header = makeLabel("곡 선택", size: 34)
        header.position = CGPoint(x: 640, y: 676)
        addChild(header)

        let hint = makeLabel("캇(왼쪽/오른쪽 테) 이동 · 동 결정 · Esc 뒤로 · 음악 파일을 창에 끌어다 놓으면 추가",
                             size: 16, color: Palette.dim, bold: false)
        hint.position = CGPoint(x: 640, y: 28)
        addChild(hint)

        addChild(list)
        addChild(detail)
        coursePanel.zPosition = 20
        addChild(coursePanel)
        buildList()
        refresh(animated: false)
    }

    // MARK: 목록

    private func title(of item: Item) -> String {
        switch item {
        case let .song(e): return e.info.title
        case .addSongs: return "＋  음악 추가"
        case .settings: return "⚙  설정"
        case .calibration: return "◎  타이밍 보정"
        }
    }

    private func buildList() {
        list.removeAllChildren()
        for (i, item) in items.enumerated() {
            let row = SKNode()
            row.name = "row\(i)"
            let bg = SKShapeNode(rect: CGRect(x: -330, y: -30, width: 660, height: 60), cornerRadius: 14)
            bg.name = "bg"
            bg.strokeColor = .clear
            row.addChild(bg)
            let t = makeLabel(title(of: item), size: 26, align: .left)
            t.position = CGPoint(x: -300, y: 0)
            row.addChild(t)
            if case let .song(e) = item {
                let stars = e.info.courses.map { "\($0.displayName) \(e.info.charts[$0]!.level)" }.joined(separator: "  ")
                let s = makeLabel(stars, size: 14, color: Palette.dim, bold: false, align: .right)
                s.position = CGPoint(x: 310, y: 0)
                row.addChild(s)
            }
            list.addChild(row)
        }
    }

    private func refresh(animated: Bool) {
        for (i, _) in items.enumerated() {
            guard let row = list.childNode(withName: "row\(i)"),
                  let bg = row.childNode(withName: "bg") as? SKShapeNode else { continue }
            let selected = i == index
            let target = CGPoint(x: 640, y: 470 - CGFloat(i - index) * 74)
            if animated { row.run(.move(to: target, duration: 0.12)) } else { row.position = target }
            row.setScale(selected ? 1.08 : 1)
            row.alpha = abs(i - index) > 3 ? 0 : selected ? 1 : 0.6
            bg.fillColor = selected ? Palette.don.withAlphaComponent(0.85) : Palette.panel
        }
        showDetail()
        schedulePreview()
    }

    private func showDetail() {
        detail.removeAllChildren()
        let y: CGFloat = 130
        switch items[index] {
        case let .song(e):
            var lines = [e.info.subtitle, "BPM \(Int(e.info.bpm))" + (e.isBuiltIn ? "  ·  기본 수록곡" : "")]
            let best = e.info.courses.compactMap { c -> String? in
                guard let r = app.records.record(song: e.id, course: c) else { return nil }
                return "\(c.displayName) \(r.bestScore)점 (\(r.crown.displayName))"
            }
            if !best.isEmpty { lines.append("최고 기록  " + best.joined(separator: "  ·  ")) }
            for (i, line) in lines.filter({ !$0.isEmpty }).enumerated() {
                let l = makeLabel(line, size: 18, color: i == 0 ? Palette.text : Palette.dim, bold: i == 0)
                l.position = CGPoint(x: 640, y: y - CGFloat(i) * 28)
                detail.addChild(l)
            }
        case .addSongs:
            let lines = ["음악 파일(mp3, m4a, wav…)을 고르면 박자를 분석해서 채보를 자동으로 만들어요",
                         "Finder에서 창으로 끌어다 놓아도 돼요 · TJA 채보나 곡 폴더도 넣을 수 있어요"]
            for (i, line) in lines.enumerated() {
                let l = makeLabel(line, size: 18, color: i == 0 ? Palette.text : Palette.dim, bold: i == 0)
                l.position = CGPoint(x: 640, y: y - CGFloat(i) * 28)
                detail.addChild(l)
            }
        case .settings:
            let l = makeLabel("입력 방식, 스크롤 속도, 볼륨, 오프셋", size: 18, color: Palette.dim)
            l.position = CGPoint(x: 640, y: y)
            detail.addChild(l)
        case .calibration:
            let l = makeLabel("소리에 맞춰 두드려서 판정 오프셋을 맞춰요 (지금 \(Int(app.settings.offsetMs))ms)",
                              size: 18, color: Palette.dim)
            l.position = CGPoint(x: 640, y: y)
            detail.addChild(l)
        }
        let folder = makeLabel("곡 폴더: \((SongLibrary.songsFolder.path as NSString).abbreviatingWithTildeInPath)  (O 키로 열기)",
                               size: 13, color: Palette.dim, bold: false)
        folder.position = CGPoint(x: 640, y: 60)
        detail.addChild(folder)
    }

    private func schedulePreview() {
        removeAction(forKey: "preview")
        app.audio.stop()
        guard case let .song(e) = items[index] else { return }
        run(.sequence([.wait(forDuration: 0.35), .run { [weak self] in
            // 전환 중인 이전 화면이면 새 화면의 음악을 건드리지 않는다
            guard let self, self.app.view.receiver === self, self.app.loadAudio(for: e) == nil else { return }
            self.app.audio.play(from: e.info.demoStart)
        }]), withKey: "preview")
    }

    // MARK: 난이도

    private func showCourses(_ e: SongEntry) {
        coursePanel.removeAllChildren()
        let dim = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 1280, height: 720))
        dim.fillColor = NSColor(white: 0, alpha: 0.6)
        dim.strokeColor = .clear
        coursePanel.addChild(dim)

        let title = makeLabel(e.info.title, size: 34)
        title.position = CGPoint(x: 640, y: 540)
        coursePanel.addChild(title)

        let courses = e.info.courses
        let width: CGFloat = 220
        let startX = 640 - CGFloat(courses.count - 1) * (width + 20) / 2
        for (i, c) in courses.enumerated() {
            let card = SKNode()
            card.position = CGPoint(x: startX + CGFloat(i) * (width + 20), y: 370)
            let bg = SKShapeNode(rect: CGRect(x: -width / 2, y: -110, width: width, height: 220), cornerRadius: 18)
            bg.fillColor = i == courseIndex ? Palette.don : Palette.panel
            bg.strokeColor = i == courseIndex ? .white : .clear
            bg.lineWidth = 3
            card.addChild(bg)
            let name = makeLabel(c.displayName, size: 30)
            name.position = CGPoint(x: 0, y: 50)
            card.addChild(name)
            let level = makeLabel("★ \(e.info.charts[c]!.level)", size: 24, color: Palette.gold)
            level.position = CGPoint(x: 0, y: 5)
            card.addChild(level)
            let notes = makeLabel("노트 \(e.info.charts[c]!.hitNotes.count)개", size: 15, color: Palette.dim, bold: false)
            notes.position = CGPoint(x: 0, y: -30)
            card.addChild(notes)
            if let r = app.records.record(song: e.id, course: c) {
                let rec = makeLabel("\(r.bestScore) · \(r.crown.displayName)", size: 15, color: Palette.dim, bold: false)
                rec.position = CGPoint(x: 0, y: -65)
                card.addChild(rec)
            }
            if i == courseIndex { card.setScale(1.06) }
            coursePanel.addChild(card)
        }

        var hint = "캇 이동 · 동 시작 · Esc 뒤로"
        if app.settings.autoplay { hint += "   ·   자동 연주 켜짐" }
        let h = makeLabel(hint, size: 18, color: Palette.dim, bold: false)
        h.position = CGPoint(x: 640, y: 200)
        coursePanel.addChild(h)
    }

    // MARK: 입력

    override func command(_ command: Command) {
        if choosingCourse {
            guard case let .song(e) = items[index] else { return }
            let courses = e.info.courses
            switch command {
            case .left, .up: courseIndex = (courseIndex + courses.count - 1) % courses.count
            case .right, .down: courseIndex = (courseIndex + 1) % courses.count
            case .confirm:
                Self.lastCourse = courses[courseIndex]
                app.present(GameScene(app: app, entry: e, course: courses[courseIndex]))
                return
            case .back:
                choosingCourse = false
                coursePanel.removeAllChildren()
                return
            default: return
            }
            showCourses(e)
            return
        }

        switch command {
        case .left, .up: index = (index + items.count - 1) % items.count
        case .right, .down: index = (index + 1) % items.count
        case .confirm:
            Self.lastIndex = index
            switch items[index] {
            case let .song(e):
                let courses = e.info.courses
                courseIndex = courses.lastIndex { $0 <= Self.lastCourse } ?? 0
                choosingCourse = true
                showCourses(e)
            case .addSongs: app.chooseSongFiles()
            case .settings: app.present(SettingsScene(app: app))
            case .calibration: app.present(CalibrationScene(app: app))
            }
            return
        case .back:
            app.present(TitleScene(app: app))
            return
        case .openFolder:
            NSWorkspace.shared.open(SongLibrary.songsFolder)
            return
        default: return
        }
        Self.lastIndex = index
        refresh(animated: true)
    }
}
