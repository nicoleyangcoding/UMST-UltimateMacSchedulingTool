import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable { case accounts = "Accounts", appearance = "Appearance" }

@MainActor
final class SettingsNav: ObservableObject {
    static let shared = SettingsNav()
    @Published var tab: SettingsTab = .accounts
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(_ tab: SettingsTab = .accounts) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "UMST Settings"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView())
            w.center()
            window = w
        }
        SettingsNav.shared.tab = tab
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var nav = SettingsNav.shared
    @ObservedObject var settings = AppSettings.shared
    @Namespace private var tabNS

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { t in
                    Button { withAnimation(settings.anim()) { nav.tab = t } } label: {
                        Text(t.rawValue).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .foregroundStyle(nav.tab == t ? .primary : .secondary)
                            .background {
                                if nav.tab == t {
                                    Capsule().fill(.quaternary).matchedGeometryEffect(id: "tab", in: tabNS)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 34).padding(.bottom, 12)

            Group {
                switch nav.tab {
                case .accounts: AccountsTab()
                case .appearance: AppearanceTab()
                }
            }
            .transition(.opacity)
        }
        .frame(width: 520, height: 520)
        .tint(settings.theme.accent)
    }
}

// MARK: Accounts

struct AccountsTab: View {
    @ObservedObject var store = CalendarStore.shared
    @ObservedObject var settings = AppSettings.shared
    @State private var calendars: [DeviceCalendar] = []
    @State private var adding = false
    @State private var pendingRemoval: Source?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Mac Calendars", caption: "Google, Gmail, iCloud and Exchange accounts added to this Mac.") {
                    if store.needsCalendarAccess {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.lock").font(.system(size: 22)).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Calendar access is off").font(.system(size: 13, weight: .medium))
                                Text("Allow UMST to read the calendars on this Mac.").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Allow Access") { store.requestCalendarAccess() }.buttonStyle(.borderedProminent)
                        }
                    } else if calendars.isEmpty {
                        Text("No calendars yet. Add an account below.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        let accounts = Dictionary(grouping: calendars, by: \.account).sorted { $0.key < $1.key }
                        ForEach(accounts, id: \.key) { account, cals in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(account).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                ForEach(cals) { c in
                                    Toggle(isOn: visibility(c)) {
                                        HStack(spacing: 8) {
                                            Circle().fill(Color(hex: c.color)).frame(width: 8, height: 8)
                                            Text(c.title).font(.system(size: 12.5)).lineLimit(1)
                                        }
                                    }
                                    .toggleStyle(.switch).controlSize(.mini)
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
                            NSWorkspace.shared.open(u)
                        }
                    } label: { Label("Add Google or Other Account…", systemImage: "plus.circle") }
                        .buttonStyle(.link).font(.system(size: 12))
                }

                section("Calendar Feeds", caption: "Canvas, Google secret iCal links, Outlook and any other calendar link.") {
                    let feeds = store.sources.filter { $0.type != "apple" }
                    if feeds.isEmpty && !adding {
                        Text("No feeds connected.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(feeds) { s in
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: s.color ?? "#8E8E93")).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(s.name).font(.system(size: 12.5, weight: .medium))
                                Text("\(s.host ?? "") · \(s.type == "canvas" ? "Canvas API" : "Feed")")
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { pendingRemoval = s } label: { Image(systemName: "trash").font(.system(size: 11)) }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("Disconnect")
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if adding {
                        AddFeedForm { withAnimation(settings.anim()) { adding = false } }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        Button { withAnimation(settings.anim()) { adding = true } } label: {
                            Label("Add Feed…", systemImage: "plus.circle")
                        }
                        .buttonStyle(.link).font(.system(size: 12))
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    Text("Links and tokens are kept in your Keychain, never in files. UMST only connects to the calendars you add, over HTTPS, and sends nothing anywhere else.")
                        .font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .animation(settings.anim(), value: store.sources.map(\.id))
        }
        .onAppear { calendars = store.deviceCalendars() }
        .onChange(of: store.calendarAccess) { calendars = store.deviceCalendars() }
        .onChange(of: store.lastRefresh) { calendars = store.deviceCalendars() }
        .confirmationDialog("Disconnect \(pendingRemoval?.name ?? "")?", isPresented: .init(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Disconnect", role: .destructive) {
                if let s = pendingRemoval { store.removeSource(s) }
                pendingRemoval = nil
            }
        } message: { Text("Its link or token is deleted from your Keychain.") }
    }

    private func visibility(_ c: DeviceCalendar) -> Binding<Bool> {
        Binding(get: { !settings.hiddenCalendars.contains(c.id) },
                set: { on in
                    if on { settings.hiddenCalendars.remove(c.id) } else { settings.hiddenCalendars.insert(c.id) }
                })
    }

    private func section<C: View>(_ title: String, caption: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct AddFeedForm: View {
    let done: () -> Void
    @State private var name = ""
    @State private var link = ""
    @State private var useToken = false
    @State private var token = ""
    @State private var reveal = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name (e.g. Canvas)", text: $name).textFieldStyle(.roundedBorder)
            HStack(spacing: 6) {
                Group {
                    if reveal { TextField(useToken ? "https://canvas.school.edu" : "https://… or webcal://…", text: $link) }
                    else { SecureField(useToken ? "https://canvas.school.edu" : "https://… or webcal://…", text: $link) }
                }
                .textFieldStyle(.roundedBorder)
                Button { reveal.toggle() } label: { Image(systemName: reveal ? "eye.slash" : "eye") }
                    .buttonStyle(.borderless).help(reveal ? "Hide" : "Show")
            }
            Toggle("Use a Canvas API token instead of a feed link", isOn: $useToken)
                .toggleStyle(.checkbox).font(.system(size: 11))
            if useToken {
                SecureField("Canvas access token", text: $token).textFieldStyle(.roundedBorder)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill").font(.system(size: 11)).foregroundStyle(.red)
            }
            HStack {
                Text(useToken ? "Canvas → Account → Settings → New Access Token" : "Canvas → Calendar → Calendar Feed")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button {
                    connect()
                } label: {
                    if busy { ProgressView().controlSize(.small).frame(width: 56) } else { Text("Connect").frame(width: 56) }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(busy || link.isEmpty || (useToken && token.isEmpty))
            }
        }
    }

    private func connect() {
        busy = true; error = nil
        Task {
            do {
                try await CalendarStore.shared.addFeed(name: name, link: link, token: useToken ? token : nil)
                link = ""; token = ""
                done()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? FeedError.unreachable.errorDescription
            }
            busy = false
        }
    }
}

// MARK: Appearance

struct AppearanceTab: View {
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Theme").font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                    ForEach(Theme.all) { t in
                        Button { withAnimation(settings.anim(.easeInOut(duration: 0.35))) { settings.themeID = t.id } } label: {
                            VStack(spacing: 6) {
                                ThemePreview(theme: t)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(settings.themeID == t.id ? t.accent : .clear, lineWidth: 2.5))
                                Text(t.name).font(.system(size: 11.5, weight: settings.themeID == t.id ? .semibold : .regular))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settings.animations) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Animations").font(.system(size: 12.5, weight: .medium))
                            Text("Smooth transitions in the calendar and menus. Turns off automatically with Reduce Motion.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    Toggle(isOn: $settings.showWidget) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show calendar on desktop").font(.system(size: 12.5, weight: .medium))
                            Text("Drag the calendar to move it. It stays visible when you use Show Desktop.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .padding(14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}

struct ThemePreview: View {
    let theme: Theme
    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.background(12)
            VStack(alignment: .leading, spacing: 4) {
                Text("TUESDAY").font(.system(size: 6.5, weight: .bold)).foregroundStyle(theme.accent)
                Text("Oct 27").font(.system(size: 12, weight: .bold))
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.accent).frame(width: 12, height: 14)
                    ForEach(0..<4, id: \.self) { _ in RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.08)).frame(width: 12, height: 14) }
                }
                Capsule().fill(.primary.opacity(0.15)).frame(width: 70, height: 4)
                Capsule().fill(.primary.opacity(0.1)).frame(width: 50, height: 4)
            }
            .padding(10)
        }
        .frame(height: 92)
        .environment(\.colorScheme, theme.scheme ?? system)
    }

    @Environment(\.colorScheme) private var system
}
