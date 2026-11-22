import Foundation

/// A calendar event, reduced to what the drawer needs.
public struct CalendarItem: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isCancelled: Bool

    public init(title: String, start: Date, end: Date, isAllDay: Bool, isCancelled: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
    }
}

public enum NextEventRule {
    /// The event to show: the soonest timed event that hasn't ended yet (including one happening now).
    /// All-day events only show when there is no timed event coming up. Cancelled events never show.
    public static func pick(_ items: [CalendarItem], now: Date) -> CalendarItem? {
        let live = items.filter { !$0.isCancelled && $0.end > now }
        let soonest: (CalendarItem, CalendarItem) -> Bool = { a, b in
            if a.start != b.start { return a.start < b.start }
            return a.title < b.title
        }
        if let timed = live.filter({ !$0.isAllDay }).min(by: soonest) { return timed }
        return live.min(by: soonest)
    }

    /// Blank titles read as "Event".
    public static func displayTitle(_ raw: String?) -> String {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Event" : t
    }
}
