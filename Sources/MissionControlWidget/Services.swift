import Foundation
import AppKit
import EventKit
import ServiceManagement
import MissionCore

/// Reads the next event from the Calendar app (including Google and iCloud calendars added there).
/// Only reads; never changes your calendar. macOS asks permission the first time.
@MainActor
final class CalendarService {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var asked = false
    var onChange: (() -> Void)?

    /// True when the person has turned calendar access off in System Settings.
    var accessDenied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted || s == .writeOnly
    }

    private var authorised: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func start() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined, !asked {
            asked = true
            store.requestFullAccessToEvents { [weak self] _, _ in
                Task { @MainActor in self?.onChange?() }
            }
        } else {
            onChange?()
        }
    }

    /// Checks permission each time, so turning access on or off in System Settings takes effect without a restart.
    func next(after now: Date) -> CalendarItem? {
        guard authorised else { return nil }
        let end = now.addingTimeInterval(14 * 24 * 60 * 60)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-12 * 60 * 60), end: end, calendars: nil)
        let items = store.events(matching: predicate).map {
            CalendarItem(title: NextEventRule.displayTitle($0.title), start: $0.startDate, end: $0.endDate,
                         isAllDay: $0.isAllDay, isCancelled: $0.status == .canceled)
        }
        return NextEventRule.pick(items, now: now)
    }

    /// Every event overlapping the given span, for the month calendar's dots.
    func events(from start: Date, to end: Date) -> [CalendarItem] {
        guard authorised, end > start else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarItem(title: "", start: $0.startDate, end: $0.endDate,
                         isAllDay: $0.isAllDay, isCancelled: $0.status == .canceled)
        }
    }
}

/// Current weather for Bandar Seri Begawan from Open-Meteo (free, no account).
@MainActor
final class WeatherService {
    private var inFlight = false

    /// Calls back with fresh weather, or nil if the request failed.
    func refresh(onDone: @escaping (WeatherNow?) -> Void) {
        guard !inFlight else { return }
        inFlight = true
        var req = URLRequest(url: Weather.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("MissionControlWidget/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let parsed = ok ? data.flatMap { Weather.parse($0, now: Date()) } : nil
            Task { @MainActor in
                self?.inFlight = false
                onDone(parsed)
            }
        }.resume()
    }
}

/// "Open at Login" using the built-in macOS login items.
enum LoginItem {
    /// Login items only work reliably for an app kept in Applications.
    static var canOffer: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    static var isOn: Bool {
        let s = SMAppService.mainApp.status
        return s == .enabled || s == .requiresApproval
    }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Mission Control Widget: login item change failed: \(error.localizedDescription)")
        }
        // macOS sometimes wants the person to allow it in System Settings first.
        if on, SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
