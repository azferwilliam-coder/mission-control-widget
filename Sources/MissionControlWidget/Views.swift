import SwiftUI
import AppKit
import MissionCore

/// "Liquid Glass" colours: white text on real macOS glass, with amber kept for London time, the dot and the timer.
enum Dusk {
    static let amber = Color(red: 1.0, green: 0.79, blue: 0.44)          // #FFC970
    static let amberDim = Color(red: 0.94, green: 0.76, blue: 0.48)      // #F0C27A
    static let coral = Color(red: 1.0, green: 0.42, blue: 0.37)          // #FF6B5E
    static let pulse = Color.white
    static let edge = Color.white.opacity(0.16)
    static let hairline = Color.white.opacity(0.18)
    static let text = Color.white.opacity(0.96)
    static let value = Color.white.opacity(0.96)
    static let muted = Color.white.opacity(0.78)
    static let faint = Color.white.opacity(0.68)
    /// A soft shadow under the text so it stays readable on bright or busy wallpapers.
    static let textShadow = Color.black.opacity(0.4)

    static let tabWidth: CGFloat = 45
    static let tabHeight: CGFloat = 255
    static let drawerWidth: CGFloat = 300
    static let topGap: CGFloat = 24

    /// True while rendering review pictures, where the live glass can't be captured, so a look-alike is drawn instead.
    @MainActor static var snapshotMode = false
    /// Draw the clear glass in review pictures.
    @MainActor static var snapshotClear = false
}

/// The frosted glass behind the tab and drawer, flush with the screen's left edge.
/// macOS 26 and later: Apple's own Liquid Glass, as used by the Dock, lightly tinted so white text stays readable.
/// Earlier macOS: the standard frosted HUD material.
struct GlassBackground: View {
    var radius: CGFloat

    /// Right-click > Clear Glass: see-through like the Dock, instead of frosted.
    @AppStorage("clearGlass") private var clearGlass = false

    var body: some View {
        let shape = TabShape(radius: radius)
        // Review pictures ignore your own Clear Glass setting, so each one shows the look it's meant to.
        if Dusk.snapshotMode ? Dusk.snapshotClear : clearGlass {
            CrystalGlass(radius: radius)
        } else if Dusk.snapshotMode {
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.20), Color.white.opacity(0.07)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .background(shape.fill(Color(white: 0.30).opacity(0.6)))
                .overlay(TabEdge(radius: radius).stroke(Dusk.edge, lineWidth: 1))
        } else if #available(macOS 26.0, *) {
            // Bleeds a little past the left edge (the window clips it), so no rim shows against the screen edge.
            Color.clear
                .glassEffect(.regular.tint(Color.black.opacity(0.22)), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .padding(.leading, -(radius + 4))
        } else {
            FrostedMaterial()
                .clipShape(shape)
                .overlay(TabEdge(radius: radius).stroke(Dusk.edge, lineWidth: 1))
        }
    }
}

/// Clear, Dock-style glass drawn by hand: no blur at all, so the wallpaper shows straight through,
/// with a bright rim and a soft inner edge glow that give it the look of a pane of real glass.
struct CrystalGlass: View {
    var radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            // A faint sheen at the top like light on glass, then the lightest dark wash so white text stays readable.
            shape.fill(LinearGradient(stops: [.init(color: Color.white.opacity(0.10), location: 0),
                                              .init(color: Color.black.opacity(0.14), location: 0.3),
                                              .init(color: Color.black.opacity(0.20), location: 1)],
                                      startPoint: .top, endPoint: .bottom))
            // Thick-edge glow just inside the rim, where real glass bends the light.
            shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 6)
                .blur(radius: 5)
                .clipShape(shape)
            // The crisp rim: bright on top, fading down the sides, catching light again at the bottom.
            shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.65), Color.white.opacity(0.14),
                                                       Color.white.opacity(0.10), Color.white.opacity(0.30)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        // Bleeds past the left edge (the window clips it), so no rim shows against the screen edge.
        .padding(.leading, -(radius + 4))
        .allowsHitTesting(false)
    }
}

/// Soft shadow under text only (not the glowing dot or pulse). Stronger on clear glass, where nothing frosts the wallpaper behind it.
struct DuskTextShadow: ViewModifier {
    @AppStorage("clearGlass") private var clearGlass = false

    func body(content: Content) -> some View {
        let clear = Dusk.snapshotMode ? Dusk.snapshotClear : clearGlass
        content
            .shadow(color: Color.black.opacity(clear ? 0.55 : 0.4), radius: clear ? 1.5 : 1, y: 1)
            .shadow(color: Color.black.opacity(clear ? 0.35 : 0), radius: clear ? 4 : 0)
    }
}

