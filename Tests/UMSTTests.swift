import Foundation

// Lightweight test runner (no Xcode required). Built and run by scripts/test.sh.

var failures = 0
var passed = 0

func expect(_ cond: @autoclosure () -> Bool, _ name: String, file: StaticString = #file, line: UInt = #line) {
    if cond() { passed += 1 } else { failures += 1; print("FAIL \(name) (line \(line))") }
}

let cal = Calendar.current
let today = cal.startOfDay(for: Date())
let window = cal.date(byAdding: .day, value: 14, to: today)!

func ics(_ events: String) -> String { "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n\(events)END:VCALENDAR\r\n" }
func stamp(_ d: Date, utc: Bool = true) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = utc ? TimeZone(identifier: "UTC") : .current
    f.dateFormat = utc ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd"
    return f.string(from: d)
}
let tomorrowNoon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.date(byAdding: .day, value: 1, to: today)!)!

// MARK: ICS – single events

do {
    let r = ICS.parse(ics("BEGIN:VEVENT\r\nUID:1\r\nSUMMARY:Quiz\\, part A\r\nDTSTART:\(stamp(tomorrowNoon))\r\nEND:VEVENT\r\n"), from: today, to: window)
    expect(r.count == 1, "single event parsed")
    expect(r.first?.title == "Quiz, part A", "escaped comma unescaped")
    expect(r.first?.start == tomorrowNoon, "UTC time parsed")
    expect(r.first?.allDay == false, "timed event not all-day")
}

do {
    let d = cal.date(byAdding: .day, value: 2, to: today)!
    let r = ICS.parse(ics("BEGIN:VEVENT\r\nUID:2\r\nSUMMARY:Exam\r\nDTSTART;VALUE=DATE:\(stamp(d, utc: false))\r\nEND:VEVENT\r\n"), from: today, to: window)
    expect(r.first?.allDay == true && r.first?.start == d, "all-day date parsed in local time")
}

do {
    let r = ICS.parse(ics("BEGIN:VEVENT\r\nUID:3\r\nSUMMARY:Lecture\r\nDTSTART;TZID=\"America/New_York\":20300105T090000\r\nEND:VEVENT\r\n"),
                      from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 4_102_444_800))
    var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
    let want = ny.date(from: DateComponents(year: 2030, month: 1, day: 5, hour: 9))!
    expect(r.first?.start == want, "quoted TZID respected")
}

do {
    let folded = "BEGIN:VEVENT\r\nUID:4\r\nSUMMARY:A very long\r\n  title\r\nDTSTART:\(stamp(tomorrowNoon))\r\nEND:VEVENT\r\n"
    expect(ICS.parse(ics(folded), from: today, to: window).first?.title == "A very long title", "folded lines joined")
}

do {
    let old = "BEGIN:VEVENT\r\nUID:5\r\nSUMMARY:Old\r\nDTSTART:20000101T100000Z\r\nEND:VEVENT\r\n"
    let cancelled = "BEGIN:VEVENT\r\nUID:6\r\nSUMMARY:Off\r\nSTATUS:CANCELLED\r\nDTSTART:\(stamp(tomorrowNoon))\r\nEND:VEVENT\r\n"
    expect(ICS.parse(ics(old + cancelled), from: today, to: window).isEmpty, "past and cancelled events dropped")
}

// MARK: ICS – recurrence

do {
    let start = cal.date(byAdding: .day, value: -30, to: tomorrowNoon)!
    let r = ICS.parse(ics("BEGIN:VEVENT\r\nUID:7\r\nSUMMARY:Daily\r\nDTSTART:\(stamp(start))\r\nRRULE:FREQ=DAILY\r\nEND:VEVENT\r\n"), from: today, to: window)
    expect((14...15).contains(r.count), "daily repeat fills the window (\(r.count))")
    expect(r.allSatisfy { $0.start >= today && $0.start <= window }, "repeats stay inside the window")
}

do {
    let start = cal.date(byAdding: .day, value: -60, to: tomorrowNoon)!
    let r = ICS.parse(ics("BEGIN:VEVENT\r\nUID:8\r\nSUMMARY:Gone\r\nDTSTART:\(stamp(start))\r\nRRULE:FREQ=DAILY;COUNT=5\r\nEND:VEVENT\r\n"), from: today, to: window)
    expect(r.isEmpty, "COUNT limit ends the series")
}

