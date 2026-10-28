import Foundation

/// Minimal iCalendar (RFC 5545) reader: VEVENT with SUMMARY, DTSTART, DTEND, UID, RECURRENCE-ID and common RRULEs.
enum ICS {
    struct Ev {
        var uid = "", title = "", start = Date(), end: Date?, allDay = false, cancelled = false
        var exdates: Set<Date> = [], rrule: String?, recurrenceID: Date?
    }

    static func parse(_ text: String, from: Date, to: Date) -> [Ev] {
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "").replacingOccurrences(of: "\n\t", with: "")
        var raw: [Ev] = [], cur: Ev?, hasStart = false, nested = 0
        for l in unfolded.split(whereSeparator: \.isNewline) {
            let line = String(l), upper = line.uppercased()
            if upper == "BEGIN:VEVENT" { cur = Ev(); hasStart = false; nested = 0; continue }
            guard cur != nil else { continue }
            // Skip components inside an event (VALARM has its own SUMMARY, DESCRIPTION, …)
            if upper.hasPrefix("BEGIN:") { nested += 1; continue }
            if nested > 0 { if upper.hasPrefix("END:") { nested -= 1 }; continue }
            if upper == "END:VEVENT" {
                if let e = cur, hasStart { raw.append(e) }
                cur = nil; continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon], value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";"), key = parts.first.map { $0.uppercased() } ?? ""
            let tzid = parts.first { $0.uppercased().hasPrefix("TZID=") }
                .map { String($0.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            switch key {
            case "UID": cur!.uid = value
            case "SUMMARY": cur!.title = unescape(value)
            case "DTSTART": if let (d, all) = date(value, tzid) { cur!.start = d; cur!.allDay = all; hasStart = true }
            case "DTEND": cur!.end = date(value, tzid)?.0
            case "RRULE": cur!.rrule = value.uppercased()
            case "RECURRENCE-ID": cur!.recurrenceID = date(value, tzid)?.0
            case "STATUS": cur!.cancelled = value.uppercased() == "CANCELLED"
            case "EXDATE":
                for v in value.split(separator: ",") { if let (d, _) = date(String(v), tzid) { cur!.exdates.insert(d) } }
            default: break
            }
        }

        // A moved or cancelled single occurrence replaces that occurrence of its series
        var overridden: [String: Set<Date>] = [:]
        for e in raw { if let r = e.recurrenceID { overridden[e.uid, default: []].insert(r) } }

        var out: [Ev] = []
        for e in raw where !e.cancelled {
            if let r = e.rrule, e.recurrenceID == nil {
                let skip = e.exdates.union(overridden[e.uid] ?? [])
                for (s, en) in expand(e.start, e.end, r, from: from, to: to) where !skip.contains(s) {
                    var x = e; x.start = s; x.end = en; out.append(x)
                }
            } else if (e.end ?? e.start) >= from && e.start <= to {
                out.append(e)
            }
        }
        return out
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\\\", with: "\u{0}").replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\N", with: " ").replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\u{0}", with: "\\")
    }

    // Outlook and Exchange feeds use Windows time zone names
    static let windowsZones = [
        "Eastern Standard Time": "America/New_York", "Central Standard Time": "America/Chicago",
        "Mountain Standard Time": "America/Denver", "US Mountain Standard Time": "America/Phoenix",
        "Pacific Standard Time": "America/Los_Angeles", "Alaskan Standard Time": "America/Anchorage",
        "Hawaiian Standard Time": "Pacific/Honolulu", "Atlantic Standard Time": "America/Halifax",
        "Newfoundland Standard Time": "America/St_Johns", "SA Pacific Standard Time": "America/Bogota",
        "E. South America Standard Time": "America/Sao_Paulo", "GMT Standard Time": "Europe/London",
        "Greenwich Standard Time": "Atlantic/Reykjavik", "W. Europe Standard Time": "Europe/Berlin",
        "Romance Standard Time": "Europe/Paris", "Central Europe Standard Time": "Europe/Budapest",
        "Central European Standard Time": "Europe/Warsaw", "E. Europe Standard Time": "Europe/Chisinau",
        "FLE Standard Time": "Europe/Kiev", "GTB Standard Time": "Europe/Bucharest",
        "Russian Standard Time": "Europe/Moscow", "Israel Standard Time": "Asia/Jerusalem",
        "Arabian Standard Time": "Asia/Dubai", "India Standard Time": "Asia/Kolkata",
        "China Standard Time": "Asia/Shanghai", "Singapore Standard Time": "Asia/Singapore",
        "Taipei Standard Time": "Asia/Taipei", "Tokyo Standard Time": "Asia/Tokyo",
        "Korea Standard Time": "Asia/Seoul", "AUS Eastern Standard Time": "Australia/Sydney",
        "E. Australia Standard Time": "Australia/Brisbane", "New Zealand Standard Time": "Pacific/Auckland",
        "UTC": "UTC", "Coordinated Universal Time": "UTC",
    ]

    static func zone(_ tzid: String?) -> TimeZone? {
        guard let t = tzid, !t.isEmpty else { return nil }
        if let z = TimeZone(identifier: t) ?? windowsZones[t].flatMap(TimeZone.init(identifier:)) { return z }
        // Prefixed IDs such as "/mozilla.org/20050126_1/America/New_York"
        let parts = t.split(separator: "/")
        return parts.count >= 2 ? TimeZone(identifier: parts.suffix(2).joined(separator: "/")) : nil
    }

    static func date(_ v: String, _ tzid: String?) -> (Date, Bool)? {
        let d = Array(v.utf8).filter { $0 >= 48 && $0 <= 57 }.map { Int($0) - 48 }
        func num(_ a: Int, _ n: Int) -> Int { d[a..<a + n].reduce(0) { $0 * 10 + $1 } }
        guard d.count >= 8 else { return nil }
        var c = DateComponents(year: num(0, 4), month: num(4, 2), day: num(6, 2))
        if d.count < 14 {
            return Calendar.current.date(from: c).map { ($0, true) }
        }
        c.hour = num(8, 2); c.minute = num(10, 2); c.second = num(12, 2)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = v.hasSuffix("Z") ? TimeZone(identifier: "UTC")! : (zone(tzid) ?? .current)
        return cal.date(from: c).map { ($0, false) }
    }

    static let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    static func expand(_ start: Date, _ end: Date?, _ rule: String, from: Date, to: Date) -> [(Date, Date?)] {
        var p: [String: String] = [:]
        for part in rule.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { p[String(kv[0])] = String(kv[1]) }
        }
        let comp: Calendar.Component
        switch p["FREQ"] {
        case "DAILY": comp = .day
        case "WEEKLY": comp = .weekOfYear
        case "MONTHLY": comp = .month
        case "YEARLY": comp = .year
        default: return [(start, end)]
        }
        let cal = Calendar.current
        let interval = max(1, Int(p["INTERVAL"] ?? "1") ?? 1)
        let count = p["COUNT"].flatMap { Int($0) }
        let until = p["UNTIL"].flatMap { date($0, nil)?.0 }
        let dur = end.map { $0.timeIntervalSince(start) }
        // BYDAY entries: weekday with an optional ordinal ("TU", "2TU", "-1FR")
        let byday: [(Int?, Int)]? = p["BYDAY"]?.split(separator: ",").compactMap { s in
            guard let wd = weekdays[String(s.suffix(2))] else { return nil }
            let n = s.dropLast(2)
            return (n.isEmpty ? nil : Int(n), wd)
        }
        let bymonthday = p["BYMONTHDAY"]?.split(separator: ",").compactMap { Int($0) }
        let startDay = cal.component(.day, from: start)

        // Without COUNT we can jump straight to the window instead of walking from the first occurrence
        var i = 0
        if count == nil, let gap = cal.dateComponents([comp], from: start, to: from).value(for: comp), gap > 1 {
            i = gap / interval - 1
        }
        var n = 0, steps = 0, out: [(Date, Date?)] = []
        while steps < 5000 {
            steps += 1
            guard let base = cal.date(byAdding: comp, value: i * interval, to: start) else { break }
            if base > to { break }
            let wd = cal.component(.weekday, from: base)
            var cands: [Date]
            switch comp {
            case .weekOfYear where byday != nil:
                cands = byday!.map(\.1).sorted().compactMap { cal.date(byAdding: .day, value: $0 - wd, to: base) }
            case .day where byday != nil:
                cands = byday!.contains { $0.1 == wd } ? [base] : []
            case .month where byday != nil || bymonthday != nil:
                cands = monthDays(base, byday ?? [], bymonthday ?? [], cal).sorted()
            case .month:
                // The 31st only happens in months that have one
                cands = cal.component(.day, from: base) == startDay ? [base] : []
            default:
                cands = [base]
            }
            for c in cands where c >= start {
                if let u = until, c > u { return out }
                n += 1
                if let k = count, n > k { return out }
                let e = dur.map { c.addingTimeInterval($0) }
                if (e ?? c) >= from && c <= to { out.append((c, e)) }
            }
            i += 1
        }
        return out
    }

    /// Days in `base`'s month matching BYDAY / BYMONTHDAY, at `base`'s time of day.
    static func monthDays(_ base: Date, _ byday: [(Int?, Int)], _ bymonthday: [Int], _ cal: Calendar) -> [Date] {
        guard let days = cal.range(of: .day, in: .month, for: base)?.count,
              let first = cal.date(byAdding: .day, value: 1 - cal.component(.day, from: base), to: base) else { return [] }
        func day(_ k: Int) -> Date? { cal.date(byAdding: .day, value: k - 1, to: first) }
        var out: [Date] = []
        for md in bymonthday {
            let k = md > 0 ? md : days + md + 1
            if (1...days).contains(k), let d = day(k) { out.append(d) }
        }
        for (ord, wd) in byday {
            let matches = (1...days).compactMap(day).filter { cal.component(.weekday, from: $0) == wd }
            if let o = ord {
                let idx = o > 0 ? o - 1 : matches.count + o
                if matches.indices.contains(idx) { out.append(matches[idx]) }
            } else {
                out += matches
            }
        }
        return out
    }
}