extension View {
    func duskTextShadow() -> some View { modifier(DuskTextShadow()) }
}

/// The older frosted material (macOS 14 and 15).
struct FrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// The small glowing dot: amber when all is well, coral when something needs you.
struct StatusDot: View {
    var attention: Bool
    var animate = true
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = attention ? Dusk.coral : Dusk.amber
        let moving = animate && !reduceMotion
        // A gentle breathe, redrawn about 12 times a second (cheap, and stops when not needed).
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !moving)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            let level = moving ? 0.4 + 0.6 * (0.5 - 0.5 * cos(phase * 2 * .pi)) : 1
            Circle()
                .fill(c)
                .frame(width: size, height: size)
                .shadow(color: c.opacity(0.9), radius: size * 5 / 6)
                .opacity(level)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Two digits stacked, with a three-letter label spread to exactly the digits' width.
struct CityTime: View {
    var code: String
    var hours: String
    var minutes: String
    var colour: Color
    var minuteColour: Color
    var labelColour: Color
    var labelOnTop: Bool

    static let digitFont = NSFont.monospacedDigitSystemFont(ofSize: 19, weight: .light)
    static let digitWidth: CGFloat = ceil(("88" as NSString).size(withAttributes: [.font: digitFont]).width)

    var label: some View {
        HStack(spacing: 0) {
            ForEach(Array(code.enumerated()), id: \.offset) { i, ch in
                if i > 0 { Spacer(minLength: 0) }
                Text(String(ch))
            }
        }
        .font(.system(size: 7.5, weight: .medium))
        .foregroundStyle(labelColour)
        .frame(width: CityTime.digitWidth)
    }

    var body: some View {
        VStack(spacing: 5) {
            if labelOnTop { label }
            VStack(spacing: 0) {
                Text(hours).foregroundStyle(colour)
                Text(minutes).foregroundStyle(minuteColour)
            }
            .font(Font(CityTime.digitFont))
            .frame(width: CityTime.digitWidth)
            if !labelOnTop { label }
        }
        .duskTextShadow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(code == "BWN" ? "Brunei" : "London") \(hours):\(minutes)")
    }
}

/// The peek tab that stays on the left edge when the drawer is tucked away (design T5).
struct TabStrip: View {
    @ObservedObject var model: DashboardModel
    var animate = true
    /// Off while the drawer is open, so two glass layers never overlap.
    var glass = true

    var body: some View {
        let bn = Format.clockParts(model.now, timeZone: model.homeZone)
        let ld = Format.clockParts(model.now, timeZone: model.londonZone)
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CityTime(code: "BWN", hours: bn.hours, minutes: bn.minutes,
                     colour: Dusk.text, minuteColour: Dusk.muted, labelColour: Dusk.muted, labelOnTop: true)
            Spacer(minLength: 0)
            StatusDot(attention: model.status.needsAttention, animate: animate, size: 7.5)
            Spacer(minLength: 0)
            CityTime(code: "LDN", hours: ld.hours, minutes: ld.minutes,
                     colour: Dusk.amber, minuteColour: Dusk.amberDim, labelColour: Dusk.amberDim, labelOnTop: false)
            Spacer(minLength: 0)
        }
        .frame(width: Dusk.tabWidth, height: Dusk.tabHeight)
        .background { if glass { GlassBackground(radius: 22) } }
        .contentShape(TabShape(radius: 22))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mission Control Widget")
        .accessibilityValue(model.status.reason ?? "All calm")
    }
}

/// A rectangle with only its right-hand corners rounded (it sits flush against the screen edge).
struct TabShape: Shape {
    var radius: CGFloat

    func path(in r: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                               bottomTrailingRadius: radius, topTrailingRadius: radius, style: .continuous)
            .path(in: r)
    }
}

/// The outline of TabShape without its left side, so no line shows against the screen edge.
struct TabEdge: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        // Keep the whole 1pt line inside the window so the right side is as bright as the top and bottom.
        let r = CGRect(x: rect.minX, y: rect.minY + 0.5, width: rect.width - 0.5, height: rect.height - 1)
        let rad = min(radius, r.height / 2, r.width)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + rad), radius: rad)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - rad, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        return p
    }
}

