import ServiceManagement
import SwiftUI

struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let accent: Color
    let gradient: [Color]?        // nil = native frosted glass
    let tint: Double              // how strongly the gradient covers the glass
    let scheme: ColorScheme?      // force light/dark, or follow the system

    static let all: [Theme] = [
        Theme(id: "glass", name: "Glass", accent: .red, gradient: nil, tint: 0, scheme: nil),
        Theme(id: "midnight", name: "Midnight", accent: Color(red: 0.39, green: 0.6, blue: 1),
              gradient: [Color(red: 0.06, green: 0.08, blue: 0.2), Color(red: 0.13, green: 0.1, blue: 0.32)], tint: 0.82, scheme: .dark),
        Theme(id: "sunset", name: "Sunset", accent: Color(red: 1, green: 0.45, blue: 0.3),
              gradient: [Color(red: 1, green: 0.62, blue: 0.45), Color(red: 0.86, green: 0.36, blue: 0.56)], tint: 0.55, scheme: .dark),
        Theme(id: "forest", name: "Forest", accent: Color(red: 0.3, green: 0.8, blue: 0.5),
              gradient: [Color(red: 0.05, green: 0.2, blue: 0.14), Color(red: 0.1, green: 0.3, blue: 0.22)], tint: 0.8, scheme: .dark),
        Theme(id: "lavender", name: "Lavender", accent: Color(red: 0.55, green: 0.4, blue: 0.95),
              gradient: [Color(red: 0.93, green: 0.9, blue: 1), Color(red: 0.86, green: 0.88, blue: 1)], tint: 0.7, scheme: .light),
        Theme(id: "graphite", name: "Graphite", accent: Color(white: 0.85),
              gradient: [Color(white: 0.12), Color(white: 0.2)], tint: 0.85, scheme: .dark),
    ]

    static func find(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }

    @ViewBuilder func background(_ radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(.regularMaterial)
            if let g = gradient {
                shape.fill(LinearGradient(colors: g, startPoint: .topLeading, endPoint: .bottomTrailing)).opacity(tint)
            }
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = isDemo ? UserDefaults(suiteName: "com.umst.app.demo")! : .standard

    @Published var themeID: String { didSet { d.set(themeID, forKey: "theme") } }
    @Published var animations: Bool { didSet { d.set(animations, forKey: "animations") } }
    @Published var showWidget: Bool { didSet { d.set(showWidget, forKey: "showWidget"); onWidgetToggle?(showWidget) } }
    @Published var openAtLogin: Bool { didSet { d.set(openAtLogin, forKey: "openAtLogin"); applyLoginItem() } }
    @Published private(set) var loginItemError: String?
    @Published var hiddenCalendars: Set<String> {
        didSet { d.set(Array(hiddenCalendars), forKey: "hiddenCalendars"); CalendarStore.shared.refresh() }
    }

    var onWidgetToggle: ((Bool) -> Void)?
    var theme: Theme { Theme.find(themeID) }

    private init() {
        themeID = d.string(forKey: "theme") ?? "glass"
        animations = d.object(forKey: "animations") as? Bool ?? true
        showWidget = d.object(forKey: "showWidget") as? Bool ?? true
        openAtLogin = d.object(forKey: "openAtLogin") as? Bool ?? true
        hiddenCalendars = Set(d.stringArray(forKey: "hiddenCalendars") ?? [])
    }

    func applyLoginItem() {
        let svc = SMAppService.mainApp
        do {
            if openAtLogin, svc.status != .enabled { try svc.register() }
            if !openAtLogin, svc.status == .enabled { try svc.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = "Couldn't change this. Add UMST in System Settings → General → Login Items."
        }
    }

    /// The animation to use, or nil when animations are off (also honors the system Reduce Motion setting)
    func anim(_ a: Animation = .spring(response: 0.35, dampingFraction: 0.85)) -> Animation? {
        animations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? a : nil
    }
}
