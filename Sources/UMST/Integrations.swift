import Foundation

/// Services UMST can connect to. Most publish a private calendar (iCal) link; UMST stores that link in the
/// Keychain and reads it directly, so nothing has to be subscribed in macOS Calendar first.
/// Google, iCloud, Outlook/Exchange and Yahoo accounts are better added to the Mac itself (Internet Accounts),
/// which also brings in events Mail finds in your email.
struct Service: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String          // SF Symbol
    let group: String
    let steps: String
    var tokenOption = false   // Canvas: planner API with an access token

    static let all: [Service] = [
        Service(id: "canvas", name: "Canvas", icon: "graduationcap", group: "School",
                steps: "In Canvas, open Calendar and click Calendar Feed (bottom right). Copy the link.", tokenOption: true),
        Service(id: "blackboard", name: "Blackboard", icon: "graduationcap", group: "School",
                steps: "Open Calendar, then Calendar Settings → Share Calendar. Copy the link."),
        Service(id: "brightspace", name: "Brightspace (D2L)", icon: "graduationcap", group: "School",
                steps: "Open Calendar → Settings, turn on Enable Calendar Feeds and save. Click Subscribe, choose All Calendars and copy the link."),
        Service(id: "moodle", name: "Moodle", icon: "graduationcap", group: "School",
                steps: "Open Calendar → Export calendar (or Import or export calendars). Choose All events, click Get calendar URL and copy it."),
        Service(id: "schoology", name: "Schoology", icon: "graduationcap", group: "School",
                steps: "Open your Calendar and use the iCal / Export option (some schools put it under Account Settings). Copy the link."),
        Service(id: "google", name: "Google Calendar", icon: "calendar", group: "Calendars",
                steps: "Easiest: add your Google account to this Mac (button above) — that also covers Gmail invites and Google Classroom. Or in Google Calendar on the web: Settings → your calendar → Integrate calendar → copy Secret address in iCal format."),
        Service(id: "outlook", name: "Outlook / Microsoft 365", icon: "calendar", group: "Calendars",
                steps: "Easiest: add your Microsoft account to this Mac (button above). Or in Outlook on the web: Settings → Calendar → Shared calendars → Publish a calendar, then copy the ICS link."),
        Service(id: "todoist", name: "Todoist", icon: "checklist", group: "Tasks",
                steps: "In Todoist on the web or desktop: Settings → Integrations → Calendar Subscription URL → Copy link."),
        Service(id: "asana", name: "Asana", icon: "checklist", group: "Tasks",
                steps: "Open My Tasks or a project, open its menu (▾) → Sync to calendar, and copy the link."),
        Service(id: "trello", name: "Trello", icon: "checklist", group: "Tasks",
                steps: "On a board, add the Calendar Power-Up, open its settings, turn on sync and copy the iCalendar feed link."),
        Service(id: "ics", name: "Other calendar link", icon: "link", group: "Other",
                steps: "Paste any link that ends in .ics or starts with webcal:// — sports schedules, school portals, work rosters, holidays."),
    ]

    static func find(_ id: String?) -> Service? { all.first { $0.id == id } }
}
