import AppKit
import Combine
import SwiftUI

// MARK: Desktop widget window
// Sits just above the desktop icons and below every app window, on all Spaces,
// so Show Desktop (which hides apps) leaves it front and center.

final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class CalendarWidgetController {
    let window: WidgetWindow
    private var bag = Set<AnyCancellable>()

    init(onAdd: @escaping () -> Void) {
        let size = NSSize(width: 360, height: 440)
        let autosave = isDemo ? "CalendarWidgetDemo" : "CalendarWidget"
        let w = WidgetWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        w.isMovableByWindowBackground = true
        w.contentView = FirstClickHostingView(rootView: CalendarWidget(onAdd: onAdd))
        if !w.setFrameUsingName(autosave), let s = NSScreen.main?.visibleFrame {
            w.setFrameOrigin(NSPoint(x: s.midX - size.width / 2, y: s.midY - size.height / 2))
        }
        w.setFrameAutosaveName(autosave)
        window = w

        let settings = AppSettings.shared
        settings.$themeID
            .sink { id in
                switch Theme.find(id).scheme {
                case .dark?: w.appearance = NSAppearance(named: .darkAqua)
                case .light?: w.appearance = NSAppearance(named: .aqua)
                default: w.appearance = nil
                }
            }
            .store(in: &bag)
        settings.onWidgetToggle = { [weak self] on in self?.setVisible(on) }
        setVisible(settings.showWidget)
    }

    func setVisible(_ on: Bool) {
        if on {
            window.alphaValue = 0
            window.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = AppSettings.shared.anim() == nil ? 0 : 0.35
                window.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = AppSettings.shared.anim() == nil ? 0 : 0.25
                window.animator().alphaValue = 0
            }, completionHandler: { [window] in window.orderOut(nil) })
        }
    }
}

struct CalendarWidget: View {
    @ObservedObject var store = CalendarStore.shared
    @ObservedObject var settings = AppSettings.shared
    let onAdd: () -> Void
    @State private var selected: Date?
    @Namespace private var stripNS