/// Lets the window know how tall the open drawer really is.
struct DrawerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The live heartbeat line with a bright light running along it. Taller beats when the Mac is busier.
struct PulseLine: View {
    var load: Double
    var animate = true
    var fixedPhase: Double = 0.35
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moving = animate && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            Canvas { ctx, size in
                let pts = Pulse.heartbeat(width: size.width, height: size.height, load: load)
                var path = Path()
                for (i, p) in pts.enumerated() {
                    let cg = CGPoint(x: p.x, y: p.y)
                    if i == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
                }
                var base = Path()
                base.move(to: CGPoint(x: 0, y: size.height * 0.6))
                base.addLine(to: CGPoint(x: size.width, y: size.height * 0.6))
                ctx.stroke(base, with: .color(Dusk.hairline), lineWidth: 1)
                ctx.stroke(path, with: .color(Dusk.pulse.opacity(0.35)), lineWidth: 1.3)

                let period = 3.2
                let t = moving ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period : fixedPhase
                let total = size.width * 2.1
                let dash: [CGFloat] = [60, total]
                let style = StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: dash, dashPhase: -CGFloat(t) * total + 60)
                var glow = ctx
                glow.addFilter(.shadow(color: Dusk.pulse.opacity(0.9), radius: 4))
                glow.stroke(path, with: .color(Dusk.pulse), style: style)
            }
        }
        .frame(height: 80)
        .accessibilityHidden(true)
    }
}

struct StatRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(Dusk.muted)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 12, design: .monospaced)).foregroundStyle(Dusk.value)
        }
        .font(.system(size: 12))
        .duskTextShadow()
        .accessibilityElement(children: .combine)
    }
}

struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .regular))
            .tracking(2.2)
            .foregroundStyle(Dusk.faint)
            .duskTextShadow()
    }
}

/// The open drawer (Amber Dusk).
struct DrawerPanelView: View {
    @ObservedObject var model: DashboardModel
    var animate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(alignment: .leading, spacing: 10) {
                PulseLine(load: model.cpu ?? 0, animate: animate)
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.longDate(model.now, timeZone: model.homeZone))
                        .font(.system(size: 13)).foregroundStyle(Dusk.value)
                    Spacer(minLength: 8)
                    Text(model.weather?.summary ?? " ")
                        .font(.system(size: 13)).foregroundStyle(Dusk.muted)
                }
                .duskTextShadow()
                if let reason = model.status.reason {
                    Text(reason)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Dusk.coral)
                        .duskTextShadow()
                }
            }
            Divider().overlay(Dusk.hairline)
            VStack(spacing: 10) {
                StatRow(label: "CPU", value: model.cpu.map(Format.percent) ?? "—")
                StatRow(label: "Memory", value: model.memory.map(Format.percent) ?? "—")
                if let b = model.batteryLine { StatRow(label: "Battery", value: b) }
                StatRow(label: "Disk free", value: model.disk.map { Format.gigabytes($0.free) } ?? "—")
                StatRow(label: "Network", value: model.network.map(Format.network) ?? "—")
                StatRow(label: "Temperature", value: model.temperatureLine)
            }
            Divider().overlay(Dusk.hairline)
            MonthCalendar(model: model)
            Divider().overlay(Dusk.hairline)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(text: "Next event")
                    if let e = model.nextEvent {
                        Text(e.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Dusk.text).lineLimit(1)
                        Text(Format.eventWhen(start: e.start, end: e.end, isAllDay: e.isAllDay, now: model.now, timeZone: model.eventZone))
                            .font(.system(size: 12)).foregroundStyle(Dusk.muted)
                    } else if model.calendarOff {
                        Text("Calendar access is off").font(.system(size: 13)).foregroundStyle(Dusk.muted)
                        Text("Turn it on in System Settings › Privacy & Security › Calendars")
                            .font(.system(size: 11)).foregroundStyle(Dusk.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Nothing coming up").font(.system(size: 13)).foregroundStyle(Dusk.muted)
                    }
                }
                .duskTextShadow()
                Button(action: model.toggleFocus) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(text: "Focus timer")
                        Spacer()
                        Text(Format.countdown(model.focus.remaining(at: model.now)))
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(Dusk.amber)
                        Text(model.focus.caption(at: model.now))
                            .font(.system(size: 12)).foregroundStyle(Dusk.muted)
                    }
                    .duskTextShadow()
                    .contentShape(Rectangle())
                    .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Focus timer, \(Format.countdown(model.focus.remaining(at: model.now))) \(model.focus.caption(at: model.now))")
                .accessibilityHint(model.focus.isRunning ? "Pauses the timer" : "Starts the timer")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(width: Dusk.drawerWidth, alignment: .leading)
        .background(GlassBackground(radius: 20))
        .contentShape(TabShape(radius: 20))
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: DrawerHeightKey.self, value: g.size.height) })
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatusDot(attention: model.status.needsAttention, animate: animate)
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                Text(Format.clock(model.now, timeZone: model.homeZone))
                    .font(Self.timeFont)
                    .foregroundStyle(Dusk.text)
                    .tracking(0.6)
                Text("BRUNEI")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .duskTextShadow()
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.clock(model.now, timeZone: model.londonZone))
                    .font(Self.timeFont)
                    .foregroundStyle(Dusk.amber)
                    .tracking(0.6)
                Text("LONDON")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .duskTextShadow()
        }
        .font(.system(size: 11))
        .tracking(1.4)
        .foregroundStyle(Dusk.muted)
    }

    /// The header times: larger and light, like the tab's digits; the city names stay small.
    static let timeFont = Font.system(size: 16, weight: .light).monospacedDigit()
}

