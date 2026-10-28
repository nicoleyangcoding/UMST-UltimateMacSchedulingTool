// Draws the UMST app icon (original artwork, plain shapes only) and writes
// Resources/AppIcon.icns plus docs/images/icon.png. Run: swift scripts/make_appicon.swift
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let icon = NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
    // Background tile on Apple's icon grid
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.3); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState(); shadow.set(); color(0x1B1E3C).setFill(); tilePath.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x2A2F6B), color(0x6B3FA0), color(0xE2556D)])!.draw(in: tilePath, angle: -60)

    // Frosted card
    let card = NSRect(x: 230, y: 250, width: 564, height: 520)
    let cardPath = NSBezierPath(roundedRect: card, xRadius: 70, yRadius: 70)
    NSGraphicsContext.saveGraphicsState()
    let cs = NSShadow(); cs.shadowColor = color(0x000000, 0.25); cs.shadowBlurRadius = 30; cs.shadowOffset = NSSize(width: 0, height: -14); cs.set()
    color(0xFFFFFF, 0.95).setFill(); cardPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Header band
    NSGraphicsContext.saveGraphicsState(); cardPath.addClip()
    NSGradient(colors: [color(0xFF5A5F), color(0xE2412D)])!.draw(in: NSRect(x: card.minX, y: card.minY, width: card.width, height: 130), angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Binder rings
    for x in [360.0, 664.0] {
        color(0xFFFFFF).setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 22, y: 205, width: 44, height: 100), xRadius: 22, yRadius: 22).fill()
    }

    // Week rows: agenda bars, one highlighted "today"
    let rows: [(CGFloat, UInt32, CGFloat)] = [(445, 0xE2412D, 300), (535, 0x0A84FF, 240), (625, 0x30A46C, 340)]
    for (y, accent, w) in rows {
        accent == 0xE2412D ? color(accent).setFill() : color(accent, 0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: 300, y: y - 28, width: 16, height: 56), xRadius: 8, yRadius: 8).fill()
        color(0x1B1E3C, 0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: 346, y: y - 16, width: w, height: 32), xRadius: 16, yRadius: 16).fill()
    }
    return true
}

func png(_ img: NSImage, _ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    try! png(icon, s).write(to: set.appendingPathComponent("icon_\(s)x\(s).png"))
    try! png(icon, s * 2).write(to: set.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
try! png(icon, 512).write(to: root.appendingPathComponent("docs/images/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/images/icon.png")
