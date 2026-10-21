// Regenerate: swift scripts/make_icon.swift /tmp/icon_1024.png, then resize into Planificador/Assets.xcassets/AppIcon.appiconset.
import AppKit

// Agenda app icon: macOS rounded-square, blue→indigo gradient, white calendar page with a checkmark.
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // macOS icon grid: 824pt body centered in 1024 with ~185pt corner radius.
    let inset: CGFloat = 100
    let body = rect.insetBy(dx: inset, dy: inset)
    let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.55, blue: 1.0, alpha: 1), NSColor(srgbRed: 0.36, green: 0.27, blue: 0.86, alpha: 1)])!
        .draw(in: path, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Page
    let page = NSRect(x: body.midX - 250, y: body.midY - 250, width: 500, height: 470)
    let pagePath = NSBezierPath(roundedRect: page, xRadius: 70, yRadius: 70)
    NSColor.white.setFill()
    pagePath.fill()

    // Header band
    NSGraphicsContext.current?.saveGraphicsState()
    pagePath.addClip()
    NSColor(srgbRed: 1.0, green: 0.36, blue: 0.33, alpha: 1).setFill()
    NSRect(x: page.minX, y: page.maxY - 120, width: page.width, height: 120).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Rings
    NSColor.white.setFill()
    for x in [page.minX + 130, page.maxX - 130] {
        NSBezierPath(roundedRect: NSRect(x: x - 22, y: page.maxY - 60, width: 44, height: 110), xRadius: 22, yRadius: 22).fill()
    }

    // Checkmark
    let check = NSBezierPath()
    check.lineWidth = 58
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    check.move(to: NSPoint(x: page.minX + 125, y: page.minY + 185))
    check.line(to: NSPoint(x: page.minX + 215, y: page.minY + 95))
    check.line(to: NSPoint(x: page.maxX - 115, y: page.minY + 280))
    NSColor(srgbRed: 0.33, green: 0.45, blue: 0.98, alpha: 1).setStroke()
    check.stroke()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