    private var theme: Theme { settings.theme }
    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: store.today) }
    }
    private var focusDay: Date { selected ?? store.today }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            weekStrip
            Divider().opacity(0.5)
            agenda
            footer
        }
        .padding(16)
        .frame(width: 360, height: 440)
        .background(theme.background(20))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .tint(theme.accent)
        .animation(settings.anim(.easeInOut(duration: 0.35)), value: settings.themeID)
        .transaction { if settings.anim() == nil { $0.animation = nil } }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(store.today.formatted(.dateTime.weekday(.wide)).uppercased())
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.accent)
                Text(store.today.formatted(.dateTime.month(.wide).day()))
                    .font(.system(size: 22, weight: .bold))
            }
            Spacer()
            HStack(spacing: 2) {
                IconButton(name: "plus", help: "Add to calendar", action: onAdd)
                IconButton(name: "arrow.clockwise", help: "Refresh calendar") { store.refresh() }
                    .rotationEffect(.degrees(store.refreshing ? 360 : 0))
                    .animation(store.refreshing && settings.animations
                               ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                               value: store.refreshing)
                Menu {
                    Button("Accounts & Setup…") { SettingsWindow.show(.accounts) }
                    Button("Appearance…") { SettingsWindow.show(.appearance) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium)).frame(width: 26, height: 26)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.self) { d in
                let on = d == focusDay
                let isToday = d == store.today
                Button {
                    withAnimation(settings.anim()) { selected = (d == store.today) ? nil : d }
                } label: {
                    VStack(spacing: 3) {
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(on ? .white.opacity(0.85) : .secondary)
                        Text(d.formatted(.dateTime.day())).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? .white : (isToday ? theme.accent : .primary))
                        Circle().frame(width: 4, height: 4)
                            .foregroundStyle(store.events(on: d).isEmpty ? .clear : (on ? .white : .secondary))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.accent)
                                .matchedGeometryEffect(id: "day", in: stripNS)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var agenda: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(days, id: \.self) { d in
                        let evs = store.events(on: d)
                        if d == store.today || d == focusDay || !evs.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dayLabel(d)).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(d == focusDay && selected != nil ? theme.accent : .secondary)
                                if evs.isEmpty {
                                    Text(d == store.today ? "Nothing today. Press + to add something." : "Nothing scheduled.")
                                        .font(.system(size: 12)).foregroundStyle(.tertiary).padding(.vertical, 3)
                                }
                                ForEach(evs) { e in
                                    EventRow(e: e, day: d)
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .move(edge: .top)),
                                            removal: .opacity.combined(with: .scale(scale: 0.96))))
                                }
                            }
                            .id(d)
                        }
                    }
                }
                .animation(settings.anim(), value: store.events)
            }
            .onChange(of: selected) {
                withAnimation(settings.anim()) { proxy.scrollTo(focusDay, anchor: .top) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if !store.isSetUp {
                Button { SettingsWindow.show(.accounts) } label: {
                    Label("Set Up Accounts", systemImage: "person.crop.circle.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(theme.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else if let p = store.problem {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(p).lineLimit(1)
            } else if let l = store.lastRefresh {
                Text("Updated \(l.formatted(date: .omitted, time: .shortened))")
                    .contentTransition(.numericText())
            }
            Spacer()
            if store.isSetUp {
                Button { SettingsWindow.show(.accounts) } label: {
                    Image(systemName: "person.crop.circle").font(.system(size: 12))
                }
                .buttonStyle(.plain).help("Accounts")
            }
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
    }

    private func dayLabel(_ d: Date) -> String {
        let diff = Calendar.current.dateComponents([.day], from: store.today, to: d).day ?? 0
        return diff == 0 ? "Today" : diff == 1 ? "Tomorrow" : d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

struct IconButton: View {
    let name: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background(hover ? Color.primary.opacity(0.08) : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(help)
        .onHover { h in withAnimation(AppSettings.shared.anim(.easeOut(duration: 0.15))) { hover = h } }
    }
}

struct EventRow: View {
    let e: CalEvent
    let day: Date
    @ObservedObject var settings = AppSettings.shared
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            if e.local {
                Button { withAnimation(settings.anim()) { CalendarStore.shared.complete(e) } } label: {
                    Image(systemName: hover ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13)).foregroundStyle(hover ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain).help("Mark done")
            } else {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: e.color)).frame(width: 3, height: 14)
                    .padding(.horizontal, 5)
            }
            Text(timeLabel).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(e.title).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .background(hover ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { h in withAnimation(settings.anim(.easeOut(duration: 0.12))) { hover = h } }
        .help(e.source)
    }

    private var timeLabel: String {
        if e.local { return "To-do" }
        if e.allDay { return "All day" }
        if e.start < day {   // continues from an earlier day
            let next = Calendar.current.date(byAdding: .day, value: 1, to: day)!
            if let end = e.end, end < next { return "→ " + end.formatted(.dateTime.hour().minute()) }
            return "All day"
        }
        return e.start.formatted(.dateTime.hour().minute())
    }
}

// MARK: Quick add (menu bar popover)

struct QuickAddView: View {
    let close: () -> Void
    @ObservedObject var settings = AppSettings.shared
    @State private var text = ""
    @State private var day = Date()
    @FocusState private var focused: Bool

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var isTomorrow: Bool { Calendar.current.isDateInTomorrow(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(isToday ? "Add to today…" : "Add to \(day.formatted(.dateTime.weekday(.wide)))…", text: $text)
                .textFieldStyle(.plain).font(.system(size: 14))
                .focused($focused)
                .onSubmit(add)
            HStack(spacing: 6) {
                chip("Today", on: isToday) { day = Date() }
                chip("Tomorrow", on: isTomorrow) { day = Calendar.current.date(byAdding: .day, value: 1, to: Date())! }
                DatePicker("", selection: $day, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).controlSize(.small).fixedSize()
                Spacer()
                Text("↩").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 300)
        .tint(settings.theme.accent)
        .onAppear { text = ""; day = Date(); DispatchQueue.main.async { focused = true } }
        .onExitCommand(perform: close)
    }

    private func chip(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(settings.anim(.easeOut(duration: 0.18))) { action() } } label: {
            Text(t).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(on ? settings.theme.accent : Color.primary.opacity(0.07), in: Capsule())
                .foregroundStyle(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func add() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { close(); return }
        CalendarStore.shared.add(text, on: day)
        text = ""
        close()
    }
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x8E8E93
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
