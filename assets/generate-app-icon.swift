import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create icon canvas\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.clear.setFill()
canvas.fill()

let tile = NSBezierPath(
    roundedRect: NSRect(x: 92, y: 92, width: 840, height: 840),
    xRadius: 190,
    yRadius: 190
)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -22)
shadow.set()

let gradient = NSGradient(colors: [
    NSColor(red: 0.16, green: 0.31, blue: 1.0, alpha: 1),
    NSColor(red: 0.42, green: 0.20, blue: 0.91, alpha: 1),
    NSColor(red: 0.72, green: 0.14, blue: 0.92, alpha: 1),
])!
gradient.draw(in: tile, angle: -48)

NSGraphicsContext.current?.saveGraphicsState()
tile.addClip()
let glow = NSGradient(
    starting: NSColor.white.withAlphaComponent(0.34),
    ending: NSColor.white.withAlphaComponent(0)
)!
glow.draw(
    fromCenter: NSPoint(x: 290, y: 790),
    radius: 10,
    toCenter: NSPoint(x: 430, y: 620),
    radius: 560,
    options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
)
NSGraphicsContext.current?.restoreGraphicsState()

NSColor.white.withAlphaComponent(0.18).setStroke()
tile.lineWidth = 8
tile.stroke()

NSShadow().set()
let noteColor = NSColor.white.withAlphaComponent(0.96)
noteColor.setFill()

let beam = NSBezierPath()
beam.move(to: NSPoint(x: 330, y: 712))
beam.line(to: NSPoint(x: 646, y: 786))
beam.line(to: NSPoint(x: 646, y: 700))
beam.line(to: NSPoint(x: 330, y: 626))
beam.close()
beam.fill()

NSBezierPath(rect: NSRect(x: 330, y: 390, width: 72, height: 300)).fill()
NSBezierPath(rect: NSRect(x: 574, y: 455, width: 72, height: 290)).fill()
NSBezierPath(ovalIn: NSRect(x: 220, y: 320, width: 192, height: 142)).fill()
NSBezierPath(ovalIn: NSRect(x: 464, y: 385, width: 192, height: 142)).fill()

let badgeRect = NSRect(x: 564, y: 190, width: 286, height: 286)
NSColor(red: 0.08, green: 0.09, blue: 0.25, alpha: 0.72).setFill()
NSBezierPath(ovalIn: badgeRect).fill()
NSColor.white.withAlphaComponent(0.22).setStroke()
let badgeBorder = NSBezierPath(ovalIn: badgeRect.insetBy(dx: 5, dy: 5))
badgeBorder.lineWidth = 8
badgeBorder.stroke()

noteColor.setFill()
NSBezierPath(
    roundedRect: NSRect(x: 678, y: 286, width: 58, height: 116),
    xRadius: 29,
    yRadius: 29
).fill()
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 628, y: 320))
arrow.line(to: NSPoint(x: 707, y: 236))
arrow.line(to: NSPoint(x: 786, y: 320))
arrow.line(to: NSPoint(x: 744, y: 360))
arrow.line(to: NSPoint(x: 707, y: 320))
arrow.line(to: NSPoint(x: 670, y: 360))
arrow.close()
arrow.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not encode icon PNG\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
