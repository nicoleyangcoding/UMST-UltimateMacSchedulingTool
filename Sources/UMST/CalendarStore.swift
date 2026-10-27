import AppKit
import EventKit

struct CalEvent: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date?
    var allDay: Bool
    var source: String
    var color: String
    var local = false
}

/// A calendar source. Secrets (feed links, tokens) are kept in the Keychain under the source's id.
///   apple  – every calendar in macOS Calendar (Google, iCloud, Exchange, events found in Mail)
///   ics    – any iCalendar feed (Canvas, Google secret address, Outlook, …)
///   canvas – Canvas planner API: `baseURL` + token
struct Source: Codable, Identifiable {
    var id = UUID().uuidString
    var name: String
    var type: String
    var host: String?            // shown in Settings; not secret
    var baseURL: String?         // canvas only
    var color: String?
    // Pre-Keychain fields, migrated on load
    var url: String?
    var token: String?

    init(name: String, type: String, host: String? = nil, color: String? = nil) {
        self.name = name; self.type = type; self.host = host; self.color = color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(String.self, forKey: .type)
        host = try c.decodeIfPresent(String.self, forKey: .host)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        token = try c.decodeIfPresent(String.self, forKey: .token)
    }
}

struct LocalItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var day: Date
}

struct DeviceCalendar: Identifiable {
    let id: String
    let title: String
    let account: String
    let color: String
}

enum FeedError: LocalizedError {
    case badLink, notCalendar, unreachable
    var errorDescription: String? {
        switch self {
        case .badLink: "Use a secure link that starts with https:// or webcal://"
        case .notCalendar: "That link doesn't look like a calendar feed."
        case .unreachable: "Couldn't connect. Check the link or token and try again."
        }
    }
}

let calDir = supportDir.appendingPathComponent("calendar")
let palette = ["#E2412D", "#0A84FF", "#30A46C", "#AF52DE", "#FF9F0A", "#FF375F", "#64D2FF"]
let daysAhead = 14

@MainActor
final class CalendarStore: ObservableObject {
    static let shared = CalendarStore()

    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var refreshing = false
    @Published fileprivate(set) var lastRefresh: Date?
    @Published private(set) var problem: String?
    @Published fileprivate(set) var calendarAccess = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var today = Calendar.current.startOfDay(for: Date())
    @Published fileprivate(set) var sources: [Source] = []

    var needsCalendarAccess: Bool { calendarAccess != .fullAccess }
    var isSetUp: Bool { !needsCalendarAccess || sources.contains { $0.type != "apple" } }

    fileprivate var items: [LocalItem] = []
    fileprivate var remote: [CalEvent] = []
    private let ek = EKEventStore()
    private var midnightTimer: Timer?
    private var refreshAgain = false

    private let sourcesFile = calDir.appendingPathComponent("sources.json")
    private let itemsFile = calDir.appendingPathComponent("items.json")
    private let cacheFile = calDir.appendingPathComponent("cache.json")