/// A small month calendar: today ringed in amber, a dot under days with events,
/// and arrows to look at other months (the month name brings you back to today).
struct MonthCalendar: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        let cal = model.gridCalendar
        let month = model.shownMonth
        let weeks = MonthGrid.weeks(for: month, today: model.now, calendar: cal)
        let title = MonthGrid.title(month, calendar: cal)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                Button { model.showMonth(offset: 0) } label: {
                    SectionLabel(text: title)
                        .frame(minHeight: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.monthOffset == 0 ? "This month" : "Back to this month")
                .accessibilityLabel(title)
                .accessibilityHint(model.monthOffset == 0 ? "" : "Shows this month again")
                Spacer(minLength: 8)
                arrow("chevron.left", label: "Previous month") { model.showMonth(offset: model.monthOffset - 1) }
                arrow("chevron.right", label: "Next month") { model.showMonth(offset: model.monthOffset + 1) }
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(MonthGrid.weekdayInitials(calendar: cal).enumerated()), id: \.offset) { _, letter in
                        Text(letter)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Dusk.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 2)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(week, id: \.date) { day in
                            DayCell(day: day, hasEvents: model.eventDays.contains(day.date))
                        }
                    }
                }
            }
            .duskTextShadow()
        }
    }

    private func arrow(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Dusk.muted)
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct DayCell: View {
    var day: MonthDay
    var hasEvents: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("\(day.day)")
                .font(.system(size: 11, weight: day.isToday ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(day.isToday ? Dusk.amber : (day.inMonth ? Dusk.value : Dusk.faint.opacity(0.55)))
                .frame(width: 22, height: 17)
                .background {
                    if day.isToday {
                        Circle().stroke(Dusk.amber.opacity(0.85), lineWidth: 1).frame(width: 19, height: 19)
                    }
                }
            Circle()
                .fill(hasEvents ? (day.inMonth ? Dusk.amber : Dusk.amberDim.opacity(0.5)) : Color.clear)
                .frame(width: 3, height: 3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.day)\(day.isToday ? ", today" : "")\(hasEvents ? ", has events" : "")")
    }
}

/// What the panel shows: the tab, or the drawer sliding out over it.
struct RootView: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var drawer: DrawerController
    /// Remembered, so the login setting isn't asked of macOS on every redraw.
    @State private var loginOn = false
    @AppStorage("clearGlass") private var clearGlass = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            TabStrip(model: model, animate: model.shouldAnimate && !drawer.showDrawer, glass: !drawer.showDrawer)
                .opacity(drawer.showDrawer ? 0 : 1)
            if drawer.showDrawer {
                DrawerPanelView(model: model, animate: model.shouldAnimate)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { loginOn = LoginItem.isOn }
        .onChange(of: drawer.showDrawer) {
            loginOn = LoginItem.isOn
            // Tucking the drawer away brings the calendar back to this month for next time.
            // Waits for the slide-out to finish, so the grid doesn't change shape mid-animation.
            if !drawer.showDrawer, model.monthOffset != 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !drawer.showDrawer { model.showMonth(offset: 0) }
                }
            }
        }
        .onPreferenceChange(DrawerHeightKey.self) { h in
            Task { @MainActor in drawer.drawerHeightChanged(h) }
        }
        .contextMenu {
            Button(model.focus.isRunning ? "Pause Focus Timer" : "Start Focus Timer") { model.toggleFocus() }
            Button("Reset Focus Timer") { model.resetFocus() }
            Divider()
            Button(drawer.logic.pinned ? "Unpin Drawer" : "Pin Drawer Open") { drawer.togglePin() }
            Toggle("Always on Top", isOn: Binding(get: { drawer.alwaysOnTop }, set: { _ in drawer.toggleAlwaysOnTop() }))
            if #available(macOS 26.0, *) {
                Toggle("Clear Glass", isOn: $clearGlass)
            }
            Button("Refresh Weather and Calendar") {
                model.refreshWeather()
                model.refreshEvent()
            }
            if LoginItem.canOffer {
                Toggle("Open at Login", isOn: Binding(get: { loginOn }, set: { LoginItem.set($0); loginOn = LoginItem.isOn }))
            }
            Divider()
            Button("Quit Mission Control Widget") { NSApp.terminate(nil) }
        }
    }
}
