import Foundation
import IOKit
import MissionCore

/// Reads temperature and fan speed from the Mac's System Management Controller.
/// Apple has no public way to do this, so it uses the same read-only AppleSMC calls as well-known
/// monitoring apps. Nothing is ever written. If anything looks wrong it quietly turns itself off.
final class SMC {
    // Mirrors the C struct SMCKeyData_t (80 bytes). The padding field keeps Swift's layout equal to C's.
    private struct KeyData {
        struct Vers { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
        struct PLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var mem: UInt32 = 0 }
        struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0 }
        var key: UInt32 = 0
        var vers = Vers()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleYPCEvent: UInt32 = 2
    private static let cmdReadKey: UInt8 = 5
    private static let cmdGetKeyInfo: UInt8 = 9

    private var connection: io_connect_t = 0
    private var infoCache: [UInt32: KeyData.KeyInfo] = [:]
    private var missing: Set<UInt32> = []
    private(set) var available = false

    init() {
        // Only trust the layout if it is exactly the size the driver expects.
        guard MemoryLayout<KeyData>.stride == 80,
              MemoryLayout<KeyData>.offset(of: \KeyData.keyInfo) == 28,
              MemoryLayout<KeyData>.offset(of: \KeyData.result) == 40,
              MemoryLayout<KeyData>.offset(of: \KeyData.data8) == 42,
              MemoryLayout<KeyData>.offset(of: \KeyData.data32) == 44,
              MemoryLayout<KeyData>.offset(of: \KeyData.bytes) == 48 else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        available = IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    private static let keyNotFound: UInt8 = 0x84

    /// The driver's answer, or nil if the call itself failed (for example just after wake).
    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outSize = MemoryLayout<KeyData>.stride
        let kr = IOConnectCallStructMethod(connection, SMC.handleYPCEvent, &input, MemoryLayout<KeyData>.stride, &output, &outSize)
        guard kr == kIOReturnSuccess else { return nil }
        return output
    }

    func value(_ key: String) -> Double? {
        guard available else { return nil }
        let code = SMCDecode.fourCC(key)
        if missing.contains(code) { return nil }
        let info: KeyData.KeyInfo
        if let cached = infoCache[code] {
            info = cached
        } else {
            var q = KeyData()
            q.key = code
            q.data8 = SMC.cmdGetKeyInfo
            guard let r = call(&q) else { return nil }   // try again next time
            guard r.result == 0, r.keyInfo.dataSize > 0, r.keyInfo.dataSize <= 32 else {
                // Only forget a key this Mac really doesn't have.
                if r.result == SMC.keyNotFound || r.result == 0 { missing.insert(code) }
                return nil
            }
            info = r.keyInfo
            infoCache[code] = info
        }
        var q = KeyData()
        q.key = code
        q.keyInfo.dataSize = info.dataSize
        q.data8 = SMC.cmdReadKey
        guard let r = call(&q), r.result == 0 else { return nil }
        let bytes = withUnsafeBytes(of: r.bytes) { Array($0.prefix(Int(info.dataSize))) }
        return SMCDecode.decode(type: SMCDecode.string(info.dataType), bytes: bytes)
    }

    /// Average CPU temperature in °C, if this Mac exposes any sensors we know.
    func cpuTemperature() -> Double? {
        SMCDecode.averageTemperature(SMCDecode.temperatureKeys.compactMap { value($0) })
    }

    /// First fan's speed, or nil on fanless Macs.
    func fanSpeed() -> Double? {
        guard let count = value("FNum"), count >= 1 else { return nil }
        return SMCDecode.plausibleFan(value("F0Ac"))
    }
}
