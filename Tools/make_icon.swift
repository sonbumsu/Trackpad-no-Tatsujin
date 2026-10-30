import AppKit

// 앱 아이콘 원본(1024px PNG)을 그린다. build.sh가 이것으로 AppIcon.icns를 만든다.
// 사용법: make_icon <출력.png>

let size = 1024.0
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS 아이콘 격자: 1024 안에 824 크기의 둥근 사각형
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.current!.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.current!.restoreGraphicsState()

NSGradient(starting: NSColor(red: 0.24, green: 0.20, blue: 0.38, alpha: 1),
           ending: NSColor(red: 0.10, green: 0.09, blue: 0.17, alpha: 1))!.draw(in: tilePath, angle: -90)

// 트랙패드 윤곽 (캇 영역 = 테두리)
let pad = NSRect(x: 190, y: 250, width: 644, height: 470)
let padPath = NSBezierPath(roundedRect: pad, xRadius: 48, yRadius: 48)
NSColor(red: 0.27, green: 0.72, blue: 0.82, alpha: 0.9).setFill()
padPath.fill()
let inner = NSBezierPath(roundedRect: pad.insetBy(dx: 70, dy: 70), xRadius: 26, yRadius: 26)
NSColor(red: 0.13, green: 0.12, blue: 0.21, alpha: 1).setFill()
inner.fill()

// 가운데 북 (동)
func circle(_ c: NSPoint, _ r: Double) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}
let center = NSPoint(x: 512, y: 485)
NSColor(white: 0.06, alpha: 1).setFill()
circle(center, 190).fill()
NSColor.white.setFill()
circle(center, 172).fill()
NSColor(red: 0.96, green: 0.30, blue: 0.20, alpha: 1).setFill()
circle(center, 140).fill()
NSColor(white: 1, alpha: 0.28).setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 70, y: center.y + 45, width: 95, height: 48)).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
