import Foundation

/// How warm the Mac says it is (mirrors ProcessInfo.ThermalState, kept here so it can be tested on any platform).
public enum ThermalLevel: Int, Sendable, Comparable {
    case nominal = 0, fair, serious, critical

    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }

    public var word: String {
        switch self {
        case .nominal: return "Cool"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Very hot"
        }
    }
}

/// Everything the status dot needs to decide whether something wants your attention.
public struct StatusInputs: Sendable {
    public var cpu: Double?
    public var memory: Double?
    public var batteryLevel: Double?
    public var batteryCharging: Bool
    public var diskFreeFraction: Double?
    public var thermal: ThermalLevel
    public var focusJustFinished: Bool
    /// The name of a Bluetooth device (mouse, keyboard, AirPods) at 20% or less, if any.
    public var lowDevice: String?

    public init(cpu: Double? = nil, memory: Double? = nil, batteryLevel: Double? = nil, batteryCharging: Bool = false,
                diskFreeFraction: Double? = nil, thermal: ThermalLevel = .nominal, focusJustFinished: Bool = false,
                lowDevice: String? = nil) {
        self.cpu = cpu
        self.memory = memory
        self.batteryLevel = batteryLevel
        self.batteryCharging = batteryCharging
        self.diskFreeFraction = diskFreeFraction
        self.thermal = thermal
        self.focusJustFinished = focusJustFinished
        self.lowDevice = lowDevice
    }
}

public enum Status: Equatable, Sendable {
    case calm
    case attention(String)

    public var needsAttention: Bool {
        if case .attention = self { return true }
        return false
    }

    public var reason: String? {
        if case .attention(let r) = self { return r }
        return nil
    }
}

public enum StatusRules {
    public static let lowBattery = 0.20
    public static let lowDisk = 0.10
    public static let busyCPU = 0.90
    public static let fullMemory = 0.92

    /// The most important reason first. Amber dot when calm, coral when something needs you.
    public static func evaluate(_ i: StatusInputs) -> Status {
        if i.thermal >= .serious { return .attention("Running \(i.thermal.word.lowercased())") }
        if let b = i.batteryLevel, b <= lowBattery, !i.batteryCharging { return .attention("Battery low") }
        if let d = i.diskFreeFraction, d < lowDisk { return .attention("Disk nearly full") }
        if i.focusJustFinished { return .attention("Focus done") }
        if let name = i.lowDevice { return .attention("\(name) battery low") }
        if let m = i.memory, m >= fullMemory { return .attention("Memory full") }
        if let c = i.cpu, c >= busyCPU { return .attention("Working hard") }
        return .calm
    }
}

/// Smooths a jumpy reading so the CPU-busy alert needs a sustained spike, not one busy second.
public struct Smoother: Sendable {
    public private(set) var value: Double?
    public let weight: Double

    public init(weight: Double = 0.25) {
        self.weight = min(1, max(0.01, weight))
    }

    public mutating func add(_ sample: Double) -> Double {
        let v = value.map { $0 + (sample - $0) * weight } ?? sample
        value = v
        return v
    }
}
