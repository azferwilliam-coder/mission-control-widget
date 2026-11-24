import Foundation
import AppKit
import MissionCore

/// Everything the drawer shows, refreshed on timers.
@MainActor
final class DashboardModel: ObservableObject {
    @Published var now = Date()
    @Published var cpu: Double?
    @Published var memory: Double?
    @Published var battery: BatteryReading?
    @Published var disk: DiskReading?
    @Published var network: NetRate?
    @Published var temperature: Double?
    @Published var fan: Double?
    @Published var thermal: ThermalLevel = .nominal
    @Published var weather: WeatherNow?
    @Published var nextEvent: CalendarItem?
    @Published var calendarOff = false
    /// Which month the drawer's calendar shows: 0 = this month, -1 = last month, and so on.
    @Published var monthOffset = 0
    /// Midnights of days in the shown month (and its edges) that have events.
    @Published var eventDays: Set<Date> = []
    /// False while the screens are asleep, so animations can stop.
    @Published var screensAwake = true
    /// False while the widget is completely covered by other windows, so animations can stop too.
    @Published var widgetVisible = true
    var shouldAnimate: Bool { screensAwake && widgetVisible }
    @Published var focus = FocusTimer()
    @Published private(set) var status: Status = .calm

    let homeZone = TimeZone(identifier: "Asia/Brunei") ?? .current
    let londonZone = TimeZone(identifier: "Europe/London") ?? TimeZone(secondsFromGMT: 0)!
    /// Event times follow the Mac's own clock, like the Calendar app.
    var eventZone = TimeZone.current { didSet { gridCalendar = Self.makeGridCalendar(eventZone) } }

    /// The calendar used for the month grid: the Mac's own time zone and first day of the week.
    private(set) var gridCalendar = DashboardModel.makeGridCalendar(.current)

