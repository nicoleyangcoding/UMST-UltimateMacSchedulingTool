// Draws the UMST app icon (original artwork, plain shapes only): a tiny version of the widget,
// a week strip with today highlighted above three agenda rows.
// Writes Resources/AppIcon.icns plus docs/images/icon.png and icon-64.png.
//   swift scripts/make_appicon.swift            build the icon
//   swift scripts/make_appicon.swift --compare  write docs/images/icon-options.png with every style
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

struct Style {
    let name: String
    let top: UInt32, bottom: UInt32      // tile, very subtle vertical shade
    let ink: UInt32, inkAlpha: CGFloat   // day boxes and text lines
    let today: UInt32                    // highlighted day
    let marks: [UInt32]                  // agenda row markers
}

let styles = [
    Style(name: "ink", top: 0x2A2A31, bottom: 0x18181C, ink: 0xFFFFFF, inkAlpha: 0.16, today: 0xFF4F3F, marks: [0xFF4F3F, 0x3B9BFF, 0x34C77B]),
    Style(name: "paper", top: 0xFFFFFF, bottom: 0xF1EEE8, ink: 0x1C1B1F, inkAlpha: 0.14, today: 0xE8402F, marks: [0xE8402F, 0x0A84FF, 0x2FB36B]),
    Style(name: "red", top: 0xF2564A, bottom: 0xD93A2E, ink: 0xFFFFFF, inkAlpha: 0.32, today: 0xFFFFFF, marks: [0xFFFFFF, 0xFFFFFF, 0xFFFFFF]),
]
let chosen = "red"

func icon(_ s: Style) -> NSImage {
    NSImage(size: NSSize(width: 1024, height: 1024), flipped: true) { _ in
        // Tile on Apple's macOS icon grid, with the standard soft drop shadow
        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow(); sh.shadowColor = color(0, 0.28); sh.shadowBlurRadius = 24; sh.shadowOffset = NSSize(width: 0, height: -10); sh.set()
        color(s.bottom).setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: color(s.top), ending: color(s.bottom))!.draw(in: path, angle: 90)
        color(0xFFFFFF, s.name == "paper" ? 0 : 0.08).setStroke(); path.lineWidth = 4; path.stroke()
        if s.name == "paper" { color(0x000000, 0.08).setStroke(); path.lineWidth = 3; path.stroke() }

        // Week strip: seven day cells, today filled
        let cell: CGFloat = 80, gap: CGFloat = 14, stripW = cell * 7 + gap * 6
        let x0 = 512 - stripW / 2, y0: CGFloat = 250
        for i in 0..<7 {
            let r = NSRect(x: x0 + CGFloat(i) * (cell + gap), y: y0, width: cell, height: 104)
            let p = NSBezierPath(roundedRect: r, xRadius: 22, yRadius: 22)
            if i == 0 { color(s.today).setFill() } else { color(s.ink, s.inkAlpha).setFill() }
            p.fill()
        }

        // Agenda rows: colored marker + text line
        let rows: [(CGFloat, CGFloat)] = [(436, 470), (564, 370), (692, 430)]
        for (k, (y, w)) in rows.enumerated() {
            color(s.marks[k], s.name == "red" ? 0.95 : 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x0, y: y, width: 32, height: 84), xRadius: 16, yRadius: 16).fill()
            color(s.ink, s.inkAlpha + (s.name == "red" ? 0.1 : 0.06)).setFill()
            NSBezierPath(roundedRect: NSRect(x: x0 + 74, y: y + 16, width: w, height: 52), xRadius: 26, yRadius: 26).fill()
        }
        return true
    }
}

func png(_ img: NSImage, _ w: Int, _ h: Int? = nil) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h ?? w, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: w, height: h ?? w))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

if CommandLine.arguments.contains("--compare") {
    // Each style at Dock size and at menu/Finder-list size, on light and dark backgrounds
    let sheet = NSImage(size: NSSize(width: 1200, height: 560), flipped: true) { _ in
        color(0xF5F3EE).setFill(); NSRect(x: 0, y: 0, width: 1200, height: 280).fill()
        color(0x1E1E21).setFill(); NSRect(x: 0, y: 280, width: 1200, height: 280).fill()
        for (i, s) in styles.enumerated() {
            let img = icon(s), cx = CGFloat(200 + i * 400)
            for (row, bg) in [(0, CGFloat(0)), (1, CGFloat(280))] {
                _ = row
                img.draw(in: NSRect(x: cx - 110, y: bg + 30, width: 200, height: 200))
                img.draw(in: NSRect(x: cx + 110, y: bg + 105, width: 48, height: 48))
                img.draw(in: NSRect(x: cx + 170, y: bg + 117, width: 24, height: 24))
            }
            let label = NSAttributedString(string: s.name.capitalized, attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: color(0x6B6870)])
            label.draw(at: NSPoint(x: cx - 20, y: 238))
        }
        return true
    }
    try! png(sheet, 1200, 560).write(to: root.appendingPathComponent("docs/images/icon-options.png"))
    print("Wrote docs/images/icon-options.png")
    exit(0)
}

let img = icon(styles.first { $0.name == chosen }!)
let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    try! png(img, s).write(to: set.appendingPathComponent("icon_\(s)x\(s).png"))
    try! png(img, s * 2).write(to: set.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: set)
try! png(img, 512).write(to: root.appendingPathComponent("docs/images/icon.png"))
try! png(img, 64).write(to: root.appendingPathComponent("docs/images/icon-64.png"))
print("Wrote Resources/AppIcon.icns, docs/images/icon.png and icon-64.png")
