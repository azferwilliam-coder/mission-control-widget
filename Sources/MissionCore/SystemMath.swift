import Foundation

/// Raw CPU tick counters for one core, as the kernel reports them.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum CPUMath {
    /// Share of time all cores were busy between two samples, 0...1.
    /// Returns nil when there is nothing to compare (first sample, core count changed, or no time passed).
    public static func usage(previous: [CPUTicks], current: [CPUTicks]) -> Double? {
        guard !previous.isEmpty, previous.count == current.count else { return nil }
        var busy: UInt64 = 0
        var total: UInt64 = 0
        for (p, c) in zip(previous, current) {
            // Counters only go up; if one went backwards (sleep/wake reset) skip that core.
            guard c.user >= p.user, c.system >= p.system, c.idle >= p.idle, c.nice >= p.nice else { continue }
            let b = (c.user - p.user) + (c.system - p.system) + (c.nice - p.nice)
            let i = c.idle - p.idle
            busy += b
            total += b + i
        }
        guard total > 0 else { return nil }
        return min(1, max(0, Double(busy) / Double(total)))
    }
}

public enum MemoryMath {
    /// "Memory used" the way Activity Monitor counts it: app memory + wired + compressed.
    public static func usedBytes(internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64,
                                 compressedPages: UInt64, pageSize: UInt64) -> UInt64 {
        let app = internalPages > purgeablePages ? internalPages - purgeablePages : 0
        return (app + wiredPages + compressedPages) * pageSize
    }

    public static func usedFraction(usedBytes: UInt64, totalBytes: UInt64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

/// Total bytes received and sent by the network interfaces at one moment.
public struct NetCounters: Equatable, Sendable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var time: TimeInterval

    public init(bytesIn: UInt64, bytesOut: UInt64, time: TimeInterval) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.time = time
    }
}

public struct NetRate: Equatable, Sendable {
    /// Bits per second.
    public var down: Double
    public var up: Double

    public init(down: Double, up: Double) {
        self.down = down
        self.up = up
    }

    public static let zero = NetRate(down: 0, up: 0)
}

/// Bytes received and sent by one network interface.
public struct InterfaceBytes: Equatable, Sendable {
    public var bytesIn: UInt64
    public var bytesOut: UInt64

    public init(bytesIn: UInt64, bytesOut: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Per-interface counters at one moment.
public struct NetSample: Equatable, Sendable {
    public var interfaces: [String: InterfaceBytes]
    public var time: TimeInterval

    public init(interfaces: [String: InterfaceBytes], time: TimeInterval) {
        self.interfaces = interfaces
        self.time = time
    }
}

public enum NetworkMath {
    /// Speed between two samples. A counter that went backwards (interface reset, Wi-Fi change) counts as 0.
    public static func rate(previous: NetCounters, current: NetCounters) -> NetRate? {
        let dt = current.time - previous.time
        guard dt > 0.05 else { return nil }
        let dIn = current.bytesIn >= previous.bytesIn ? current.bytesIn - previous.bytesIn : 0
        let dOut = current.bytesOut >= previous.bytesOut ? current.bytesOut - previous.bytesOut : 0
        return NetRate(down: Double(dIn) * 8 / dt, up: Double(dOut) * 8 / dt)
    }

    /// Speed across interfaces, counting only interfaces present in both samples, so a dock or
    /// iPhone tether coming online doesn't add its lifetime total as one giant spike.
    public static func rate(previous: NetSample, current: NetSample) -> NetRate? {
        let dt = current.time - previous.time
        guard dt > 0.05 else { return nil }
        var dIn: UInt64 = 0
        var dOut: UInt64 = 0
        for (name, c) in current.interfaces {
            guard let p = previous.interfaces[name] else { continue }
            dIn &+= c.bytesIn >= p.bytesIn ? c.bytesIn - p.bytesIn : 0
            dOut &+= c.bytesOut >= p.bytesOut ? c.bytesOut - p.bytesOut : 0
        }
        return NetRate(down: Double(dIn) * 8 / dt, up: Double(dOut) * 8 / dt)
    }

    /// Only real network hardware (Wi-Fi and Ethernet), so VPN tunnels and AirDrop links aren't counted twice.
    public static func isCountedInterface(_ name: String) -> Bool {
        name.hasPrefix("en")
    }
}

public enum DiskMath {
    public static func freeFraction(free: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(free) / Double(total)))
    }
}
