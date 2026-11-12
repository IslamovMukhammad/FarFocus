#!/usr/bin/env swift
// Draws the FarFocus app icon in code and writes Resources/AppIcon.iconset.
// Usage: swift Scripts/make_icon.swift   (from the package folder)
//
// The design: a matte graphite tile, like a lens barrel. Across it runs an engraved focus-distance scale
// (ticks, a few distances) ending in ∞, and a single amber index mark sits on the ∞: focus at infinity,
// the whole point of an eye break.

import AppKit

func lemniscate(center: NSPoint, width: CGFloat, height: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let a = width / 2
    let yScale = height / (a * 0.7072)
    for i in 0...160 {
        let t = Double(i) / 160 * 2 * .pi
        let d = 1 + sin(t) * sin(t)
        let p = NSPoint(x: center.x + a * cos(t) / d, y: center.y + a * sin(t) * cos(t) / d * yScale / 2)
        if i == 0 { path.move(to: p) } else { path.line(to: p) }
    }
    path.close()
    return path
}

func drawIcon(_ px: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = px / 1024   // design in 1024 units, y measured from the top

    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s)
    }
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: (1024 - y) * s) }

    let graphite = NSColor(srgbRed: 0x18 / 255, green: 0x19 / 255, blue: 0x1C / 255, alpha: 1)
    let ivory = NSColor(srgbRed: 0xEC / 255, green: 0xE7 / 255, blue: 0xDD / 255, alpha: 1)
    let amber = NSColor(srgbRed: 0xF0 / 255, green: 0xA4 / 255, blue: 0x3A / 255, alpha: 1)

    // Tile (macOS icon grid: 824 body centred in 1024, radius ~185) with a soft drop shadow.
    let tile = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    graphite.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Barrel shading: a faint horizontal band of light, darker toward top and bottom (a cylinder).
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(colorsAndLocations:
        (NSColor.black.withAlphaComponent(0.35), 0.0),
        (NSColor.white.withAlphaComponent(0.06), 0.46),
        (NSColor.white.withAlphaComponent(0.02), 0.56),
        (NSColor.black.withAlphaComponent(0.40), 1.0))!
        .draw(in: tile.bounds, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // The engraved scale: a baseline of ticks fading toward the left edge, numbers above the long ticks.
    let baseY: CGFloat = 600
    let marks: [(x: CGFloat, label: String?)] = [(230, "1"), (330, nil), (400, "3"), (470, nil), (530, "10")]
    for i in 0..<15 {
        let x = 200 + CGFloat(i) * 32
        guard x < 600 else { break }
        let long = marks.contains { abs($0.x - x) < 16 && $0.label != nil }
        ivory.withAlphaComponent(0.25 + 0.55 * (x - 200) / 400).setFill()
        NSBezierPath(rect: r(x - 3, baseY - (long ? 70 : 40), 6, long ? 70 : 40)).fill()
    }
    if px >= 128 {
        let font = NSFont.systemFont(ofSize: 74 * s, weight: .medium)
        for mark in marks {
            guard let label = mark.label else { continue }
            let x = 200 + (((mark.x - 200) / 32).rounded()) * 32
            let alpha = 0.25 + 0.55 * (x - 200) / 400
            let text = NSAttributedString(string: label, attributes: [.font: font,
                                                                      .foregroundColor: ivory.withAlphaComponent(alpha)])
            let size = text.size()
            text.draw(at: NSPoint(x: x * s - size.width / 2, y: (1024 - baseY + 92) * s))
        }
    }

    // ∞ at the far end, in amber: where the index rests.
    let inf = lemniscate(center: p(712, 526), width: 250 * s, height: 112 * s)
    inf.lineWidth = 34 * s
    inf.lineJoinStyle = .round
    amber.setStroke()
    inf.stroke()

    // The index: a line topped by a small triangle pointing up at the ∞.
    amber.setFill()
    let tri = NSBezierPath()
    tri.move(to: p(682, 684))
    tri.line(to: p(742, 684))
    tri.line(to: p(712, 640))
    tri.close()
    tri.fill()
    NSBezierPath(rect: r(703, 682, 18, 116)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: "Resources/AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = drawIcon(CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try png.write(to: out.appendingPathComponent(name))
    }
}
print("Wrote \(out.path)")
