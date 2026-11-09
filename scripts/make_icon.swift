// Regenerate: swift scripts/make_icon.swift /tmp/icon_1024.png, then resize into Planificador/Assets.xcassets/AppIcon.appiconset
// (sips -z N N /tmp/icon_1024.png --out icon_N.png for 16, 32, 64, 128, 256, 512, 1024).
import AppKit

// Agenda app icon: a dark glass squircle with one glowing day ring (cyan → violet → pink)
// and a bright "now" dot where the ring ends. Minimal: the day as a dial, nothing else.
let size: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Linear blend through several stops, t in 0...1.
func blend(_ stops: [NSColor], _ t: CGFloat) -> NSColor {
    let scaled = min(max(t, 0), 1) * CGFloat(stops.count - 1)
    let i = min(Int(scaled), stops.count - 2)
    return stops[i].blended(withFraction: scaled - CGFloat(i), of: stops[i + 1])!
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    // macOS icon grid: 824pt body centered in 1024.
    let body = rect.insetBy(dx: 100, dy: 100)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    // Body with a soft drop shadow.
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSGradient(colors: [color(0x1D1A3A), color(0x0B0A16)])!.draw(in: squircle, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    // Aurora behind the ring: a violet bloom low-left, a cyan one top-right.
    NSGradient(colors: [color(0x7B61FF, 0.45), color(0x7B61FF, 0)])!
        .draw(fromCenter: NSPoint(x: body.minX + 220, y: body.minY + 200), radius: 0,
              toCenter: NSPoint(x: body.minX + 220, y: body.minY + 200), radius: 520, options: [])
    NSGradient(colors: [color(0x38D9FF, 0.28), color(0x38D9FF, 0)])!
        .draw(fromCenter: NSPoint(x: body.maxX - 160, y: body.maxY - 140), radius: 0,
              toCenter: NSPoint(x: body.maxX - 160, y: body.maxY - 140), radius: 460, options: [])
    // Glass sheen on the top half.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.14), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Hairline rim, like the edge of a glass pane.
    NSColor.white.withAlphaComponent(0.12).setStroke()
    let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
    rim.lineWidth = 4
    rim.stroke()

    let center = NSPoint(x: body.midX, y: body.midY)
    let radius: CGFloat = 228
    let width: CGFloat = 76

    // Faint full track.
    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = width
    NSColor.white.withAlphaComponent(0.07).setStroke()
    track.stroke()

    // The day ring: from 12 o'clock clockwise through 300°, drawn as small segments to follow the gradient.
    let stops = [color(0x38D9FF), color(0x7B61FF), color(0xFF5FA2)]
    let start: CGFloat = 90, sweep: CGFloat = 300, steps = 300
    func point(_ angle: CGFloat) -> NSPoint {
        NSPoint(x: center.x + radius * cos(angle * .pi / 180), y: center.y + radius * sin(angle * .pi / 180))
    }
    func drawRing() {
        for step in 0..<steps {
            let a0 = start - sweep * CGFloat(step) / CGFloat(steps)
            let a1 = start - sweep * CGFloat(step + 1) / CGFloat(steps) - 0.6 // overlap hides seams
            let segment = NSBezierPath()
            segment.appendArc(withCenter: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: true)
            segment.lineWidth = width
            blend(stops, CGFloat(step) / CGFloat(steps)).setStroke()
            segment.stroke()
        }
        // Round start cap.
        let cap = point(start)
        stops[0].setFill()
        NSBezierPath(ovalIn: NSRect(x: cap.x - width / 2, y: cap.y - width / 2, width: width, height: width)).fill()
    }

    // Glow pass, then the crisp ring on top.
    NSGraphicsContext.current?.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0x7B61FF, 0.9)
    glow.shadowBlurRadius = 60
    glow.shadowOffset = .zero
    glow.set()
    drawRing()
    NSGraphicsContext.current?.restoreGraphicsState()
    drawRing()

    // "Now": a white dot riding the end of the ring, with a pink halo.
    let end = point(start - sweep)
    NSGraphicsContext.current?.saveGraphicsState()
    let halo = NSShadow()
    halo.shadowColor = color(0xFF5FA2, 1)
    halo.shadowBlurRadius = 50
    halo.shadowOffset = .zero
    halo.set()
    NSColor.white.setFill()
    let dot: CGFloat = 92
    NSBezierPath(ovalIn: NSRect(x: end.x - dot / 2, y: end.y - dot / 2, width: dot, height: dot)).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
