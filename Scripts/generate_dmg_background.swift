import AppKit

// Renders the Snapture installer DMG window background: a branded indigo→violet
// pastel wash, glossy gradient arrow, translucent pedestals that frame the live
// app / Applications icons, and refined typography. Finder places the live icons
// on top at the coordinates these pedestals/arrow are drawn around (see
// Scripts/dmg_layout.py).
//
// Usage: swift generate_dmg_background.swift <output.png>
// Output: exactly 600 x 420 px, RGBA, fully opaque (Finder reliably loads PNG
// window backgrounds at the window's point size).

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let W: CGFloat = 600, H: CGFloat = 420

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 420,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError() }
rep.size = NSSize(width: W, height: H)
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx

// Top-down y helper: art is authored top-left, AppKit draws bottom-left.
func flip(_ topY: CGFloat) -> CGFloat { return H - topY }

// Brand palette --------------------------------------------------------------
func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let indigo   = srgb(0.36, 0.30, 0.93)
let violet   = srgb(0.55, 0.36, 0.96)
let inkTitle = srgb(0.16, 0.14, 0.34)   // deep indigo / near-black for title

// 1. BASE WASH — desaturated indigo→violet pastel, diagonal --------------------
let washTop = srgb(0.953, 0.949, 0.992)
let washMid = srgb(0.918, 0.910, 0.984)
let washBot = srgb(0.886, 0.878, 0.972)
let baseGrad = NSGradient(colors: [washTop, washMid, washBot],
                          atLocations: [0.0, 0.55, 1.0],
                          colorSpace: NSColorSpace.sRGB)!
baseGrad.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -78)

// 2. AMBIENT COLOR GLOWS — soft radial brand light, low opacity ----------------
func radialGlow(center: NSPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    let g = NSGradient(colors: [color.withAlphaComponent(alpha), color.withAlphaComponent(0)],
                       atLocations: [0.0, 1.0], colorSpace: NSColorSpace.sRGB)!
    g.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius,
           options: .drawsAfterEndingLocation)
}
radialGlow(center: NSPoint(x: 120, y: flip(70)),  radius: 300, color: indigo, alpha: 0.10)
radialGlow(center: NSPoint(x: 500, y: flip(360)), radius: 320, color: violet, alpha: 0.11)
radialGlow(center: NSPoint(x: 300, y: flip(185)), radius: 230, color: srgb(0.62, 0.50, 0.98), alpha: 0.05)

// 3. TOP GLOSS HIGHLIGHT — glassy sheen across the top band --------------------
let glossGrad = NSGradient(colors: [srgb(1, 1, 1, 0.55), srgb(1, 1, 1, 0.0)],
                           atLocations: [0.0, 1.0], colorSpace: NSColorSpace.sRGB)!
glossGrad.draw(in: NSRect(x: 0, y: flip(150), width: W, height: 150), angle: 90)
NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.6).setFill()
NSBezierPath(rect: NSRect(x: 0, y: H - 1.0, width: W, height: 1.0)).fill()

// 4. ICON PEDESTALS — soft translucent rounded platforms under each icon -------
func drawPlatform(centerX: CGFloat, topDownCenterY: CGFloat) {
    let cy = flip(topDownCenterY)
    let pw: CGFloat = 138, ph: CGFloat = 138
    let rect = NSRect(x: centerX - pw / 2, y: cy - ph / 2, width: pw, height: ph)
    let radius: CGFloat = 30

    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = srgb(0.30, 0.26, 0.55, 0.28)
    sh.shadowBlurRadius = 26
    sh.shadowOffset = NSSize(width: 0, height: -10)
    sh.set()
    let body = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: radius, yRadius: radius)
    srgb(1, 1, 1, 0.85).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let trayGrad = NSGradient(colors: [srgb(1, 1, 1, 0.78), srgb(0.93, 0.92, 0.99, 0.55)],
                              atLocations: [0.0, 1.0], colorSpace: NSColorSpace.sRGB)!
    trayGrad.draw(in: rect, angle: -90)
    let sheen = NSGradient(colors: [srgb(1, 1, 1, 0.6), srgb(1, 1, 1, 0.0)],
                           atLocations: [0.0, 1.0], colorSpace: NSColorSpace.sRGB)!
    sheen.draw(in: NSRect(x: rect.minX, y: rect.maxY - ph * 0.45, width: pw, height: ph * 0.45), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    srgb(1, 1, 1, 0.9).setStroke()
    border.lineWidth = 1
    border.stroke()
    let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -0.5, dy: -0.5), xRadius: radius + 0.5, yRadius: radius + 0.5)
    srgb(0.55, 0.48, 0.85, 0.18).setStroke()
    ring.lineWidth = 1
    ring.stroke()
}
drawPlatform(centerX: 150, topDownCenterY: 185)   // app icon
drawPlatform(centerX: 450, topDownCenterY: 185)   // Applications folder

