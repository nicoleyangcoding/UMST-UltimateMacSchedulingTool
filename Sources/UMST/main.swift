import AppKit
import ServiceManagement
import SwiftUI

let supportDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/UMST")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let addItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let addPopover = NSPopover()
    let menu = NSMenu()
    var widget: CalendarWidgetController?

    func applicationDidFinishLaunching(_ n: Notification) {
        // One copy at a time (login item + manual launch shouldn't double up)
        let me = NSRunningApplication.current
        if !isDemo, NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains(where: { $0 != me && !$0.isTerminated }) {
            NSApp.terminate(nil)
            return
        }
        if !isDemo { AppSettings.shared.applyLoginItem() }

        // Click: quick add. Right-click (or Control-click): settings, refresh, quit.
        addItem.button?.image = symbol("calendar.badge.plus", "UMST")
        addItem.button?.toolTip = "Add to Calendar"
        addItem.button?.target = self
        addItem.button?.action = #selector(statusClicked)
        addItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        buildMenu()

        addPopover.behavior = .transient
        addPopover.contentViewController = NSHostingController(rootView: QuickAddView { [weak self] in
            self?.addPopover.performClose(nil)
        })
        CalendarStore.shared.start()
        widget = CalendarWidgetController { [weak self] in self?.toggleQuickAdd() }
        if let dir = Snapshot.directory, let w = widget?.window { Snapshot.run(widget: w, to: dir) }
    }

    func buildMenu() {
        func item(_ title: String, _ sel: Selector, _ icon: String, _ key: String = "") -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
            mi.target = self
            mi.image = symbol(icon, nil)
            return mi
        }
        menu.addItem(item("Add to Calendar…", #selector(quickAddFromMenu), "plus", "n"))
        menu.addItem(item("Refresh", #selector(refresh), "arrow.clockwise", "r"))
        menu.addItem(.separator())
        menu.addItem(item("Accounts…", #selector(openAccounts), "person.crop.circle", ","))
        menu.addItem(item("Appearance…", #selector(openAppearance), "paintpalette"))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit UMST", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q")
        quit.image = symbol("power", nil)
        menu.addItem(quit)
    }

    @objc func statusClicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            addItem.menu = menu
            addItem.button?.performClick(nil)
            addItem.menu = nil   // so a normal click opens quick add again
        } else {
            toggleQuickAdd()
        }
    }

    // A transient popover opened while the menu is still closing would dismiss itself
    @objc func quickAddFromMenu() { DispatchQueue.main.async { self.toggleQuickAdd() } }

    @objc func toggleQuickAdd() {
        if addPopover.isShown { addPopover.performClose(nil); return }
        guard let b = addItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)   // so typing goes straight into the box
        addPopover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
    }

    @objc func refresh() { CalendarStore.shared.refresh() }
    @objc func openAccounts() { SettingsWindow.show(.accounts) }
    @objc func openAppearance() { SettingsWindow.show(.appearance) }
}

func symbol(_ name: String, _ desc: String?) -> NSImage? {
    let img = NSImage(systemSymbolName: name, accessibilityDescription: desc)
    img?.isTemplate = true
    return img
}

// Used by the uninstaller so no stale Login Items entry is left behind
if CommandLine.arguments.contains("--unregister-login") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
