// Turns icons/<host>.png into macOS-style tiles (tiles/<host>.png + .icns) and gives the
// Desktop group folders custom icons. Called by make_folders.py.
import AppKit

let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/UMST")
let src = base.appendingPathComponent("icons"), out = base.appendingPathComponent("tiles")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ img: NSImage, _ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Full-bleed logos (opaque corners) fill the tile; transparent ones sit on white with padding
func isFullBleed(_ img: NSImage) -> Bool {
    guard let rep = img.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: img.tiffRepresentation!) else { return false }
    let c = rep.colorAt(x: 1, y: 1)
    return (c?.alphaComponent ?? 0) > 0.9
}

func tile(_ logo: NSImage) -> NSImage {
    NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
        let r = NSRect(x: 100, y: 100, width: 824, height: 824)   // Apple icon grid
        let path = NSBezierPath(roundedRect: r, xRadius: 185, yRadius: 185)
        let shadow = NSShadow()
        shadow.shadowColor = .black.withAlphaComponent(0.28); shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width: 0, height: -10)
        NSGraphicsContext.saveGraphicsState(); shadow.set(); NSColor.white.setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState(); path.addClip()
        if isFullBleed(logo) { logo.draw(in: r) } else { logo.draw(in: r.insetBy(dx: 170, dy: 170)) }
        NSGraphicsContext.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.08).setStroke(); path.lineWidth = 3; path.stroke()
        return true
    }
}

func writeIcns(_ img: NSImage, to dest: URL) {
    let set = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
    try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for s in [16, 32, 128, 256, 512] {
        try? png(img, s).write(to: set.appendingPathComponent("icon_\(s)x\(s).png"))
        try? png(img, s * 2).write(to: set.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
    }
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", set.path, "-o", dest.path]; try? p.run(); p.waitUntilExit()
    try? FileManager.default.removeItem(at: set)
}

// Menu version: edge-to-edge rounded tile, no shadow margin, so every row's icon lines up at 16pt
func menuTile(_ logo: NSImage) -> NSImage {
    NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
        let path = NSBezierPath(roundedRect: r, xRadius: 15, yRadius: 15)
        path.addClip()
        if isFullBleed(logo) { logo.draw(in: r) } else {
            NSColor.white.setFill(); path.fill()
            logo.draw(in: r.insetBy(dx: 11, dy: 11))
        }
        return true
    }
}

for f in (try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)) ?? [] where f.pathExtension == "png" {
    guard let logo = NSImage(contentsOf: f) else { continue }
    let t = tile(logo), name = f.deletingPathExtension().lastPathComponent
    try? png(menuTile(logo), 64).write(to: out.appendingPathComponent(name + ".png"))   // 16pt @2x+
    writeIcns(t, to: out.appendingPathComponent(name + ".icns"))
}

// Desktop folder icons: system folder with a symbol embossed on it
let folderSymbols = ["Desktop": "tray.full.fill", "Personal": "person.fill", "School": "graduationcap.fill", "Work": "briefcase.fill"]
let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
for (name, sym) in folderSymbols {
    let path = desktop.appendingPathComponent(name).path
    guard FileManager.default.fileExists(atPath: path) else { continue }
    let folder = NSWorkspace.shared.icon(for: .folder)
    let icon = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { r in
        folder.draw(in: r)
        let cfg = NSImage.SymbolConfiguration(pointSize: 300, weight: .semibold)
        if let s = NSImage(systemSymbolName: sym, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
            let tinted = NSImage(size: s.size, flipped: false) { sr in
                s.draw(in: sr); NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.75, alpha: 0.85).set(); sr.fill(using: .sourceAtop); return true
            }
            let sz = tinted.size
            tinted.draw(in: NSRect(x: (1024 - sz.width) / 2, y: 400 - sz.height / 2, width: sz.width, height: sz.height))
        }
        return true
    }
    NSWorkspace.shared.setIcon(icon, forFile: path, options: [])
}
print("icons done")
