import AppKit

// `UMST --demo --snapshot <dir>` renders the README screenshots: the widget in every theme
// plus both Settings tabs, using demo data only. An app may capture its own windows without
// Screen Recording permission.

private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

@MainActor
enum Snapshot {
    static var directory: URL? {
        let args = ProcessInfo.processInfo.arguments
        guard isDemo, let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    static func run(widget: NSWindow, to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settings = AppSettings.shared
        var steps: [() -> Void] = []
        for t in Theme.all {
            steps.append { settings.themeID = t.id }
            steps.append { capture(widget, to: dir.appendingPathComponent("widget-\(t.id).png")) }
        }
        steps.append { settings.themeID = "glass"; SettingsWindow.show(.accounts) }
        steps.append { capture(NSApp.windows.first { $0.title == "UMST Settings" }, to: dir.appendingPathComponent("settings-accounts.png")) }
        steps.append { SettingsWindow.show(.appearance) }
        steps.append { capture(NSApp.windows.first { $0.title == "UMST Settings" }, to: dir.appendingPathComponent("settings-appearance.png")) }
        steps.append { NSApp.terminate(nil) }
        for (i, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 0.8, execute: step)
        }
    }

    private static func capture(_ window: NSWindow?, to url: URL) {
        guard let window,
              let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return }
        let create = unsafeBitCast(sym, to: CreateImage.self)
        // .optionIncludingWindow, window id, .boundsIgnoreFraming | .bestResolution
        guard let img = create(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
