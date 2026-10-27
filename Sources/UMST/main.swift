import AppKit
import SwiftUI

struct Link: Decodable { let name: String; let profile: String?; let url: String?; let app: String?; let account: String? }
struct LinkGroup: Decodable { let group: String; let items: [Link] }

let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/UMST")
let linksFile = supportDir.appendingPathComponent("links.json")
let tilesDir = supportDir.appendingPathComponent("tiles")
let chromeURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
let iconSize = NSSize(width: 16, height: 16)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let linksItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let desktopItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let addItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let addPopover = NSPopover()
    let linkPopover = NSPopover()
    var widget: CalendarWidgetController?
    let menu = NSMenu()
    var links: [Link] = []
    var watcher: DispatchSourceFileSystemObject?
    var hiddenApps: [String] = []
    var frontApp: String?
    let showIcon = symbol("macwindow.on.rectangle", "Show Desktop")
    let restoreIcon = symbol("rectangle.on.rectangle.slash", "Bring Windows Back")

    func applicationDidFinishLaunching(_ n: Notification) {
        linksItem.button?.image = symbol("square.grid.2x2", "Quick Links")
        linksItem.menu = menu
        desktopItem.button?.image = showIcon
        desktopItem.button?.toolTip = "Show Desktop"
        desktopItem.button?.target = self
        desktopItem.button?.action = #selector(toggleDesktop)
        buildMenu()
        watchLinks()

        addItem.button?.image = symbol("calendar.badge.plus", "Add to Calendar")
        addItem.button?.toolTip = "Add to Calendar"
        addItem.button?.target = self
        addItem.button?.action = #selector(toggleQuickAdd)
        addPopover.behavior = .transient
        addPopover.contentViewController = NSHostingController(rootView: QuickAddView { [weak self] in
            self?.addPopover.performClose(nil)
        })
        CalendarStore.shared.start()
        widget = CalendarWidgetController { [weak self] in self?.toggleQuickAdd() }
    }

    // Opens after the menu has closed, anchored to the Quick Links icon
    @objc func showAddLink() {
        DispatchQueue.main.async { [self] in
            guard let b = linksItem.button else { return }
            linkPopover.behavior = .transient
            linkPopover.contentViewController = NSHostingController(rootView: AddLinkView { [weak self] in
                self?.linkPopover.performClose(nil)
            })
            NSApp.activate(ignoringOtherApps: true)
            linkPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        }
    }

    @objc func toggleQuickAdd() {
        if addPopover.isShown { addPopover.performClose(nil); return }
        guard let b = addItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)   // so typing goes straight into the box
        addPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
    }

    // Menu is built once and only rebuilt when links.json changes, so opening it costs nothing
    func buildMenu() {
        menu.removeAllItems()
        let groups = (try? JSONDecoder().decode([LinkGroup].self, from: Data(contentsOf: linksFile))) ?? []
        links = groups.flatMap(\.items)
        var tag = 0
        for (gi, g) in groups.enumerated() {
            if gi > 0 { menu.addItem(.separator()) }
            menu.addItem(.sectionHeader(title: g.group))
            let names = g.items.map(\.name)
            for l in g.items {
                let mi = NSMenuItem(title: l.name, action: #selector(openLink(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = tag; tag += 1
                mi.image = icon(for: l)
                mi.toolTip = l.account
                // Same-named rows (the Gmails) get the account inline in grey, keeping every row one line
                if names.filter({ $0 == l.name }).count > 1, let a = l.account {
                    let t = NSMutableAttributedString(string: l.name, attributes: [.font: NSFont.menuFont(ofSize: 0)])
                    t.append(NSAttributedString(string: "  " + (a.split(separator: "@").first.map(String.init) ?? a),
                                                attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
                    mi.attributedTitle = t
                }
                menu.addItem(mi)
            }
        }
        let queued = LinkAdder.pending()
        if !queued.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Pending Requests"))
            for r in queued {
                let mi = NSMenuItem(title: "\(r.text)  ·  \(r.group)", action: nil, keyEquivalent: "")
                mi.image = symbol("clock", nil)
                mi.isEnabled = false
                menu.addItem(mi)
            }
        }
        menu.addItem(.separator())
        let addLink = NSMenuItem(title: "Add Link…", action: #selector(showAddLink), keyEquivalent: "n")
        addLink.target = self
        addLink.image = symbol("plus", nil)
        menu.addItem(addLink)
        let edit = NSMenuItem(title: "Edit Links…", action: #selector(editLinks), keyEquivalent: ",")
        edit.target = self
        edit.image = symbol("pencil", nil)
        menu.addItem(edit)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        settings.image = symbol("gearshape", nil)
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit UMST", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quit.image = symbol("power", nil)
        menu.addItem(quit)
    }

    func icon(for l: Link) -> NSImage? {
        var img: NSImage?
        if let app = l.app {
            // App icons carry ~10% transparent margin; crop it so it matches the site tiles
            let full = NSWorkspace.shared.icon(forFile: "/Applications/\(app).app")
            img = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
                full.draw(in: r, from: NSRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: full.size.width / 1024, y: full.size.height / 1024)),
                          operation: .sourceOver, fraction: 1)
                return true
            }
        } else if let host = l.url.flatMap({ URL(string: $0)?.host }) {
            img = NSImage(contentsOf: tilesDir.appendingPathComponent(host + ".png"))
        }
        img?.size = iconSize
        return img ?? symbol("globe", nil)
    }

    // Re-arm on rename/delete because editors save by replacing the file
    func watchLinks() {
        watcher?.cancel()
        let fd = open(linksFile.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            self?.buildMenu()
            if src.data.contains(.rename) || src.data.contains(.delete) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.buildMenu(); self?.watchLinks() }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    @objc func openLink(_ sender: NSMenuItem) {
        guard links.indices.contains(sender.tag) else { return }
        let l = links[sender.tag]
        let cfg = NSWorkspace.OpenConfiguration()
        if let app = l.app {
            // Only plain app names from /Applications, nothing path-like
            guard !app.contains("/"), !app.contains("..") else { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/\(app).app"), configuration: cfg)
            return
        }
        // Only web links, and only real Chrome profile folder names, ever reach Chrome's command line
        guard let raw = l.url, let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return }
        let profile = l.profile ?? "Default"
        guard profile.range(of: #"^(Default|Profile \d+)$"#, options: .regularExpression) != nil else { return }
        // A fresh Chrome instance hands the URL to the running one in the chosen profile, like `open -na`
        cfg.createsNewApplicationInstance = true
        cfg.arguments = ["--profile-directory=\(profile)", url.absoluteString]
        NSWorkspace.shared.openApplication(at: chromeURL, configuration: cfg)
    }

    @objc func editLinks() { NSWorkspace.shared.open(linksFile) }

    @objc func openSettings() { SettingsWindow.show(.accounts) }

    // Hide every visible app (windows and tabs stay exactly as they were), click again to unhide the same ones.
    // Goes through System Events because macOS blocks one app from unhiding/activating another directly.
    @objc func toggleDesktop() {
        if !hiddenApps.isEmpty {
            var s = "tell application \"System Events\"\n"
            for n in hiddenApps { s += "try\nset visible of process \"\(esc(n))\" to true\nend try\n" }
            if let f = frontApp { s += "try\nset frontmost of process \"\(esc(f))\" to true\nend try\n" }
            run(s + "end tell")
            hiddenApps = []; frontApp = nil
            desktopItem.button?.image = showIcon
            desktopItem.button?.toolTip = "Show Desktop"
            return
        }
        // Focus Finder first: macOS won't hide the app that's currently in front
        let out = run("""
        tell application "System Events"
        set fr to name of first process whose frontmost is true
        set ps to every process whose visible is true and background only is false and name is not "Finder" and name is not "UMST"
        set frontmost of process "Finder" to true
        set out to fr
        repeat with p in ps
        set out to out & linefeed & (name of p)
        set visible of p to false
        end repeat
        return out
        end tell
        """)
        guard let lines = out?.components(separatedBy: "\n"), lines.count > 1 else { return }
        frontApp = lines[0]
        hiddenApps = Array(lines.dropFirst())
        desktopItem.button?.image = restoreIcon
        desktopItem.button?.toolTip = "Bring Windows Back"
    }

    func esc(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

    @discardableResult func run(_ source: String) -> String? {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { NSLog("UMST: Show Desktop script failed (%@)", "\(err[NSAppleScript.errorNumber] ?? "?")") }
        return r?.stringValue
    }
}

func symbol(_ name: String, _ desc: String?) -> NSImage? {
    let img = NSImage(systemSymbolName: name, accessibilityDescription: desc)
    img?.isTemplate = true
    return img
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
