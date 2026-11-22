import Foundation

/// Turns the raw bytes the Mac's System Management Controller returns into numbers.
/// Apple Silicon reports most sensors as little-endian 32-bit floats ("flt "); Intel Macs use fixed-point types.
public enum SMCDecode {
    /// "TC0P" → 0x54433050
    public static func fourCC(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for b in s.utf8.prefix(4) { v = (v << 8) | UInt32(b) }
        return v
    }

    /// 0x54433050 → "TC0P"
    public static func string(_ code: UInt32) -> String {
        let bytes = [UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF), UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF)]
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            let f = Double(Float(bitPattern: bits))
            return f.isFinite ? f : nil
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            return Double(raw) / 4
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return nil
        }
    }

    /// Temperature sensor keys across Intel and M1–M4 Macs. Missing keys are simply skipped.
    public static let temperatureKeys: [String] = [
        // Intel CPU
        "TC0P", "TC0D", "TC0E", "TC0F",
        // M1
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp0n",
        // M2
        "Tp1h", "Tp1t", "Tp1p", "Tp1l",
        // M3 / M4
        "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E",
    ]

    /// Average of plausible CPU readings, or nil if none look real.
    public static func averageTemperature(_ readings: [Double]) -> Double? {
        let ok = readings.filter { $0.isFinite && $0 > 10 && $0 < 115 }
        guard !ok.isEmpty else { return nil }
        return ok.reduce(0, +) / Double(ok.count)
    }

    /// A fan speed worth showing (fanless Macs and stopped fans report 0).
    public static func plausibleFan(_ rpm: Double?) -> Double? {
        guard let r = rpm, r.isFinite, r >= 0, r < 12000 else { return nil }
        return r
    }
}
