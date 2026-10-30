import AppKit
import SpriteKit

enum Side { case left, right }

struct DrumHit {
    var type: DrumType
    /// NSEvent.timestamp (시스템 업타임 기준)
    var timestamp: TimeInterval
    /// 트랙패드 정규화 좌표. 키보드 입력이면 nil
    var position: CGPoint?
    var side: Side
}

enum Command {
    case up, down, left, right, confirm, back, retry, openFolder
}

protocol InputReceiver: AnyObject {
    func drumHit(_ hit: DrumHit)
    func command(_ command: Command)
    func touchesUpdated(_ points: [CGPoint])
}

/// 트랙패드 터치와 키보드를 받아 북 입력으로 바꾸는 SKView
final class GameView: SKView {
    weak var receiver: InputReceiver?
    var onHit: ((DrumHit) -> Void)?
    var onDropFiles: (([URL]) -> Void)?
    private(set) var cursorLocked = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 파일 끌어다 놓기

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDropFiles?(urls)
        return true
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: 트랙패드

    override func touchesBegan(with event: NSEvent) {
        let began = event.touches(matching: .began, in: self).filter { !$0.isResting }
        // 세 손가락 이상 동시에 닿으면 시스템 제스처로 보고 무시
        if !began.isEmpty, began.count < 3 {
            let settings = Settings.shared
            if settings.layout == .fingers {
                let p = began.first!.normalizedPosition
                emit(DrumHit(type: began.count >= 2 ? .ka : .don, timestamp: event.timestamp,
                             position: p, side: p.x < 0.5 ? .left : .right))
            } else {
                for t in began.sorted(by: { $0.normalizedPosition.x < $1.normalizedPosition.x }) {
                    let p = t.normalizedPosition
                    emit(DrumHit(type: settings.layout.classify(p, rim: settings.rimSize),
                                 timestamp: event.timestamp, position: p, side: p.x < 0.5 ? .left : .right))
                }
            }
        }
        reportTouches(event)
    }

    override func touchesMoved(with event: NSEvent) { reportTouches(event) }
    override func touchesEnded(with event: NSEvent) { reportTouches(event) }
    override func touchesCancelled(with event: NSEvent) { reportTouches(event) }

    private func reportTouches(_ event: NSEvent) {
        receiver?.touchesUpdated(event.touches(matching: .touching, in: self).map(\.normalizedPosition))
    }

    private func emit(_ hit: DrumHit) {
        onHit?(hit)
        receiver?.drumHit(hit)
    }

    // 탭하여 클릭이 켜져 있으면 터치와 함께 클릭도 들어온다. 클릭은 쓰지 않는다.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    // MARK: 키보드

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        // 한글 입력 상태에서도 동작하도록 키 코드로 구분한다
        let drumKeys: [UInt16: (DrumType, Side)] = [
            3: (.don, .left), 38: (.don, .right), 49: (.don, .right), // F J Space
            2: (.ka, .left), 40: (.ka, .right), // D K
        ]
        if let (type, side) = drumKeys[event.keyCode] {
            if !event.isARepeat {
                emit(DrumHit(type: type, timestamp: event.timestamp, position: nil, side: side))
            }
            return
        }
        let commands: [UInt16: Command] = [
            126: .up, 125: .down, 123: .left, 124: .right,
            36: .confirm, 76: .confirm, 53: .back, 12: .back, 15: .retry, 31: .openFolder,
        ]
        if let c = commands[event.keyCode] { receiver?.command(c) }
    }

    // MARK: 커서 고정

    /// 커서가 창 밖으로 나가면 터치 이벤트가 끊기므로 창 가운데에 묶어 둔다
    func setCursorLocked(_ locked: Bool) {
        if locked {
            guard let window, let screen = window.screen else { return }
            let frame = window.convertToScreen(convert(bounds, to: nil))
            let center = CGPoint(x: frame.midX, y: screen.frame.maxY - frame.midY)
            CGWarpMouseCursorPosition(center)
            CGAssociateMouseAndMouseCursorPosition(0)
            if !cursorLocked { NSCursor.hide() }
            cursorLocked = true
        } else if cursorLocked {
            CGAssociateMouseAndMouseCursorPosition(1)
            NSCursor.unhide()
            cursorLocked = false
        }
    }
}
