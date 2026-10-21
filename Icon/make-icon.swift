// Draws the Notchless app icon and writes Icon/AppIcon.icns.
// Run from the repo root: swift Icon/make-icon.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func notchPath(_ r: CGRect, ear: CGFloat, bottom: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX, y: r.minY))
    p.addQuadCurve(to: CGPoint(x: r.minX + ear, y: r.minY + ear), control: CGPoint(x: r.minX + ear, y: r.minY))
    p.addLine(to: CGPoint(x: r.minX + ear, y: r.maxY - bottom))
    p.addQuadCurve(to: CGPoint(x: r.minX + ear + bottom, y: r.maxY), control: CGPoint(x: r.minX + ear, y: r.maxY))
    p.addLine(to: CGPoint(x: r.maxX - ear - bottom, y: r.maxY))
    p.addQuadCurve(to: CGPoint(x: r.maxX - ear, y: r.maxY - bottom), control: CGPoint(x: r.maxX - ear, y: r.maxY))
    p.addLine(to: CGPoint(x: r.maxX - ear, y: r.minY + ear))
    p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - ear, y: r.minY))
    p.closeSubpath()
    return p
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], at c: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius, options: [])
}

/// Draws on a 1024 canvas, top-left origin.
func draw(_ ctx: CGContext) {
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // Squircle body, Apple's 824pt icon grid.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.45))
    ctx.addPath(squircle); ctx.setFillColor(color(0x101016)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()
    linear(ctx, [color(0x2A2A36), color(0x0A0A0F)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    // Warm glow spilling out from under the open notch.
    radial(ctx, [color(0xFF7A3D, 0.55), color(0xFF3D7F, 0.18), color(0xFF3D7F, 0)], at: CGPoint(x: 512, y: 720), radius: 400)

    // Menu bar strip the notch hangs from.
    ctx.setFillColor(color(0xFFFFFF, 0.07)); ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 74))

    // The open notch.
    let notch = notchPath(CGRect(x: 214, y: 100, width: 596, height: 590), ear: 34, bottom: 100)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 24), blur: 60, color: color(0x000000, 0.7))
    ctx.addPath(notch); ctx.setFillColor(color(0x000000)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(notch); ctx.setLineWidth(3); ctx.replacePathWithStrokedPath(); ctx.clip()
    linear(ctx, [color(0xFFFFFF, 0), color(0xFFFFFF, 0.22)], from: CGPoint(x: 512, y: 300), to: CGPoint(x: 512, y: 690))
    ctx.restoreGState()

    // Menu bar items blooming out of it.
    let palette: [(UInt32, UInt32)] = [(0xFFB347, 0xFF5E3A), (0xC4B5FD, 0x7C3AED), (0x67E8F9, 0x0284C7),
                                       (0xF9A8D4, 0xDB2777), (0xBEF264, 0x16A34A), (0xFDE68A, 0xF59E0B)]
    let tile: CGFloat = 124, gap: CGFloat = 34
    let startX = 512 - (tile * 3 + gap * 2) / 2
    for (i, pair) in palette.enumerated() {
        let rect = CGRect(x: startX + CGFloat(i % 3) * (tile + gap), y: 236 + CGFloat(i / 3) * (tile + gap), width: tile, height: tile)
        let path = CGPath(roundedRect: rect, cornerWidth: 36, cornerHeight: 36, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 30, color: color(pair.1, 0.55))
        ctx.addPath(path); ctx.setFillColor(color(pair.1)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        linear(ctx, [color(pair.0), color(pair.1)], from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))
        linear(ctx, [color(0xFFFFFF, 0.35), color(0xFFFFFF, 0)], from: CGPoint(x: rect.midX, y: rect.minY), to: CGPoint(x: rect.midX, y: rect.midY))
        ctx.restoreGState()
    }
    // Caption line under the grid, as in the app.
    ctx.setFillColor(color(0xFFFFFF, 0.2))
    ctx.addPath(CGPath(roundedRect: CGRect(x: 412, y: 584, width: 200, height: 16), cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.fillPath()

    // The "hidden" dot from the app's UI.
    let dot = CGPoint(x: startX + tile - 8, y: 244)
    radial(ctx, [color(0xFFD08A, 1), color(0xFF9F45, 0.9), color(0xFF9F45, 0)], at: dot, radius: 30)
    ctx.setFillColor(color(0xFFF3DC)); ctx.fillEllipse(in: CGRect(x: dot.x - 9, y: dot.y - 9, width: 18, height: 18))

    // Glass rim.
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squircle); ctx.setLineWidth(4); ctx.replacePathWithStrokedPath(); ctx.clip()
    linear(ctx, [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0.04)], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))
    ctx.restoreGState()
}

let iconset = URL(fileURLWithPath: "Icon/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
        draw(ctx)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Icon/AppIcon.icns"]
try! task.run(); task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("Wrote Icon/AppIcon.icns")
