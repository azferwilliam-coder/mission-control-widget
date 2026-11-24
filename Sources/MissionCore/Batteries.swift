import Foundation

// MARK: - Device batteries
//
// The rings at the bottom of the drawer: this Mac, plus Bluetooth devices that tell macOS their charge
// (Magic Mouse, Keyboard and Trackpad; AirPods and Beats). iPhone and Apple Watch are not included,
// because a Mac app can't read them reliably. Nothing here is ever guessed: a device with no reading is left out.

public enum DeviceKind: Int, Sendable, CaseIterable, Comparable {
    case mac = 0, headphones, mouse, keyboard, trackpad, other

    public static func < (a: DeviceKind, b: DeviceKind) -> Bool { a.rawValue < b.rawValue }

    /// The short word under the ring.
    public var shortName: String {
        switch self {
        case .mac: return "Mac"
        case .headphones: return "Pods"
        case .mouse: return "Mouse"
        case .keyboard: return "Keys"
        case .trackpad: return "Pad"
        case .other: return "Other"
        }
    }

    /// Works out the kind from what macOS calls the device (its name and, when known, its type).
    public static func guess(name: String, type: String? = nil) -> DeviceKind {
        let t = (type ?? "").lowercased()
        let n = name.lowercased()
        func has(_ words: [String], _ s: String) -> Bool { words.contains { s.contains($0) } }
        if has(["headphone", "headset", "earbud", "audio"], t) { return .headphones }
        if has(["mouse"], t) { return .mouse }
        if has(["keyboard"], t) { return .keyboard }
        if has(["trackpad", "touchpad"], t) { return .trackpad }
        if has(["airpods", "beats", "headphone", "earbuds", "buds"], n) { return .headphones }
        if has(["trackpad"], n) { return .trackpad }
        if has(["mouse"], n) { return .mouse }
        if has(["keyboard"], n) { return .keyboard }
        return .other
    }
}

/// One part of a device with its own battery, such as an AirPods earbud or the case.
public struct BatteryPart: Equatable, Sendable {
    public var label: String
    public var level: Double

    public init(label: String, level: Double) {
        self.label = label
        self.level = level
    }
}

public struct DeviceBattery: Equatable, Sendable, Identifiable {
    public var name: String
    public var kind: DeviceKind
    /// 0...1. For AirPods, the lower of the two earbuds (the case doesn't count, as it isn't in your ears).
    public var level: Double
    public var charging: Bool
    /// Left, right and case for AirPods; empty for single-battery devices.
    public var parts: [BatteryPart]

    public var id: String { "\(kind.rawValue)|\(BatteryRules.matchKey(name))" }

    public init(name: String, kind: DeviceKind, level: Double, charging: Bool = false, parts: [BatteryPart] = []) {
        self.name = BatteryRules.shortName(name)
        self.kind = kind
        self.level = min(1, max(0, level))
        self.charging = charging
        self.parts = parts
    }

    /// Low means 20% or less and not on charge, the same rule as the Mac's own battery.
    public var isLow: Bool { level <= StatusRules.lowBattery && !charging }

    /// The words shown when you hover a ring, e.g. "AirPods Pro: Left 72%, Right 70%, Case 45%".
    public var detail: String {
        let pct = { (v: Double) in "\(Int((v * 100).rounded()))%" }
        if parts.isEmpty { return "\(name): \(pct(level))\(charging ? ", charging" : "")" }
        return "\(name): " + parts.map { "\($0.label) \(pct($0.level))" }.joined(separator: ", ")
    }
}

public enum BatteryRules {
    /// How many rings fit across the 300 pt drawer.
    public static let maxShown = 5

    /// "Azfer’s Magic Mouse" becomes "Magic Mouse", so names fit under the ring and in the warning.
    public static func shortName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        for mark in ["’s ", "'s "] {
            if let r = trimmed.range(of: mark) {
                let rest = trimmed[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { return rest }
            }
        }
        return trimmed
    }

    /// "Azfer’s Magic Mouse" and "Azfer's Magic Mouse" are the same device.
    public static func matchKey(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .filter { !$0.isWhitespace }
    }

    /// A percentage as macOS writes it ("72%", "72" or 72) as 0...1, or nil if it isn't a real reading.
    public static func level(from value: Any?) -> Double? {
        var number: Double?
        if let i = value as? Int { number = Double(i) }
        else if let d = value as? Double { number = d }
        else if let s = value as? String {
            let digits = s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            number = Double(digits)
        }
        guard let n = number, n.isFinite, n >= 0, n <= 100 else { return nil }
        return n / 100
    }