    func start() {
        if isDemo { startDemo(); return }
        try? FileManager.default.createDirectory(at: calDir, withIntermediateDirectories: true)
        Safe.lockDown(supportDir, directory: true)
        Safe.lockDown(calDir, directory: true)
        if FileManager.default.fileExists(atPath: sourcesFile.path) {
            guard loadSources() else {
                problem = "Couldn't read your saved calendars"   // leave the file untouched
                return
            }
        } else {
            sources = [Source(name: "Mac Calendars", type: "apple")]
            saveSources()
        }
        items = load([LocalItem].self, itemsFile) ?? []
        remote = load([CalEvent].self, cacheFile) ?? []
        lastRefresh = (try? cacheFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        purgeExpired()
        merge()
        scheduleMidnight()

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in self.dayRolledIfNeeded(); self.refreshIfStale(hours: 4) }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: ek, queue: .main) { _ in
            Task { @MainActor in self.refresh() }
        }
        refresh()
        if calendarAccess == .notDetermined { requestCalendarAccess() }
    }

    // MARK: Quick-add items

    func add(_ title: String, on day: Date) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items.append(LocalItem(title: String(t.prefix(200)), day: Calendar.current.startOfDay(for: day)))
        save(items, itemsFile)
        merge()
    }

    func complete(_ e: CalEvent) {
        items.removeAll { $0.id.uuidString == e.id }
        save(items, itemsFile)
        merge()
    }

    private func purgeExpired() {
        let n = items.count
        items.removeAll { $0.day < today }
        if items.count != n { save(items, itemsFile) }
    }

    private func scheduleMidnight() {
        midnightTimer?.invalidate()
        let next = Calendar.current.date(byAdding: .day, value: 1, to: today)!.addingTimeInterval(5)
        let t = Timer(fire: next, interval: 0, repeats: false) { _ in
            Task { @MainActor in self.dayRolledIfNeeded(); self.refresh() }
        }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        midnightTimer = t
    }

    private func dayRolledIfNeeded() {
        let d = Calendar.current.startOfDay(for: Date())
        guard d != today else { return }
        today = d
        purgeExpired()
        merge()
        scheduleMidnight()
    }

    // MARK: Sources

    @discardableResult
    private func loadSources() -> Bool {
        guard let loaded = load([Source].self, sourcesFile) else { return false }
        sources = loaded
        // Move any secret that was stored in the file into the Keychain
        var migrated = false
        for i in sources.indices {
            if let u = sources[i].url {
                if sources[i].type == "canvas" {
                    sources[i].baseURL = u
                } else {
                    Keychain.set(u, for: sources[i].id + ".url")
                }
                sources[i].host = Safe.httpsURL(u)?.host
                sources[i].url = nil
                migrated = true
            }
            if let t = sources[i].token {
                Keychain.set(t, for: sources[i].id + ".token")
                sources[i].token = nil
                migrated = true
            }
        }
        if migrated { saveSources() }
        return true
    }

    private func saveSources() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let d = try? enc.encode(sources) { Safe.write(d, to: sourcesFile) }
    }

    /// Validates and test-connects before anything is saved.
    func addFeed(name: String, link: String, token: String?) async throws {
        guard let url = Safe.httpsURL(link) else { throw FeedError.badLink }
        let tok = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        var s = Source(name: trimmed.isEmpty ? (url.host ?? "Calendar") : trimmed,
                       type: tok?.isEmpty == false ? "canvas" : "ics", host: url.host,
                       color: palette[sources.count % palette.count])
        if s.type == "canvas" {
            s.baseURL = "https://" + url.host!
            _ = try await fetchCanvas(base: s.baseURL!, token: tok!, name: s.name, color: "", from: today, to: today.addingTimeInterval(86400))
            Keychain.set(tok!, for: s.id + ".token")
        } else {
            let data = try await Safe.fetch(URLRequest(url: url))
            guard String(decoding: data.prefix(2048), as: UTF8.self).contains("BEGIN:VCALENDAR") else { throw FeedError.notCalendar }
            Keychain.set(url.absoluteString, for: s.id + ".url")
        }
        sources.append(s)
        saveSources()
        refresh()
    }

    func removeSource(_ s: Source) {
        Keychain.delete(s.id + ".url")
        Keychain.delete(s.id + ".token")
        sources.removeAll { $0.id == s.id }
        saveSources()
        refresh()
    }

    func deviceCalendars() -> [DeviceCalendar] {
        if isDemo { return Demo.calendars }
        guard !needsCalendarAccess else { return [] }
        return ek.calendars(for: .event)
            .map { DeviceCalendar(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, color: hex($0.color)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    func requestCalendarAccess() {
        Task {
            _ = try? await ek.requestFullAccessToEvents()
            calendarAccess = EKEventStore.authorizationStatus(for: .event)
            if needsCalendarAccess, let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(u)
            }
            refresh()
        }
    }

    // MARK: Refresh

    func refreshIfStale(hours: Double) {
        if let l = lastRefresh, Date().timeIntervalSince(l) < hours * 3600 { return }
        refresh()
    }

    func refresh() {
        guard !isDemo else { return }
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        let srcs = sources
        let hidden = AppSettings.shared.hiddenCalendars
        let from = today, to = Calendar.current.date(byAdding: .day, value: daysAhead, to: today)!
        Task {
            var all: [CalEvent] = [], failed: [String] = []
            await withTaskGroup(of: (String, [CalEvent]?).self) { g in
                for (i, s) in srcs.enumerated() {
                    let color = s.color ?? palette[i % palette.count]
                    g.addTask {
                        // Read off the main thread: the Keychain may ask the user for permission
                        let secret = s.type == "apple" ? nil : Keychain.get(s.id + (s.type == "canvas" ? ".token" : ".url"))
                        return (s.name, try? await self.fetch(s, secret: secret, hidden: hidden, color: color, from: from, to: to))
                    }
                }
                for await (name, r) in g {
                    if let r { all += r } else { failed.append(name) }
                }
            }
            remote = all
            save(all, cacheFile)
            lastRefresh = Date()
            problem = failed.isEmpty ? nil : "Couldn't reach " + failed.sorted().joined(separator: ", ")
            refreshing = false
            merge()
            if refreshAgain { refreshAgain = false; refresh() }
        }
    }

    nonisolated private func fetch(_ s: Source, secret: String?, hidden: Set<String>, color: String, from: Date, to: Date) async throws -> [CalEvent] {
        switch s.type {
        case "apple":
            return await fetchApple(hidden: hidden, from: from, to: to)
        case "ics":
            guard let u = secret.flatMap(Safe.httpsURL) else { throw FeedError.badLink }
            let data = try await Safe.fetch(URLRequest(url: u))
            return ICS.parse(String(decoding: data, as: UTF8.self), from: from, to: to).map {
                CalEvent(id: "ics:\(s.id):\($0.uid):\($0.start.timeIntervalSince1970)", title: $0.title, start: $0.start,
                         end: $0.end, allDay: $0.allDay, source: s.name, color: color)
            }
        case "canvas":
            guard let base = s.baseURL, let token = secret else { throw FeedError.badLink }
            return try await fetchCanvas(base: base, token: token, name: s.name, color: color, from: from, to: to)
        default:
            return []
        }
    }

    nonisolated private func fetchApple(hidden: Set<String>, from: Date, to: Date) async -> [CalEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let store = await ek
        let cals = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: cals)).map {
            CalEvent(id: "ek:\($0.eventIdentifier ?? UUID().uuidString):\($0.startDate.timeIntervalSince1970)",
                     title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay,
                     source: $0.calendar.title, color: hex($0.calendar.color))
        }
    }

    nonisolated private func fetchCanvas(base: String, token: String, name: String, color: String, from: Date, to: Date) async throws -> [CalEvent] {
        guard let root = Safe.httpsURL(base), var c = URLComponents(url: root, resolvingAgainstBaseURL: false) else { throw FeedError.badLink }
        let iso = ISO8601DateFormatter()
        c.path = "/api/v1/planner/items"
        c.queryItems = [.init(name: "start_date", value: iso.string(from: from)),
                        .init(name: "end_date", value: iso.string(from: to)),
                        .init(name: "per_page", value: "100")]
        var req = URLRequest(url: c.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let data = try? await Safe.fetch(req),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw FeedError.unreachable }
        return arr.compactMap { it in
            guard let p = it["plannable"] as? [String: Any], let title = p["title"] as? String,
                  let ds = it["plannable_date"] as? String, let d = iso.date(from: ds) else { return nil }
            return CalEvent(id: "canvas:\(it["plannable_id"] ?? title):\(ds)", title: title, start: d, end: nil,
                            allDay: false, source: (it["context_name"] as? String) ?? name, color: color)
        }
    }

    // MARK: Merge

    fileprivate func merge() {
        let local = items.map {
            CalEvent(id: $0.id.uuidString, title: $0.title, start: $0.day, end: nil, allDay: true,
                     source: "To-do", color: "#8E8E93", local: true)
        }
        // The same event from two sources (e.g. Canvas feed also subscribed in Calendar) shows once
        var seen = Set<String>()
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: today)!
        events = (local + remote)
            .filter { ($0.end ?? $0.start) >= today && $0.start < end }
            .filter { seen.insert($0.title.lowercased() + "\(Int($0.start.timeIntervalSince1970 / 60))").inserted }
            .sorted { ($0.local ? 0 : 1, $0.allDay ? 0 : 1, $0.start) < ($1.local ? 0 : 1, $1.allDay ? 0 : 1, $1.start) }
    }

    func events(on day: Date) -> [CalEvent] {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        return events.filter { e in
            if e.local { return e.start == day }
            if e.allDay { return e.start < next && (e.end ?? next) > day }
            // Late-night events that spill a little past midnight stay on their own day
            return (e.start >= day && e.start < next) || (e.start < day && (e.end ?? e.start) > day.addingTimeInterval(3 * 3600))
        }
    }

    // MARK: Disk

    private func load<T: Decodable>(_ t: T.Type, _ url: URL) -> T? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func save<T: Encodable>(_ v: T, _ url: URL) {
        guard !isDemo else { return }
        if let d = try? JSONEncoder().encode(v) { Safe.write(d, to: url) }
    }
}