    nonisolated private static func makeGridCalendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = Calendar.autoupdatingCurrent.firstWeekday
        return c
    }
    var shownMonth: Date { MonthGrid.monthStart(of: now, offset: monthOffset, calendar: gridCalendar) }
    private var eventDaysKey: Date?

    private var previousTicks: [CPUTicks] = []
    private var previousNet: NetSample?
    private var weatherRetryAt: Date?
    private var cpuSmooth = Smoother(weight: 0.2)
    private var smc: SMC?
    private var timers: [Timer] = []
    private let calendar = CalendarService()
    private let weatherService = WeatherService()
    private var tickCount = 0

    /// Sample data used for screenshots, so they never show anything personal.
    static func demo() -> DashboardModel {
        let m = DashboardModel()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = m.homeZone
        m.now = cal.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 21, minute: 47)) ?? Date()
        m.cpu = 0.23
        m.memory = 0.61
        m.battery = BatteryReading(level: 0.84, charging: true, onPower: true)
        m.disk = DiskReading(free: 312_000_000_000, total: 994_000_000_000)
        m.network = NetRate(down: 84_200_000, up: 12_600_000)
        m.temperature = 48
        m.fan = 1850
        m.weather = WeatherNow(celsius: 29, code: 80, fetchedAt: m.now)
        let runStart = cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 18, minute: 30)) ?? m.now
        m.nextEvent = CalendarItem(title: "Evening Run", start: runStart,
                                   end: runStart.addingTimeInterval(3600), isAllDay: false)
        m.eventZone = m.homeZone
        m.eventDays = [3, 9, 14, 22, 25, 26, 28].compactMap {
            cal.date(from: DateComponents(year: 2026, month: 11, day: $0))
        }.reduce(into: Set<Date>()) { $0.insert($1) }
        m.focus = FocusTimer()
        m.focus.toggle(at: m.now.addingTimeInterval(-(25 * 60 - (18 * 60 + 42))))
        m.recomputeStatus()
        return m
    }

    func start() {
        smc = SMC()
        sampleFast()
        sampleSlow()
        calendar.onChange = { [weak self] in self?.refreshEvent() }
        calendar.start()
        refreshWeather()

        let fast = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        fast.tolerance = 0.2
        RunLoop.main.add(fast, forMode: .common)
        timers.append(fast)

        // Catch up straight after the Mac wakes.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.previousNet = nil
                self?.previousTicks = []
                self?.sampleSlow()
                self?.refreshWeather()
                self?.refreshEvent()
            }
        }
        // Follow the Mac's time zone when it changes (travelling), for event times and the calendar.
        NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.eventZone = .current
                self?.now = Date()
                self?.refreshEvent()
            }
        }
        // Stop animating while the displays sleep.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensAwake = false }
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screensAwake = true }
        }
    }

    /// Called every second by the window, so it can double-check the pointer.
    var onTick: (() -> Void)?

    private func tick() {
        tickCount += 1
        now = Date()
        sampleFast()
        // Only chime if it finished just now, not if it ran out while the Mac was asleep.
        if focus.tick(at: now), focus.justFinished(at: now) {
            NSSound(named: "Glass")?.play()
        }
        if tickCount % 10 == 0 { sampleSlow() }
        if tickCount % 300 == 0 { refreshEvent() } else if eventDaysKey != shownMonth { refreshEventDays() }
        // Move on as soon as the shown event ends, rather than at the next five-minute check.
        if let e = nextEvent, now >= e.end { refreshEvent() }
        if tickCount % (20 * 60) == 0 { refreshWeather() }
        if let r = weatherRetryAt, now >= r { weatherRetryAt = nil; refreshWeather() }
        if let w = weather, !Weather.isFresh(w, now: now) { weather = nil }
        recomputeStatus()
        onTick?()
    }

    private func sampleFast() {
        let ticks = CPUSampler.read()
        if let u = CPUMath.usage(previous: previousTicks, current: ticks) {
            cpu = cpuSmooth.add(u)
        }
        previousTicks = ticks
        memory = MemorySampler.read() ?? memory

        let t = ProcessInfo.processInfo.systemUptime
        if let c = NetworkSampler.read(now: t) {
            if let p = previousNet, let r = NetworkMath.rate(previous: p, current: c) { network = r }
            previousNet = c
        }
    }

    private func sampleSlow() {
        battery = BatterySampler.read()
        disk = DiskSampler.read() ?? disk
        thermal = ThermalSampler.read()
        temperature = smc?.cpuTemperature()
        fan = smc?.fanSpeed()
    }

    func refreshWeather() {
        weatherService.refresh { [weak self] w in
            guard let self else { return }
            if let w {
                self.weather = w
            } else {
                // Try again in a minute rather than waiting 20.
                self.weatherRetryAt = Date().addingTimeInterval(60)
            }
        }
    }

    func refreshEvent() {
        nextEvent = calendar.next(after: Date())
        calendarOff = calendar.accessDenied
        refreshEventDays()
    }

    /// Reloads the dots for the month on show, covering the greyed days either side too.
    func refreshEventDays() {
        let c = gridCalendar
        let weeks = MonthGrid.weeks(for: shownMonth, today: now, calendar: c)
        guard let first = weeks.first?.first?.date, let lastDay = weeks.last?.last?.date,
              let end = c.date(byAdding: .day, value: 1, to: lastDay) else { return }
        eventDays = MonthGrid.eventDays(calendar.events(from: first, to: end), from: first, to: end, calendar: c)
        eventDaysKey = shownMonth
    }

    func showMonth(offset: Int) {
        monthOffset = max(-120, min(120, offset))
        now = Date()
        refreshEventDays()
    }

    func toggleFocus() {
        now = Date()
        focus.toggle(at: now)
        recomputeStatus()
    }

    func resetFocus() {
        focus.reset()
        recomputeStatus()
    }

    func recomputeStatus() {
        status = StatusRules.evaluate(StatusInputs(
            cpu: cpu, memory: memory,
            batteryLevel: battery?.level, batteryCharging: battery?.charging ?? false,
            diskFreeFraction: disk.map { DiskMath.freeFraction(free: $0.free, total: $0.total) },
            thermal: thermal,
            focusJustFinished: focus.justFinished(at: now)))
    }

    // MARK: Words for the drawer

    var temperatureLine: String {
        var parts: [String] = []
        if let t = temperature { parts.append(Format.degrees(t)) } else { parts.append(thermal.word) }
        if let f = fan, f > 0 { parts.append(Format.rpm(f)) }
        return parts.joined(separator: " · ")
    }

    var batteryLine: String? {
        guard let b = battery else { return nil }
        let p = Format.percent(b.level)
        if b.charging { return "\(p) charging" }
        return p
    }
}
