import Foundation

/// Minimal iCalendar (RFC 5545) reader: VEVENT with SUMMARY, DTSTART, DTEND, UID and common RRULEs.
enum ICS {
    struct Ev { var uid = "", title = "", start = Date(), end: Date?, allDay = false }

    static func parse(_ text: String, from: Date, to: Date) -> [Ev] {
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n ", with: "")
        var out: [Ev] = [], cur: Ev?, rrule: String?, hasStart = false
        for raw in unfolded.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            if line == "BEGIN:VEVENT" { cur = Ev(); rrule = nil; hasStart = false; continue }
            if line == "END:VEVENT" {
                if let e = cur, hasStart {
                    if let r = rrule {
                        for (s, en) in expand(e.start, e.end, r, from: from, to: to) {
                            var x = e; x.start = s; x.end = en; out.append(x)
                        }
                    } else if (e.end ?? e.start) >= from && e.start <= to { out.append(e) }
                }
                cur = nil; continue
            }
            guard cur != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon], value = String(line[line.index(after: colon)...])
            let parts = head.split(separator: ";"), key = parts.first.map(String.init) ?? ""
            let tzid = parts.first { $0.hasPrefix("TZID=") }.map { String($0.dropFirst(5)) }
            switch key {
            case "UID": cur!.uid = value
            case "SUMMARY": cur!.title = unescape(value)
            case "DTSTART": if let (d, all) = date(value, tzid) { cur!.start = d; cur!.allDay = all; hasStart = true }
            case "DTEND": cur!.end = date(value, tzid)?.0
            case "RRULE": rrule = value
            default: break
            }
        }
        return out
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
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
        cal.timeZone = v.hasSuffix("Z") ? TimeZone(identifier: "UTC")! : (tzid.flatMap(TimeZone.init(identifier:)) ?? .current)
        return cal.date(from: c).map { ($0, false) }
    }

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
        let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
        let byday = comp == .weekOfYear ? p["BYDAY"]?.split(separator: ",").compactMap { weekdays[String($0.suffix(2))] } : nil
        // Without COUNT we can jump straight to the window instead of walking from the first occurrence
        var i = 0
        if count == nil, let gap = cal.dateComponents([comp], from: start, to: from).value(for: comp), gap > 1 {
            i = gap / interval - 1
        }
        var n = 0, out: [(Date, Date?)] = []
        while i < 5000 {
            guard let base = cal.date(byAdding: comp, value: i * interval, to: start) else { break }
            if base > to { break }
            let wd = cal.component(.weekday, from: base)
            let cands = byday.map { $0.sorted().compactMap { cal.date(byAdding: .day, value: $0 - wd, to: base) } } ?? [base]
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
}
