import AppKit
import SpriteKit

/// 화면 전환과 공용 서비스
final class AppContext {
    let view: GameView
    let audio = AudioService()
    let settings = Settings.shared
    let records = RecordStore(url: SongLibrary.supportFolder.appendingPathComponent("records.json"))
    private(set) var library: [SongEntry] = []

    init(view: GameView) {
        self.view = view
        view.onHit = { [unowned self] hit in
            self.audio.play(hit.type == .don ? .don : .ka)
        }
        view.onDropFiles = { [unowned self] urls in self.importSongs(urls) }
        reloadLibrary()
    }

    func reloadLibrary() { library = SongLibrary.load() }

    /// 곡을 가져온다. 연주 중에는 받지 않는다.
    func importSongs(_ urls: [URL]) {
        guard !(view.scene is GameScene), !(view.scene is ImportScene) else { return }
        present(ImportScene(app: self, urls: urls))
    }

    /// 파일 선택 창을 띄운다. 그동안은 커서 고정을 푼다.
    func chooseSongFiles() {
        let wasLocked = view.cursorLocked
        view.setCursorLocked(false)
        let panel = NSOpenPanel()
        panel.message = "음악 파일(mp3, m4a, wav…)을 고르면 채보를 자동으로 만들어요. TJA나 곡 폴더도 돼요."
        panel.prompt = "추가"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        let response = panel.runModal()
        if wasLocked { view.setCursorLocked(true) }
        if response == .OK, !panel.urls.isEmpty { importSongs(panel.urls) }
    }

    /// 이전 장면의 음악은 여기서 끈다. 장면의 willMove(from:)는 전환이 끝난 뒤에 불려서
    /// 거기서 끄면 새 장면이 막 시작한 음악까지 꺼진다.
    func present(_ scene: BaseScene) {
        audio.stop()
        view.receiver = scene
        view.presentScene(scene, transition: .crossFade(withDuration: 0.2))
    }

    /// 곡 음악을 준비한다. 실패하면 이유를 돌려준다.
    func loadAudio(for entry: SongEntry) -> String? {
        switch entry.audio {
        case let .demo(song):
            audio.load(samples: DemoAudioCache.samples(for: song))
            return nil
        case let .file(url):
            guard let url else { return "음악 파일을 찾을 수 없어요 (WAVE: \(entry.info.wave ?? "없음"))" }
            do {
                try audio.load(url: url)
                return nil
            } catch {
                return "음악 파일을 열 수 없어요: \(url.lastPathComponent)\n(ogg는 지원되지 않을 수 있어요. mp3/m4a/wav로 바꿔 주세요)"
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var view: GameView!
    private var context: AppContext!
    private var wantsCursorLock = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        DemoAudioCache.prewarm()
        buildMenu()

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "트릭패드의 달인"
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.center()

        view = GameView(frame: window.contentLayoutRect)
        view.preferredFramesPerSecond = 120
        view.ignoresSiblingOrder = true
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)

        context = AppContext(view: view)
        context.present(TitleScene(app: context))
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) { relockCursor() }
    func applicationWillResignActive(_ notification: Notification) { view?.setCursorLocked(false) }
    func applicationWillTerminate(_ notification: Notification) { view?.setCursorLocked(false) }
    func windowDidResize(_ notification: Notification) { relockCursor() }
    func windowDidEnterFullScreen(_ notification: Notification) { relockCursor() }
    func windowDidExitFullScreen(_ notification: Notification) { relockCursor() }

    private func relockCursor() {
        guard wantsCursorLock, NSApp.isActive else { return }
        view?.setCursorLocked(true)
    }

    @objc private func addSongs() {
        context.chooseSongFiles()
    }

    @objc private func toggleCursorLock() {
        wantsCursorLock.toggle()
        wantsCursorLock ? relockCursor() : view.setCursorLocked(false)
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "음악 추가…", action: #selector(addSongs), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "커서 고정 켜기/끄기", action: #selector(toggleCursorLock), keyEquivalent: "l").target = self
        appMenu.addItem(withTitle: "전체 화면", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "트릭패드의 달인 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = main
    }
}
