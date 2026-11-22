import Foundation

/// One square in the drawer's month calendar.
public struct MonthDay: Equatable, Sendable {
    /// Midnight at the start of this day.
    public var date: Date
    public var day: Int
    /// False for the greyed-out days from the months either side.
    public var inMonth: Bool
    public var isToday: Bool
}

/// The maths behind the little month calendar: which days go in which row, and which days have events.
public enum MonthGrid {
    /// Midnight on the first day of the month `offset` months away from `date` (0 = this month).
    public static func monthStart(of date: Date, offset: Int = 0, calendar: Calendar) -> Date {
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        return calendar.date(byAdding: .month, value: offset, to: first) ?? first
    }

    /// The month as rows of seven days, starting on the calendar's first weekday.
    /// Only as many rows as the month needs (four to six).
    public static func weeks(for month: Date, today: Date, calendar: Calendar) -> [[MonthDay]] {
        let start = monthStart(of: month, calendar: calendar)
        let monthNumber = calendar.component(.month, from: start)
        let daysInMonth = calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        let weekday = calendar.component(.weekday, from: start)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let cells = Int((Double(lead + daysInMonth) / 7).rounded(.up)) * 7
        let todayStart = calendar.startOfDay(for: today)
        var days: [MonthDay] = []
        for i in 0..<cells {
            guard let d = calendar.date(byAdding: .day, value: i - lead, to: start) else { continue }
            let midnight = calendar.startOfDay(for: d)
            days.append(MonthDay(date: midnight,
                                 day: calendar.component(.day, from: midnight),
                                 inMonth: calendar.component(.month, from: midnight) == monthNumber,
                                 isToday: midnight == todayStart))
        }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    /// One-letter weekday headings in calendar order, e.g. M T W T F S S.
    public static func weekdayInitials(calendar: Calendar) -> [String] {
        var symbols = calendar.veryShortStandaloneWeekdaySymbols
        if symbols.count != 7 { symbols = ["S", "M", "T", "W", "T", "F", "S"] }
        let shift = (calendar.firstWeekday - 1 + 7) % 7
        return Array(symbols[shift...] + symbols[..<shift])
    }

    /// "November 2026".
    public static func title(_ month: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: month)
        let names = titleFormatter.standaloneMonthSymbols ?? []
        guard let m = c.month, let y = c.year, (1...names.count).contains(m) else { return "" }
        return "\(names[m - 1]) \(y)"
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    /// Midnights of every day that has at least one event. Multi-day events mark each day they cover;
    /// an event ending exactly at midnight doesn't mark the next day; cancelled events are left out.
    /// Only days from `from` up to (not including) `to` are looked at, so very long events stay cheap.
    public static func eventDays(_ items: [CalendarItem], from: Date, to: Date, calendar: Calendar) -> Set<Date> {
        var out = Set<Date>()
        let windowStart = calendar.startOfDay(for: from)
        for item in items where !item.isCancelled {
            var day = max(calendar.startOfDay(for: item.start), windowStart)
            // The last moment the event actually covers (an end at 00:00 belongs to the day before).
            let last = item.end > item.start ? item.end.addingTimeInterval(-1) : item.start
            while day <= last, day < to {
                out.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                // Re-snap to midnight, in case a clock change skipped it.
                day = calendar.startOfDay(for: next)
            }
        }
        return out
    }
}