// 5. GLOSSY ARROW — indigo→violet, inner highlight + drop shadow ---------------
func drawArrow() {
    let yMid = flip(185)
    let xStart: CGFloat = 260        // half-size arrow, centered on x = 300
    let xTip:   CGFloat = 340
    let shaftH: CGFloat = 8
    let headLen: CGFloat = 21
    let headHalf: CGFloat = 15
    let xHeadBase = xTip - headLen

    let p = NSBezierPath()
    let r = shaftH / 2
    p.move(to: NSPoint(x: xStart + r, y: yMid + r))
    p.line(to: NSPoint(x: xHeadBase, y: yMid + r))
    p.line(to: NSPoint(x: xHeadBase, y: yMid + headHalf))
    p.curve(to: NSPoint(x: xTip, y: yMid),
            controlPoint1: NSPoint(x: xHeadBase + headLen * 0.55, y: yMid + headHalf * 0.55),
            controlPoint2: NSPoint(x: xTip, y: yMid + headHalf * 0.18))
    p.curve(to: NSPoint(x: xHeadBase, y: yMid - headHalf),
            controlPoint1: NSPoint(x: xTip, y: yMid - headHalf * 0.18),
            controlPoint2: NSPoint(x: xHeadBase + headLen * 0.55, y: yMid - headHalf * 0.55))
    p.line(to: NSPoint(x: xHeadBase, y: yMid - r))
    p.line(to: NSPoint(x: xStart + r, y: yMid - r))
    p.appendArc(withCenter: NSPoint(x: xStart + r, y: yMid),
                radius: r, startAngle: 270, endAngle: 90, clockwise: true)
    p.close()

    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = srgb(0.30, 0.20, 0.70, 0.40)
    sh.shadowBlurRadius = 14
    sh.shadowOffset = NSSize(width: 0, height: -5)
    sh.set()
    srgb(0.45, 0.33, 0.95, 1).setFill()
    p.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    p.addClip()
    let arrowGrad = NSGradient(colors: [indigo, violet],
                               atLocations: [0.0, 1.0], colorSpace: NSColorSpace.sRGB)!
    arrowGrad.draw(in: NSRect(x: xStart - 2, y: yMid - headHalf, width: (xTip - xStart) + 4, height: headHalf * 2), angle: 0)
    let bounds = p.bounds
    let hl = NSGradient(colors: [srgb(1, 1, 1, 0.45), srgb(1, 1, 1, 0.0)],
                        atLocations: [0.0, 1.0], colorSpace: NSColorSpace.sRGB)!
    hl.draw(in: NSRect(x: bounds.minX, y: yMid, width: bounds.width, height: headHalf), angle: 90)
    let lo = NSGradient(colors: [srgb(0.18, 0.12, 0.45, 0.0), srgb(0.18, 0.12, 0.45, 0.22)],
                        atLocations: [0.0, 1.0], colorSpace: NSColorSpace.sRGB)!
    lo.draw(in: NSRect(x: bounds.minX, y: yMid - headHalf, width: bounds.width, height: headHalf), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    srgb(1, 1, 1, 0.35).setStroke()
    p.lineWidth = 1
    p.stroke()
    NSGraphicsContext.restoreGraphicsState()
}
drawArrow()

// 6. TYPOGRAPHY — title (deep indigo, tight) + muted subtitle ------------------
func drawCenteredText(_ s: String, font: NSFont, color: NSColor, topDownY: CGFloat, tracking: CGFloat) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: para, .kern: tracking
    ]
    let astr = NSAttributedString(string: s, attributes: attrs)
    let size = astr.size()
    let y = flip(topDownY) - size.height
    astr.draw(in: NSRect(x: 0, y: y, width: W, height: size.height + 2))
}
drawCenteredText("Install Snapture",
                 font: .systemFont(ofSize: 33, weight: .semibold), color: inkTitle,
                 topDownY: 52, tracking: 0.2)
drawCenteredText("Drag Snapture onto the Applications folder",
                 font: .systemFont(ofSize: 13.5, weight: .regular),
                 color: srgb(0.41, 0.39, 0.57, 0.92), topDownY: 98, tracking: 0.35)

// 7. FINALIZE — flatten onto an opaque base so the PNG has no transparency -----
NSGraphicsContext.restoreGraphicsState()

guard let finalRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 420,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError() }
finalRep.size = NSSize(width: W, height: H)
let fctx = NSGraphicsContext(bitmapImageRep: finalRep)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = fctx
washBot.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
rep.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()

guard let png = finalRep.representation(using: .png, properties: [:]) else { fatalError("No PNG data") }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("✓ DMG background → \(outPath) (\(Int(W))×\(Int(H))px)")
} catch {
    fatalError("Write failed: \(error)")
}
