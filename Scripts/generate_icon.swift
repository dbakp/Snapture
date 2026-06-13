import AppKit

// Renders the 1024×1024 master icon: Big Sur-style squircle (824pt, inset 100),
// indigo→violet gradient, white camera.viewfinder glyph.
let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let squircle = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: squircle, xRadius: 185, yRadius: 185)

// Soft drop shadow behind the squircle
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(srgbRed: 0.32, green: 0.27, blue: 0.91, alpha: 1).setFill()
path.fill()
NSShadow().set()

// Gradient fill
let gradient = NSGradient(
    starting: NSColor(srgbRed: 0.32, green: 0.27, blue: 0.91, alpha: 1),
    ending: NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1)
)!
gradient.draw(in: path, angle: 60)

// White glyph, tinted via sourceAtop
let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .medium)
if let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let symbolSize = symbol.size
    let scale = min(440 / symbolSize.width, 440 / symbolSize.height)
    let w = symbolSize.width * scale, h = symbolSize.height * scale
    let rect = NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h)

    let tinted = NSImage(size: symbolSize)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: symbolSize).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()

// Write master PNG
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}
let out = URL(fileURLWithPath: "AppIcon-master.png")
try! png.write(to: out)
print("Wrote \(out.path)")