do {
    let r = ICS.parse(ics("BEGIN:VEVENT\r\nUID:9\r\nSUMMARY:MWF\r\nDTSTART:\(stamp(tomorrowNoon))\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR\r\nEND:VEVENT\r\n"), from: today, to: window)
    let weekdays = Set(r.map { cal.component(.weekday, from: $0.start) })
    expect(!r.isEmpty && weekdays.isSubset(of: [2, 4, 6]), "weekly BYDAY only on listed days")
}

do {
    let skip = cal.date(byAdding: .day, value: 1, to: tomorrowNoon)!
    let r = ICS.parse(ics("BEGIN:VEVENT\r\nUID:10\r\nSUMMARY:Skip\r\nDTSTART:\(stamp(tomorrowNoon))\r\nRRULE:FREQ=DAILY;COUNT=3\r\nEXDATE:\(stamp(skip))\r\nEND:VEVENT\r\n"), from: today, to: window)
    expect(r.count == 2 && !r.contains { $0.start == skip }, "EXDATE removes an occurrence")
}

do {
    let until = cal.date(byAdding: .day, value: 3, to: tomorrowNoon)!
    let r = ICS.parse(ics("BEGIN:VEVENT\r\nUID:11\r\nSUMMARY:Until\r\nDTSTART:\(stamp(tomorrowNoon))\r\nRRULE:FREQ=DAILY;UNTIL=\(stamp(until))\r\nEND:VEVENT\r\n"), from: today, to: window)
    expect(r.count == 4, "UNTIL is inclusive (\(r.count))")
}

// MARK: ICS – hostile input never crashes

do {
    let junk = [
        "", "garbage", "BEGIN:VEVENT", "END:VEVENT", "BEGIN:VEVENT\r\nDTSTART:2\r\nEND:VEVENT",
        "BEGIN:VEVENT\r\nDTSTART:20261\r\nEND:VEVENT", "BEGIN:VEVENT\r\nDTSTART:2026012\r\nEND:VEVENT",
        "BEGIN:VEVENT\r\nDTSTART:\(stamp(tomorrowNoon))\r\nRRULE:FREQ=DAILY;INTERVAL=0\r\nEND:VEVENT",
        "BEGIN:VEVENT\r\nDTSTART:\(stamp(tomorrowNoon))\r\nRRULE:FREQ=WEEKLY;BYDAY=XX,\r\nEND:VEVENT",
        "BEGIN:VEVENT\r\nDTSTART:\(stamp(tomorrowNoon))\r\nRRULE:FREQ=YEARLY;COUNT=-1\r\nEND:VEVENT",
        "BEGIN:VEVENT\r\nDTSTART;TZID=Not/AZone:20261028T100000\r\nEXDATE:,,,\r\nEND:VEVENT",
        String(repeating: "BEGIN:VEVENT\r\n", count: 2000),
    ]
    for j in junk { _ = ICS.parse(j, from: today, to: window) }
    var rng = SystemRandomNumberGenerator()
    let alphabet = Array("BEGIN:VEVENTDTSTARTRRULE=;:,0123456789TZ\r\n\\ ")
    for _ in 0..<3000 {
        let s = String((0..<Int.random(in: 0..<300, using: &rng)).map { _ in alphabet.randomElement(using: &rng)! })
        _ = ICS.parse(s, from: today, to: window)
    }
    expect(true, "parser survives malformed and random input")
}

// MARK: Network allow-list

expect(Safe.httpsURL("https://canvas.example.edu/feed.ics") != nil, "https allowed")
expect(Safe.httpsURL("webcal://p01.calendar.example.com/x.ics")?.scheme == "https", "webcal upgraded to https")
expect(Safe.httpsURL("  https://example.com/x  ") != nil, "whitespace trimmed")
for bad in ["http://example.com/x.ics", "file:///etc/passwd", "javascript:alert(1)", "https://user:pw@example.com/x",
            "https://localhost/x", "ftp://example.com/x", "https:///nohost", "", "not a url", "data:text/calendar,BEGIN"] {
    expect(Safe.httpsURL(bad) == nil, "rejected: \(bad)")
}

print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
