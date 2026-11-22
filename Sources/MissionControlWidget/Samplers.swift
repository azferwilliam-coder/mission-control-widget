import Foundation
import Darwin
import IOKit
import IOKit.ps
import MissionCore

/// One reference to the host port, reused (asking for it every second adds a port reference each time).
private let hostPort = mach_host_self()

/// CPU ticks for every core, straight from the kernel.
enum CPUSampler {
    static func read() -> [CPUTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var result: [CPUTicks] = []
        result.reserveCapacity(Int(cpuCount))
        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(cpuCount) {
            let b = i * stride
            func tick(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[b + Int(state)])) }
            result.append(CPUTicks(user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                                   idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE)))
        }
        return result
    }
}

enum MemorySampler {
    /// Fraction of memory in use, like Activity Monitor's "Memory Used".
    static func read() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let used = MemoryMath.usedBytes(
            internalPages: UInt64(stats.internal_page_count),
            purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count),
            compressedPages: UInt64(stats.compressor_page_count),
            pageSize: UInt64(vm_kernel_page_size))
        return MemoryMath.usedFraction(usedBytes: used, totalBytes: ProcessInfo.processInfo.physicalMemory)
    }
}

struct BatteryReading: Equatable {
    var level: Double
    var charging: Bool
    var onPower: Bool
}

enum BatterySampler {
    /// nil on a Mac without a battery (iMac, Mac mini, Mac Studio).
    static func read() -> BatteryReading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            guard let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            let onPower = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return BatteryReading(level: Double(cur) / Double(max), charging: charging, onPower: onPower)
        }
        return nil
    }
}

struct DiskReading: Equatable {
    var free: Int64
    var total: Int64
}

enum DiskSampler {
    static func read() -> DiskReading? {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let free = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity else { return nil }
        return DiskReading(free: free, total: Int64(total))
    }
}

enum NetworkSampler {
    /// Bytes in and out for each Wi-Fi and Ethernet interface, using the kernel's 64-bit counters.
    static func read(now: TimeInterval) -> NetSample? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, UInt32(mib.count), &buf, &len, nil, 0) == 0 else { return nil }
        var interfaces: [String: InterfaceBytes] = [:]
        var offset = 0
        buf.withUnsafeBytes { raw in
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let base = raw.baseAddress!.advanced(by: offset)
                let hdr = base.loadUnaligned(as: if_msghdr.self)
                let msgLen = Int(hdr.ifm_msglen)
                guard msgLen > 0 else { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = base.loadUnaligned(as: if_msghdr2.self)
                    let up = (h2.ifm_flags & IFF_UP) != 0
                    let loop = (h2.ifm_flags & IFF_LOOPBACK) != 0
                    if up, !loop {
                        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                        if if_indextoname(UInt32(h2.ifm_index), &name) != nil {
                            let n = String(cString: name)
                            if NetworkMath.isCountedInterface(n) {
                                interfaces[n] = InterfaceBytes(bytesIn: h2.ifm_data.ifi_ibytes, bytesOut: h2.ifm_data.ifi_obytes)
                            }
                        }
                    }
                }
                offset += msgLen
            }
        }
        return NetSample(interfaces: interfaces, time: now)
    }
}

enum ThermalSampler {
    static func read() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .nominal
        }
    }
}
