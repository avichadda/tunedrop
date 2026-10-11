import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-dmg-background.swift OUTPUT.png\n", stderr)
    exit(2)
}

let width = 660
let height = 420
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create DMG background canvas\n", stderr)
    exit(1)
}

func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
    ]
    let size = text.size(withAttributes: attributes)
    text.draw(
        at: NSPoint(x: (CGFloat(width) - size.width) / 2, y: y),
        withAttributes: attributes
    )
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
let gradient = NSGradient(colors: [
    NSColor(red: 0.09, green: 0.17, blue: 0.52, alpha: 1),
    NSColor(red: 0.31, green: 0.18, blue: 0.70, alpha: 1),
    NSColor(red: 0.62, green: 0.12, blue: 0.78, alpha: 1),
])!
gradient.draw(in: canvas, angle: -24)

let glow = NSGradient(
    starting: NSColor(red: 0.34, green: 0.55, blue: 1, alpha: 0.65),
    ending: NSColor(red: 0.34, green: 0.55, blue: 1, alpha: 0)
)!
glow.draw(
    fromCenter: NSPoint(x: 120, y: 360),
    radius: 0,
    toCenter: NSPoint(x: 190, y: 290),
    radius: 360,
    options: [.drawsAfterEndingLocation]
)

drawCentered(
    "Install TuneDrop",
    y: 346,
    font: .systemFont(ofSize: 30, weight: .bold),
    color: .white
)
drawCentered(
    "Drag TuneDrop to Applications",
    y: 312,
    font: .systemFont(ofSize: 17, weight: .medium),
    color: NSColor.white.withAlphaComponent(0.82)
)

let arrowColor = NSColor.white.withAlphaComponent(0.88)
arrowColor.setStroke()
arrowColor.setFill()

let shaft = NSBezierPath()
shaft.move(to: NSPoint(x: 275, y: 190))
shaft.line(to: NSPoint(x: 362, y: 190))
shaft.lineWidth = 8
shaft.lineCapStyle = .round
shaft.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 390, y: 190))
arrowHead.line(to: NSPoint(x: 358, y: 215))
arrowHead.line(to: NSPoint(x: 358, y: 165))
arrowHead.close()
arrowHead.fill()

drawCentered(
    "TuneDrop uses your installed CLI to archive authorized music.",
    y: 31,
    font: .systemFont(ofSize: 12, weight: .regular),
    color: NSColor.white.withAlphaComponent(0.62)
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode DMG background PNG\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