    /// Reads one Bluetooth device's entry from `system_profiler SPBluetoothDataType -json`.
    /// Returns nil when it carries no battery numbers.
    public static func fromProfiler(name: String, info: [String: Any]) -> DeviceBattery? {
        let left = level(from: info["device_batteryLevelLeft"])
        let right = level(from: info["device_batteryLevelRight"])
        let box = level(from: info["device_batteryLevelCase"])
        let main = level(from: info["device_batteryLevelMain"]) ?? level(from: info["device_batteryLevel"])
        let kind = DeviceKind.guess(name: name, type: info["device_minorType"] as? String)

        var parts: [BatteryPart] = []
        if let l = left { parts.append(BatteryPart(label: "Left", level: l)) }
        if let r = right { parts.append(BatteryPart(label: "Right", level: r)) }
        if let c = box { parts.append(BatteryPart(label: "Case", level: c)) }

        // An earbud out of the case can report 0%; ignore it when the other one has charge.
        var buds = [left, right].compactMap { $0 }
        if buds.count == 2, buds.contains(0), buds.contains(where: { $0 > 0 }) { buds = buds.filter { $0 > 0 } }
        let overall: Double
        if let lowest = buds.min() { overall = lowest }
        else if let m = main { overall = m }
        else if let c = box { overall = c }   // only the case is reporting
        else { return nil }
        // A single main reading needs no breakdown.
        if buds.isEmpty && box == nil { parts = [] }
        return DeviceBattery(name: name, kind: kind == .other && !buds.isEmpty ? .headphones : kind,
                             level: overall, charging: false, parts: parts)
    }

    /// Reads the connected devices out of the whole `system_profiler SPBluetoothDataType -json` output.
    public static func parseProfiler(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [DeviceBattery] = []
        for c in controllers {
            // Newer macOS: "device_connected"; older: "device_title" holding every paired device with a connected flag.
            let lists = [c["device_connected"], c["devices_connected"], c["device_title"]].compactMap { $0 as? [[String: Any]] }
            for list in lists {
                for entry in list {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any] else { continue }
                        if let flag = info["device_isconnected"] as? String, flag.lowercased().contains("no") { continue }
                        if let flag = info["device_connected"] as? String, flag.lowercased().contains("no") { continue }
                        if let d = fromProfiler(name: name, info: info) { out.append(d) }
                    }
                }
            }
        }
        return out
    }

    /// Reads one Bluetooth accessory from the IOKit registry (Magic Mouse, Keyboard, Trackpad).
    public static func fromRegistry(_ props: [String: Any]) -> DeviceBattery? {
        guard let name = (props["Product"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let lvl = level(from: props["BatteryPercent"]) else { return nil }
        // Built-in keyboards and trackpads have no battery of their own, and never report BatteryPercent.
        return DeviceBattery(name: name, kind: DeviceKind.guess(name: name), level: lvl, charging: false)
    }

    /// Joins the readings into the rings to show: the Mac first, then headphones, mouse, keyboard, trackpad.
    /// The same device found twice is shown once (the registry reading wins, it's fresher).
    /// If there are more than fit, the fullest ones drop off first, so a low device is never hidden.
    public static func combine(mac: DeviceBattery?, registry: [DeviceBattery], profiler: [DeviceBattery]) -> [DeviceBattery] {
        var seen = Set<String>()
        var list: [DeviceBattery] = []
        for d in registry + profiler {
            let key = matchKey(d.name)
            if seen.contains(key) {
                // Keep the first reading, but learn the kind from System Information if the name didn't say.
                if let i = list.firstIndex(where: { matchKey($0.name) == key }), list[i].kind == .other, d.kind != .other {
                    list[i].kind = d.kind
                }
                continue
            }
            seen.insert(key)
            list.append(d)
        }
        list.sort { a, b in a.kind != b.kind ? a.kind < b.kind : a.name.localizedStandardCompare(b.name) == .orderedAscending }
        let room = maxShown - (mac == nil ? 0 : 1)
        while list.count > room, let fullest = list.indices.max(by: { list[$0].level < list[$1].level }) {
            list.remove(at: fullest)
        }
        return (mac.map { [$0] } ?? []) + list
    }

    /// The accessory that most needs charging, if any is low. (The Mac's own battery has its own rule.)
    public static func lowestAccessory(_ devices: [DeviceBattery]) -> DeviceBattery? {
        devices.filter { $0.kind != .mac && $0.isLow }.min { $0.level < $1.level }
    }
}
