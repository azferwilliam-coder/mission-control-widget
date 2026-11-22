import Foundation

public enum Format {
    /// 0.234 → "23%"
    public static func percent(_ fraction: Double) -> String {
        let clamped = min(1, max(0, fraction.isFinite ? fraction : 0))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// Bytes → "312 GB" (decimal units, like Finder). Under 10 GB shows one decimal: "8.4 GB".
    public static func gigabytes(_ bytes: Int64) -> String {
        let gb = Double(max(0, bytes)) / 1_000_000_000
        if gb.rounded() >= 1000 {
            return String(format: "%.1f TB", gb / 1000)
        }
        if gb < 10 {
            return String(format: "%.1f GB", gb)
        }
        return "\(Int(gb.rounded())) GB"
    }

    /// Bits per second → "84.2" in Mbps, or "512" kbps shown as "0.5".
    public static func mbps(_ bitsPerSecond: Double) -> String {
        let m = max(0, bitsPerSecond.isFinite ? bitsPerSecond : 0) / 1_000_000
        if m >= 100 { return "\(Int(m.rounded()))" }
        return String(format: "%.1f", m)
    }

    /// "↓ 84.2  ↑ 12.6 Mbps"
    public static func network(_ rate: NetRate) -> String {
        "↓ \(mbps(rate.down))  ↑ \(mbps(rate.up)) Mbps"
    }

    /// Hours and minutes of a moment in a given time zone, each two digits: ("21", "47").
    public static func clockParts(_ date: Date, timeZone: TimeZone) -> (hours: String, minutes: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return (String(format: "%02d", c.hour ?? 0), String(format: "%02d", c.minute ?? 0))
    }

    /// "21:47"
    public static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let p = clockParts(date, timeZone: timeZone)
        return "\(p.hours):\(p.minutes)"
    }

    /// Seconds → "18:42" (minutes:seconds), rounding up so a timer never shows 00:00 early.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds).rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// "Saturday 21 November"
    public static func longDate(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = timeZone
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    /// Celsius → "48°"
    public static func degrees(_ celsius: Double) -> String {
        let c = celsius.isFinite ? min(999, max(-999, celsius)) : 0
        return "\(Int(c.rounded()))°"
    }

    /// 1850 → "1,850 rpm"
    public static func rpm(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let v = value.isFinite ? min(99_999, max(0, value)) : 0
        let n = f.string(from: NSNumber(value: Int(v.rounded()))) ?? "\(Int(v))"
        return "\(n) rpm"
    }

    /// When an event starts, said simply: "Now", "Today, 6:30 PM", "Tomorrow, 6:30 PM", "Monday, 9:00 AM", "Fri 28 Nov, 9:00 AM".
    public static func eventWhen(start: Date, end: Date, isAllDay: Bool, now: Date, timeZone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        if start <= now && end > now { return isAllDay ? "Today, all day" : "Now" }
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_GB")
        time.timeZone = timeZone
        time.dateFormat = "h:mm a"
        time.amSymbol = "AM"
        time.pmSymbol = "PM"
        let t = isAllDay ? "all day" : time.string(from: start)
        let today = cal.startOfDay(for: now)
        let day = cal.startOfDay(for: start)
        let diff = cal.dateComponents([.day], from: today, to: day).day ?? 0
        switch diff {
        case 0: return "Today, \(t)"
        case 1: return "Tomorrow, \(t)"
        case 2...6:
            let wd = DateFormatter()
            wd.locale = Locale(identifier: "en_GB")
            wd.timeZone = timeZone
            wd.dateFormat = "EEEE"
            return "\(wd.string(from: start)), \(t)"
        default:
            let d = DateFormatter()
            d.locale = Locale(identifier: "en_GB")
            d.timeZone = timeZone
            d.dateFormat = "EEE d MMM"
            return "\(d.string(from: start)), \(t)"
        }
    }
}
