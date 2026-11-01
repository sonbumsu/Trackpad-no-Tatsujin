import AppKit

// 앱 아이콘 원본(1024px PNG)을 그린다. build.sh가 이것으로 AppIcon.icns를 만든다.
// 사용법: make_icon <로고.png> <출력.png>

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

// 로고(Resources/Logo.png)를 타일 안에 꽉 차게 얹는다. 투명한 여백은 잘라낸다.
let logoRep = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
var minX = logoRep.pixelsWide, minY = logoRep.pixelsHigh, maxX = 0, maxY = 0
for y in 0..<logoRep.pixelsHigh {
    for x in 0..<logoRep.pixelsWide where logoRep.colorAt(x: x, y: y)!.alphaComponent > 0.05 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
// colorAt은 위에서부터 세므로 그리기 좌표(아래에서부터)로 뒤집는다
let crop = NSRect(x: minX, y: logoRep.pixelsHigh - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
let logo = NSImage(size: NSSize(width: logoRep.pixelsWide, height: logoRep.pixelsHigh))
logo.addRepresentation(logoRep)
let box = tile.insetBy(dx: 30, dy: 30)
let scale = min(box.width / crop.width, box.height / crop.height)
let drawSize = NSSize(width: crop.width * scale, height: crop.height * scale)
NSGraphicsContext.current!.saveGraphicsState()
tilePath.addClip()
logo.draw(in: NSRect(x: box.midX - drawSize.width / 2, y: box.midY - drawSize.height / 2,
                     width: drawSize.width, height: drawSize.height),
          from: crop, operation: .sourceOver, fraction: 1)
NSGraphicsContext.current!.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