// MARK: Demo mode (`UMST --demo`): sample data for screenshots; reads and writes nothing

let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")

extension CalendarStore {
    fileprivate func startDemo() {
        sources = [Source(name: "Mac Calendars", type: "apple"),
                   Source(name: "Canvas", type: "ics", host: "canvas.example.edu", color: "#E2412D")]
        calendarAccess = .fullAccess
        items = [LocalItem(title: "Pick up dry cleaning", day: today), LocalItem(title: "Call Mom", day: today)]
        remote = Demo.events(today)
        lastRefresh = Date()
        merge()
    }
}

enum Demo {
    static let calendars = [
        DeviceCalendar(id: "1", title: "Personal", account: "Gmail", color: "#0A84FF"),
        DeviceCalendar(id: "2", title: "Work", account: "Gmail", color: "#30A46C"),
        DeviceCalendar(id: "3", title: "Holidays", account: "iCloud", color: "#AF52DE"),
    ]

    static func events(_ today: Date) -> [CalEvent] {
        let c = Calendar.current
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
            c.date(bySettingHour: h, minute: m, second: 0, of: c.date(byAdding: .day, value: day, to: today)!)!
        }
        let list: [(String, Date, Bool, String, String)] = [
            ("Team standup", at(0, 9, 30), false, "Work", "#30A46C"),
            ("Organic Chemistry lecture", at(0, 11), false, "Canvas", "#E2412D"),
            ("Lunch with Sam", at(0, 12, 30), false, "Personal", "#0A84FF"),
            ("Problem Set 6 due", at(0, 23, 59), false, "Canvas", "#E2412D"),
            ("Design review (Zoom)", at(1, 14), false, "Work", "#30A46C"),
            ("Lab report due", at(1, 23, 59), false, "Canvas", "#E2412D"),
            ("Dentist", at(2, 10), false, "Personal", "#0A84FF"),
            ("Midterm exam", at(3, 0), true, "Canvas", "#E2412D"),
            ("Halloween", at(4, 0), true, "Holidays", "#AF52DE"),
            ("1:1 with manager", at(6, 15), false, "Work", "#30A46C"),
        ]
        return list.enumerated().map { i, e in
            CalEvent(id: "demo\(i)", title: e.0, start: e.1, end: e.2 ? c.date(byAdding: .day, value: 1, to: e.1) : e.1.addingTimeInterval(3600),
                     allDay: e.2, source: e.3, color: e.4)
        }
    }
}

func hex(_ c: NSColor?) -> String {
    guard let c = c?.usingColorSpace(.sRGB) else { return "#8E8E93" }
    return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
}
