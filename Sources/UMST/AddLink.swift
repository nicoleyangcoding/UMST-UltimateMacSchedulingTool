import AppKit
import SwiftUI

// "Add Link…" box. A web address is added on the spot; anything else (e.g. "Notion")
// is saved to requests.json as a pending request to be filled in later.

let requestsFile = supportDir.appendingPathComponent("requests.json")
let linkGroups = ["Personal", "School", "Work"]

struct LinkRequest: Codable { var group: String; var text: String; var added: Date }

enum LinkAdder {
    static func pending() -> [LinkRequest] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: requestsFile)).flatMap { try? dec.decode([LinkRequest].self, from: $0) } ?? []
    }

    /// Returns true if the link was added immediately, false if it was saved as a request.
    @discardableResult
    static func submit(_ raw: String, group: String) -> Bool {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        if let url = webAddress(text) {
            addNow(url, group: group)
            return true
        }
        var q = pending()
        q.append(LinkRequest(group: group, text: text, added: Date()))
        let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted; enc.dateEncodingStrategy = .iso8601
        if let d = try? enc.encode(q) { Safe.write(d, to: requestsFile) }
        return false
    }

    /// "notion.so" or "https://x.com/home" → URL. Plain words → nil. Only https is accepted.
    static func webAddress(_ s: String) -> URL? {
        guard !s.contains(" "), s.contains(".") else { return nil }
        return Safe.httpsURL(s.lowercased().hasPrefix("https://") ? s : "https://" + s.replacingOccurrences(of: "http://", with: ""))
    }

    static func addNow(_ url: URL, group: String) {
        var groups = (try? Data(contentsOf: linksFile))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        if !groups.contains(where: { $0["group"] as? String == group }) { groups.append(["group": group, "items": []]) }
        let gi = groups.firstIndex { $0["group"] as? String == group }!
        var items = groups[gi]["items"] as? [[String: Any]] ?? []
        // Use the Chrome profile this group already uses most; none means the default browser
        let profiles = items.compactMap { $0["profile"] as? String }
        let profile = Dictionary(grouping: profiles, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        let account = items.first { $0["profile"] as? String == profile }?["account"] as? String
        let host = url.host!
        let parts = host.replacingOccurrences(of: "www.", with: "").split(separator: ".")
        let base = parts.count >= 2 ? parts[parts.count - 2] : parts.first ?? Substring(host)
        var item: [String: Any] = ["name": base.prefix(1).uppercased() + base.dropFirst(), "url": url.absoluteString]
        if let profile { item["profile"] = profile }
        if let account { item["account"] = account }
        items.append(item)
        groups[gi]["items"] = items
        if let data = try? JSONSerialization.data(withJSONObject: groups, options: [.prettyPrinted, .withoutEscapingSlashes]) {
            Safe.write(data, to: linksFile)
        }
        Task.detached(priority: .utility) {
            await fetchIcon(host: host)
            // Desktop launchers are opt-in: only rebuild them if the user has generated them before
            let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/\(group)")
            runTool(FileManager.default.fileExists(atPath: desktop.path) ? "make_folders.py" : "make_icons")
            await MainActor.run { (NSApp.delegate as? AppDelegate)?.buildMenu() }
        }
    }

    static func fetchIcon(host: String) async {
        let dest = supportDir.appendingPathComponent("icons/\(host).png")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        for s in ["https://\(host)/apple-touch-icon.png", "https://www.google.com/s2/favicons?domain=\(host)&sz=256"] {
            guard let u = URL(string: s), let d = try? await Safe.fetch(URLRequest(url: u)),
                  d.count < 2_000_000, let img = NSImage(data: d), img.size.width >= 16 else { continue }
            Safe.write(d, to: dest)
            return
        }
    }

    /// Runs a helper bundled in the app's Resources folder.
    static func runTool(_ name: String) {
        guard let path = Bundle.main.path(forResource: name, ofType: nil) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: name.hasSuffix(".py") ? "/usr/bin/python3" : path)
        p.arguments = name.hasSuffix(".py") ? [path] : []
        try? p.run()
        p.waitUntilExit()
    }
}

struct AddLinkView: View {
    let close: () -> Void
    @ObservedObject var settings = AppSettings.shared
    @State private var group = "Personal"
    @State private var text = ""
    @State private var note: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $group) {
                ForEach(linkGroups, id: \.self) { Text($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            TextField("Website or app name…", text: $text)
                .textFieldStyle(.plain).font(.system(size: 14))
                .focused($focused)
                .onSubmit(submit)
            Text(note ?? "Paste a link to add it now, or type a name to save it as a request.")
                .font(.system(size: 10.5)).foregroundStyle(note == nil ? .secondary : settings.theme.accent)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .padding(12)
        .frame(width: 280)
        .tint(settings.theme.accent)
        .onAppear { text = ""; note = nil; DispatchQueue.main.async { focused = true } }
        .onExitCommand(perform: close)
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { close(); return }
        let now = LinkAdder.submit(text, group: group)
        (NSApp.delegate as? AppDelegate)?.buildMenu()
        withAnimation(settings.anim()) { note = now ? "Added to \(group) ✓" : "Saved as a pending request ✓" }
        text = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: close)
    }
}
