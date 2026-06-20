import AppKit

// Renders a 1024x1024 app icon: white "hammer.fill" SF Symbol on a blue
// rounded-rect gradient (matches the menu bar icon).
// Usage: swift make-icon.swift [output.png]

let side = 1024

func newContext() -> (NSBitmapImageRep, NSGraphicsContext) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    return (rep, ctx)
}

let canvas = NSRect(x: 0, y: 0, width: side, height: side)

// --- symbol layer: white hammer on a transparent background ---
let (symRep, symCtx) = newContext()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = symCtx
let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .bold)
if let base = NSImage(systemSymbolName: "hammer.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    base.isTemplate = true
    let s = base.size
    let scale = (CGFloat(side) * 0.50) / max(s.width, s.height)
    let drawSize = NSSize(width: s.width * scale, height: s.height * scale)
    let drawRect = NSRect(
        x: (CGFloat(side) - drawSize.width) / 2,
        y: (CGFloat(side) - drawSize.height) / 2,
        width: drawSize.width, height: drawSize.height)
    base.draw(in: drawRect)
    NSColor.white.setFill()
    canvas.fill(using: .sourceAtop) // recolor only the symbol pixels
}
NSGraphicsContext.restoreGraphicsState()
let symbolImage = NSImage(size: canvas.size)
symbolImage.addRepresentation(symRep)

// --- main canvas: blue gradient rounded rect + symbol ---
let (rep, ctx) = newContext()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let bgRect = canvas.insetBy(dx: 84, dy: 84)
ctx.saveGraphicsState()
NSBezierPath(roundedRect: bgRect, xRadius: 190, yRadius: 190).addClip()
let grad = NSGradient(colors: [
    NSColor(red: 0.32, green: 0.58, blue: 0.99, alpha: 1.0),
    NSColor(red: 0.09, green: 0.33, blue: 0.85, alpha: 1.0)
])!
grad.draw(in: bgRect, angle: -90)
ctx.restoreGraphicsState()
symbolImage.draw(in: canvas)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to make PNG")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
