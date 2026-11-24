import XCTest
@testable import MissionCore

final class SystemMathTests: XCTestCase {
    func testCPUUsageAcrossCores() {
        let a = [CPUTicks(user: 100, system: 50, idle: 850, nice: 0), CPUTicks(user: 0, system: 0, idle: 1000, nice: 0)]
        let b = [CPUTicks(user: 200, system: 100, idle: 900, nice: 0), CPUTicks(user: 0, system: 0, idle: 1200, nice: 0)]
        // busy = 150 of (150 + 50 + 200) = 0.375
        XCTAssertEqual(CPUMath.usage(previous: a, current: b)!, 0.375, accuracy: 1e-9)
    }

    func testCPUUsageNeedsTwoMatchingSamples() {
        let one = [CPUTicks(user: 1, system: 1, idle: 1, nice: 0)]
        XCTAssertNil(CPUMath.usage(previous: [], current: one))
        XCTAssertNil(CPUMath.usage(previous: one, current: one + one))
        XCTAssertNil(CPUMath.usage(previous: one, current: one), "no time passed")
    }

    func testCPUCounterGoingBackwardsIsSkipped() {
        let a = [CPUTicks(user: 500, system: 0, idle: 500, nice: 0), CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let b = [CPUTicks(user: 10, system: 0, idle: 10, nice: 0), CPUTicks(user: 50, system: 0, idle: 50, nice: 0)]
        XCTAssertEqual(CPUMath.usage(previous: a, current: b)!, 0.5, accuracy: 1e-9)
    }

    func testCPUUsageStaysInRange() {
        let a = [CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let b = [CPUTicks(user: 10, system: 10, idle: 0, nice: 10)]
        XCTAssertEqual(CPUMath.usage(previous: a, current: b), 1)
    }

    func testMemoryUsedLikeActivityMonitor() {
        let used = MemoryMath.usedBytes(internalPages: 1000, purgeablePages: 200, wiredPages: 300, compressedPages: 100, pageSize: 16384)
        XCTAssertEqual(used, (800 + 300 + 100) * 16384)
        XCTAssertEqual(MemoryMath.usedBytes(internalPages: 10, purgeablePages: 50, wiredPages: 0, compressedPages: 0, pageSize: 4096), 0)
        XCTAssertEqual(MemoryMath.usedFraction(usedBytes: 8, totalBytes: 16), 0.5)
        XCTAssertEqual(MemoryMath.usedFraction(usedBytes: 8, totalBytes: 0), 0)
        XCTAssertEqual(MemoryMath.usedFraction(usedBytes: 99, totalBytes: 16), 1)
    }

    func testNetworkRate() {
        let a = NetCounters(bytesIn: 1_000_000, bytesOut: 500_000, time: 10)
        let b = NetCounters(bytesIn: 3_000_000, bytesOut: 600_000, time: 12)
        let r = NetworkMath.rate(previous: a, current: b)!
        XCTAssertEqual(r.down, 8_000_000, accuracy: 0.001)
        XCTAssertEqual(r.up, 400_000, accuracy: 0.001)
    }

    func testNetworkCounterResetCountsAsZero() {
        let a = NetCounters(bytesIn: 5_000_000, bytesOut: 5_000_000, time: 10)
        let b = NetCounters(bytesIn: 100, bytesOut: 5_000_100, time: 11)
        let r = NetworkMath.rate(previous: a, current: b)!
        XCTAssertEqual(r.down, 0)
        XCTAssertEqual(r.up, 800, accuracy: 0.001)
        XCTAssertNil(NetworkMath.rate(previous: a, current: a), "no time passed")
    }

    func testOnlyRealInterfacesCounted() {
        XCTAssertTrue(NetworkMath.isCountedInterface("en0"))
        XCTAssertTrue(NetworkMath.isCountedInterface("en5"))
        for n in ["lo0", "utun3", "awdl0", "llw0", "bridge0", "ap1", "anpi0", "gif0"] {
            XCTAssertFalse(NetworkMath.isCountedInterface(n), n)
        }
    }

    func testDiskFreeFraction() {
        XCTAssertEqual(DiskMath.freeFraction(free: 312, total: 994), 312.0 / 994, accuracy: 1e-12)
        XCTAssertEqual(DiskMath.freeFraction(free: 5, total: 0), 0)
    }
}

final class FormattingTests: XCTestCase {
    let brunei = TimeZone(identifier: "Asia/Brunei")!
    let london = TimeZone(identifier: "Europe/London")!

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ tz: TimeZone) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testPercent() {
        XCTAssertEqual(Format.percent(0.234), "23%")
        XCTAssertEqual(Format.percent(0.996), "100%")
        XCTAssertEqual(Format.percent(-1), "0%")
        XCTAssertEqual(Format.percent(.nan), "0%")
    }

    func testGigabytes() {
        XCTAssertEqual(Format.gigabytes(312_000_000_000), "312 GB")
        XCTAssertEqual(Format.gigabytes(8_400_000_000), "8.4 GB")
        XCTAssertEqual(Format.gigabytes(1_500_000_000_000), "1.5 TB")
        XCTAssertEqual(Format.gigabytes(-5), "0.0 GB")
    }

    func testNetworkText() {
        XCTAssertEqual(Format.network(NetRate(down: 84_200_000, up: 12_600_000)), "↓ 84.2  ↑ 12.6 Mbps")
        XCTAssertEqual(Format.mbps(512_000), "0.5")
        XCTAssertEqual(Format.mbps(940_000_000), "940")
        XCTAssertEqual(Format.mbps(.infinity), "0.0")
    }

    func testBruneiAndLondonClocks() {
        // 13:47 UTC in November: Brunei is UTC+8, London is on GMT.
        let d = date(2026, 11, 21, 13, 47, TimeZone(identifier: "UTC")!)
        XCTAssertEqual(Format.clock(d, timeZone: brunei), "21:47")
        XCTAssertEqual(Format.clock(d, timeZone: london), "13:47")
        let p = Format.clockParts(d, timeZone: brunei)
        XCTAssertEqual(p.hours, "21")
        XCTAssertEqual(p.minutes, "47")
    }

    func testLondonSummerTime() {
        // In July London is on BST (UTC+1), so the gap to Brunei is 7 hours.
        let d = date(2026, 7, 1, 12, 5, TimeZone(identifier: "UTC")!)
        XCTAssertEqual(Format.clock(d, timeZone: london), "13:05")
        XCTAssertEqual(Format.clock(d, timeZone: brunei), "20:05")
    }

    func testMidnightPadsDigits() {
        let d = date(2026, 1, 1, 0, 3, brunei)
        XCTAssertEqual(Format.clock(d, timeZone: brunei), "00:03")
    }

    func testCountdown() {
        XCTAssertEqual(Format.countdown(18 * 60 + 42), "18:42")
        XCTAssertEqual(Format.countdown(0.2), "00:01", "rounds up so it never shows zero early")
        XCTAssertEqual(Format.countdown(0), "00:00")
        XCTAssertEqual(Format.countdown(-3), "00:00")
        XCTAssertEqual(Format.countdown(25 * 60), "25:00")
    }

    func testLongDate() {
        XCTAssertEqual(Format.longDate(date(2026, 11, 21, 21, 47, brunei), timeZone: brunei), "Saturday 21 November")
    }

    func testTemperatureAndFan() {
        XCTAssertEqual(Format.degrees(47.6), "48°")
        XCTAssertEqual(Format.rpm(1850.4), "1,850 rpm")
        XCTAssertEqual(Format.rpm(-2), "0 rpm")
    }

    func testEventWhen() {
        let now = date(2026, 11, 21, 21, 47, brunei)
        func when(_ start: Date, allDay: Bool = false) -> String {
            Format.eventWhen(start: start, end: start.addingTimeInterval(3600), isAllDay: allDay, now: now, timeZone: brunei)
        }
        XCTAssertEqual(when(date(2026, 11, 22, 18, 30, brunei)), "Tomorrow, 6:30 PM")
        XCTAssertEqual(when(date(2026, 11, 21, 23, 0, brunei)), "Today, 11:00 PM")
        XCTAssertEqual(when(date(2026, 11, 24, 9, 0, brunei)), "Tuesday, 9:00 AM")
        XCTAssertEqual(when(date(2026, 12, 2, 9, 0, brunei)), "Wed 2 Dec, 9:00 AM")
        XCTAssertEqual(when(date(2026, 11, 22, 0, 0, brunei), allDay: true), "Tomorrow, all day")
        XCTAssertEqual(Format.eventWhen(start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600), isAllDay: false, now: now, timeZone: brunei), "Now")
    }
}

final class StatusTests: XCTestCase {
    func testCalmByDefault() {
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(cpu: 0.2, memory: 0.6, batteryLevel: 0.84, diskFreeFraction: 0.31)), .calm)
    }

    func testLowBatteryOnlyWhenNotCharging() {
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(batteryLevel: 0.12, batteryCharging: false)), .attention("Battery low"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(batteryLevel: 0.12, batteryCharging: true)), .calm)
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(batteryLevel: 0.2, batteryCharging: false)), .attention("Battery low"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(batteryLevel: 0.21, batteryCharging: false)), .calm)
    }

    func testOtherAlerts() {
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(diskFreeFraction: 0.05)), .attention("Disk nearly full"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(thermal: .serious)), .attention("Running hot"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(thermal: .critical)), .attention("Running very hot"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(thermal: .fair)), .calm)
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(cpu: 0.95)), .attention("Working hard"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(memory: 0.95)), .attention("Memory full"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(focusJustFinished: true)), .attention("Focus done"))
    }

    func testMostImportantReasonWins() {
        let s = StatusRules.evaluate(StatusInputs(cpu: 0.99, batteryLevel: 0.05, thermal: .critical))
        XCTAssertEqual(s.reason, "Running very hot")
        XCTAssertTrue(s.needsAttention)
        XCTAssertNil(Status.calm.reason)
    }

    func testSmootherNeedsSustainedLoad() {
        var s = Smoother(weight: 0.2)
        XCTAssertEqual(s.add(0.1), 0.1)
        let spike = s.add(1.0)
        XCTAssertLessThan(spike, StatusRules.busyCPU, "one busy second shouldn't trigger the alert")
        var v = spike
        for _ in 0..<20 { v = s.add(1.0) }
        XCTAssertGreaterThan(v, StatusRules.busyCPU)
    }
}

final class FocusTimerTests: XCTestCase {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testStartPauseResume() {
        var f = FocusTimer(duration: 25 * 60)
        XCTAssertEqual(f.remaining(at: t0), 1500)
        XCTAssertEqual(f.caption(at: t0), "tap to start")
        f.toggle(at: t0)
        XCTAssertTrue(f.isRunning)
        XCTAssertEqual(f.remaining(at: t0.addingTimeInterval(378)), 1122)  // 18:42
        f.toggle(at: t0.addingTimeInterval(378))
        XCTAssertEqual(f.caption(at: t0), "paused")
        XCTAssertEqual(f.remaining(at: t0.addingTimeInterval(9999)), 1122, "paused time doesn't move")
        f.toggle(at: t0.addingTimeInterval(1000))
        XCTAssertEqual(f.remaining(at: t0.addingTimeInterval(1100)), 1022)
    }

    func testFinishesOnceAndResets() {
        var f = FocusTimer(duration: 60)
        f.toggle(at: t0)
        XCTAssertFalse(f.tick(at: t0.addingTimeInterval(59)))
        XCTAssertTrue(f.tick(at: t0.addingTimeInterval(61)))
        XCTAssertFalse(f.tick(at: t0.addingTimeInterval(62)), "only signals once")
        XCTAssertEqual(f.remaining(at: t0.addingTimeInterval(62)), 0)
        XCTAssertEqual(f.caption(at: t0), "done")
        XCTAssertTrue(f.justFinished(at: t0.addingTimeInterval(90)))
        XCTAssertFalse(f.justFinished(at: t0.addingTimeInterval(200)))
        f.toggle(at: t0.addingTimeInterval(300))
        XCTAssertTrue(f.isRunning, "tapping a finished timer starts a new session")
        f.reset()
        XCTAssertEqual(f.remaining(at: t0), 60)
        XCTAssertFalse(f.isRunning)
    }

    func testMinimumDuration() {
        XCTAssertEqual(FocusTimer(duration: 5).duration, 60)
    }

    func testBroadcastPayloadForHorizonStrip() {
        var f = FocusTimer(duration: 1500)
        XCTAssertEqual(FocusBroadcast.payload(f, now: t0)["state"] as? String, "idle")
        f.toggle(at: t0)
        let running = FocusBroadcast.payload(f, now: t0.addingTimeInterval(100))
        XCTAssertEqual(running["state"] as? String, "running")
        XCTAssertEqual(running["endsAt"] as? Double, t0.addingTimeInterval(1500).timeIntervalSince1970)
        XCTAssertEqual(running["remaining"] as? Double, 1400)
        XCTAssertEqual(running["duration"] as? Double, 1500)
        f.toggle(at: t0.addingTimeInterval(300))
        let paused = FocusBroadcast.payload(f, now: t0.addingTimeInterval(400))
        XCTAssertEqual(paused["state"] as? String, "paused")
        XCTAssertEqual(paused["remaining"] as? Double, 1200)
        f.toggle(at: t0.addingTimeInterval(400))
        _ = f.tick(at: t0.addingTimeInterval(1700))
        let done = FocusBroadcast.payload(f, now: t0.addingTimeInterval(1700))
        XCTAssertEqual(done["state"] as? String, "finished")
        XCTAssertEqual(done["finishedAt"] as? Double, t0.addingTimeInterval(1600).timeIntervalSince1970)
    }
}

final class WeatherTests: XCTestCase {
    func testParsesOpenMeteo() {
        let json = """
        {"latitude":4.9,"longitude":114.94,"current_units":{"temperature_2m":"°C"},
         "current":{"time":"2026-11-21T21:45","interval":900,"temperature_2m":28.6,"weather_code":80}}
        """.data(using: .utf8)!
        let now = Date()
        let w = Weather.parse(json, now: now)!
        XCTAssertEqual(w.celsius, 28.6)
        XCTAssertEqual(w.code, 80)
        XCTAssertEqual(w.summary, "29° showers")
        XCTAssertTrue(Weather.isFresh(w, now: now.addingTimeInterval(3600)))
        XCTAssertFalse(Weather.isFresh(w, now: now.addingTimeInterval(4 * 3600)))
    }

    func testBadResponsesAreIgnored() {
        XCTAssertNil(Weather.parse(Data("{}".utf8), now: Date()))
        XCTAssertNil(Weather.parse(Data("not json".utf8), now: Date()))
        XCTAssertNil(Weather.parse(Data(#"{"error":true,"reason":"bad"}"#.utf8), now: Date()))
    }

    func testWords() {
        XCTAssertEqual(Weather.words(for: 0), "clear")
        XCTAssertEqual(Weather.words(for: 3), "cloudy")
        XCTAssertEqual(Weather.words(for: 63), "rain")
        XCTAssertEqual(Weather.words(for: 95), "thunderstorms")
        XCTAssertEqual(Weather.words(for: 12345), "—")
    }

    func testURLAsksOnlyForBandarSeriBegawan() {
        let u = Weather.url.absoluteString
        XCTAssertTrue(u.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        XCTAssertTrue(u.contains("latitude=4.9031"))
        XCTAssertTrue(u.contains("longitude=114.9398"))
        XCTAssertTrue(u.contains("current=temperature_2m,weather_code"))
    }
}

final class SMCDecodeTests: XCTestCase {
    func testFourCC() {
        XCTAssertEqual(SMCDecode.fourCC("TC0P"), 0x5443_3050)
        XCTAssertEqual(SMCDecode.string(0x5443_3050), "TC0P")
        XCTAssertEqual(SMCDecode.string(SMCDecode.fourCC("flt ")), "flt ")
    }

    func testFloatLittleEndian() {
        let bits = Float(47.5).bitPattern
        let bytes = [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8(bits >> 24)]
        XCTAssertEqual(SMCDecode.decode(type: "flt ", bytes: bytes), 47.5)
        XCTAssertNil(SMCDecode.decode(type: "flt ", bytes: [0, 0]))
        let nanBits = Float.nan.bitPattern
        XCTAssertNil(SMCDecode.decode(type: "flt ", bytes: [UInt8(nanBits & 0xFF), UInt8((nanBits >> 8) & 0xFF), UInt8((nanBits >> 16) & 0xFF), UInt8(nanBits >> 24)]))
    }

    func testIntelFixedPoint() {
        XCTAssertEqual(SMCDecode.decode(type: "sp78", bytes: [0x30, 0x80]), 48.5)
        XCTAssertEqual(SMCDecode.decode(type: "sp78", bytes: [0xFF, 0x00]), -1)
        XCTAssertEqual(SMCDecode.decode(type: "fpe2", bytes: [0x1C, 0xE8]), 1850)
        XCTAssertEqual(SMCDecode.decode(type: "ui8 ", bytes: [2]), 2)
        XCTAssertEqual(SMCDecode.decode(type: "ui16", bytes: [0x07, 0x3A]), 1850)
        XCTAssertNil(SMCDecode.decode(type: "what", bytes: [1, 2, 3, 4]))
    }

    func testAverageIgnoresJunk() {
        XCTAssertEqual(SMCDecode.averageTemperature([46, 50, 0, -3, 200, .nan]), 48)
        XCTAssertNil(SMCDecode.averageTemperature([0, 0, 129]))
        XCTAssertNil(SMCDecode.averageTemperature([]))
    }

    func testFanPlausibility() {
        XCTAssertEqual(SMCDecode.plausibleFan(1850), 1850)
        XCTAssertEqual(SMCDecode.plausibleFan(0), 0)
        XCTAssertNil(SMCDecode.plausibleFan(nil))
        XCTAssertNil(SMCDecode.plausibleFan(-1))
        XCTAssertNil(SMCDecode.plausibleFan(65535))
    }

    func testKeysAreFourCharacters() {
        for k in SMCDecode.temperatureKeys { XCTAssertEqual(k.utf8.count, 4, k) }
        XCTAssertEqual(Set(SMCDecode.temperatureKeys).count, SMCDecode.temperatureKeys.count, "no duplicates")
    }
}

final class DrawerTests: XCTestCase {
    func testHoverOpensAndLeavingClosesAfterDelay() {
        var d = DrawerLogic()
        XCTAssertEqual(d.pointerEntered(), .expand)
        XCTAssertTrue(d.expanded)
        XCTAssertEqual(d.pointerEntered(), .none, "already open")
        XCTAssertEqual(d.pointerExited(), .scheduleCollapse(after: DrawerLogic.collapseDelay))
        XCTAssertEqual(d.collapseTimerFired(generation: d.generation), .collapse)
        XCTAssertFalse(d.expanded)
    }

    func testComingBackCancelsTheClose() {
        var d = DrawerLogic()
        _ = d.pointerEntered()
        _ = d.pointerExited()
        let staleGeneration = d.generation
        _ = d.pointerEntered()
        XCTAssertEqual(d.collapseTimerFired(generation: staleGeneration), .none)
        XCTAssertTrue(d.expanded)
    }

    func testStaleTimerFromEarlierExitIgnored() {
        var d = DrawerLogic()
        _ = d.pointerEntered()
        _ = d.pointerExited()
        let first = d.generation
        _ = d.pointerEntered()
        _ = d.pointerExited()
        XCTAssertEqual(d.collapseTimerFired(generation: first), .none)
        XCTAssertEqual(d.collapseTimerFired(generation: d.generation), .collapse)
    }

    func testPinKeepsItOpen() {
        var d = DrawerLogic()
        XCTAssertEqual(d.togglePin(), .expand, "pinning opens it")
        XCTAssertEqual(d.pointerExited(), .none, "pinned drawer stays")
        XCTAssertEqual(d.collapseTimerFired(generation: d.generation), .none)
        XCTAssertEqual(d.togglePin(), .collapse, "unpinning with the pointer away tucks it in")
        XCTAssertFalse(d.expanded)
    }

    func testUnpinWhilePointerInsideStaysOpenUntilLeaving() {
        var d = DrawerLogic()
        _ = d.pointerEntered()
        XCTAssertEqual(d.togglePin(), .none)
        XCTAssertEqual(d.togglePin(), .none)
        XCTAssertTrue(d.expanded)
        XCTAssertEqual(d.pointerExited(), .scheduleCollapse(after: DrawerLogic.collapseDelay))
    }

    func testExitWhenClosedDoesNothing() {
        var d = DrawerLogic()
        XCTAssertEqual(d.pointerExited(), .none)
    }
}

final class PulseTests: XCTestCase {
    func testStaysInsideBoxAtAnyLoad() {
        for load in [-1, 0, 0.23, 0.5, 1, 7, .nan] as [Double] {
            let pts = Pulse.heartbeat(width: 252, height: 80, load: load)
            XCTAssertEqual(pts.first?.x, 0)
            XCTAssertEqual(pts.last?.x, 252)
            for p in pts {
                XCTAssertGreaterThanOrEqual(p.y, 1)
                XCTAssertLessThanOrEqual(p.y, 79)
            }
            XCTAssertEqual(pts.map(\.x), pts.map(\.x).sorted(), "line runs left to right")
        }
    }

    func testBusierMeansTallerBeats() {
        func span(_ l: Double) -> Double {
            let ys = Pulse.heartbeat(width: 252, height: 80, load: l).map(\.y)
            return ys.max()! - ys.min()!
        }
        XCTAssertLessThan(span(0), span(0.5))
        XCTAssertLessThan(span(0.5), span(1))
        XCTAssertGreaterThan(span(0), 0, "still a visible pulse when idle")
    }
}

final class NextEventTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func item(_ title: String, startIn: TimeInterval, length: TimeInterval = 3600, allDay: Bool = false, cancelled: Bool = false) -> CalendarItem {
        CalendarItem(title: title, start: now.addingTimeInterval(startIn), end: now.addingTimeInterval(startIn + length),
                     isAllDay: allDay, isCancelled: cancelled)
    }

    func testPicksSoonestTimedEvent() {
        let items = [item("Later", startIn: 7200), item("Soon", startIn: 600), item("Banner", startIn: -3600, length: 86400, allDay: true)]
        XCTAssertEqual(NextEventRule.pick(items, now: now)?.title, "Soon")
    }

    func testShowsEventHappeningNow() {
        let items = [item("Meeting", startIn: -600), item("Next", startIn: 1800)]
        XCTAssertEqual(NextEventRule.pick(items, now: now)?.title, "Meeting")
    }

    func testSkipsFinishedAndCancelled() {
        let items = [item("Done", startIn: -7200), item("Off", startIn: 300, cancelled: true), item("Real", startIn: 900)]
        XCTAssertEqual(NextEventRule.pick(items, now: now)?.title, "Real")
    }

    func testAllDayOnlyWhenNothingTimed() {
        let items = [item("Holiday", startIn: -3600, length: 86400, allDay: true)]
        XCTAssertEqual(NextEventRule.pick(items, now: now)?.title, "Holiday")
        XCTAssertNil(NextEventRule.pick([], now: now))
    }

    func testSameStartIsStableByTitle() {
        let items = [item("B", startIn: 600), item("A", startIn: 600)]
        XCTAssertEqual(NextEventRule.pick(items, now: now)?.title, "A")
    }

    func testBlankTitles() {
        XCTAssertEqual(NextEventRule.displayTitle(nil), "Event")
        XCTAssertEqual(NextEventRule.displayTitle("   \n"), "Event")
        XCTAssertEqual(NextEventRule.displayTitle("  Run "), "Run")
    }
}

final class PerInterfaceNetworkTests: XCTestCase {
    func testNewInterfaceDoesNotSpike() {
        let a = NetSample(interfaces: ["en0": InterfaceBytes(bytesIn: 1000, bytesOut: 500)], time: 10)
        let b = NetSample(interfaces: ["en0": InterfaceBytes(bytesIn: 2000, bytesOut: 1000),
                                       "en5": InterfaceBytes(bytesIn: 9_000_000_000, bytesOut: 9_000_000_000)], time: 11)
        let r = NetworkMath.rate(previous: a, current: b)!
        XCTAssertEqual(r.down, 8000, accuracy: 0.001)
        XCTAssertEqual(r.up, 4000, accuracy: 0.001)
    }

    func testInterfaceGoingAwayIsIgnored() {
        let a = NetSample(interfaces: ["en0": InterfaceBytes(bytesIn: 1000, bytesOut: 0),
                                       "en1": InterfaceBytes(bytesIn: 5000, bytesOut: 0)], time: 0)
        let b = NetSample(interfaces: ["en0": InterfaceBytes(bytesIn: 1500, bytesOut: 0)], time: 1)
        XCTAssertEqual(NetworkMath.rate(previous: a, current: b)?.down ?? -1, 4000, accuracy: 0.001)
    }

    func testCounterResetCountsAsZeroAndTooSoonIsNil() {
        let a = NetSample(interfaces: ["en0": InterfaceBytes(bytesIn: 9000, bytesOut: 9000)], time: 0)
        let b = NetSample(interfaces: ["en0": InterfaceBytes(bytesIn: 10, bytesOut: 10)], time: 2)
        XCTAssertEqual(NetworkMath.rate(previous: a, current: b), NetRate(down: 0, up: 0))
        let c = NetSample(interfaces: a.interfaces, time: 0.01)
        XCTAssertNil(NetworkMath.rate(previous: a, current: c))
    }

    func testOnlyWiFiAndEthernetCount() {
        XCTAssertTrue(NetworkMath.isCountedInterface("en0"))
        XCTAssertFalse(NetworkMath.isCountedInterface("utun3"))
        XCTAssertFalse(NetworkMath.isCountedInterface("awdl0"))
        XCTAssertFalse(NetworkMath.isCountedInterface("lo0"))
    }
}

final class DrawerReconcileTests: XCTestCase {
    func testMissedEnterOpensDrawer() {
        var d = DrawerLogic()
        XCTAssertEqual(d.reconcile(pointerIsInside: true), .expand)
        XCTAssertEqual(d.reconcile(pointerIsInside: true), .none, "nothing changes when it already agrees")
    }

    func testMissedExitStartsCollapse() {
        var d = DrawerLogic()
        _ = d.pointerEntered()
        XCTAssertEqual(d.reconcile(pointerIsInside: false), .scheduleCollapse(after: DrawerLogic.collapseDelay))
        XCTAssertEqual(d.collapseTimerFired(generation: d.generation), .collapse)
    }

    func testReturningCancelsPendingCollapse() {
        var d = DrawerLogic()
        _ = d.pointerEntered()
        _ = d.pointerExited()
        let g = d.generation
        XCTAssertEqual(d.reconcile(pointerIsInside: true), .none, "already open")
        XCTAssertEqual(d.collapseTimerFired(generation: g), .none)
        XCTAssertTrue(d.expanded)
    }

    func testPinWhileCollapsePendingKeepsItOpen() {
        var d = DrawerLogic()
        _ = d.pointerEntered()
        _ = d.pointerExited()
        let g = d.generation
        XCTAssertEqual(d.togglePin(), .none)
        XCTAssertEqual(d.collapseTimerFired(generation: g), .none)
        XCTAssertTrue(d.expanded)
    }
}

final class ExtraCoreTests: XCTestCase {
    func testFocusPauseResumeAndFinishOnce() {
        let t0 = Date(timeIntervalSince1970: 0)
        var f = FocusTimer(duration: 120)
        f.toggle(at: t0)
        f.toggle(at: t0.addingTimeInterval(30))
        XCTAssertEqual(f.caption(at: t0), "paused")
        XCTAssertEqual(f.remaining(at: t0.addingTimeInterval(500)), 90, "paused time doesn't run")
        f.toggle(at: t0.addingTimeInterval(100))
        XCTAssertFalse(f.tick(at: t0.addingTimeInterval(189)))
        XCTAssertTrue(f.tick(at: t0.addingTimeInterval(190)))
        XCTAssertFalse(f.tick(at: t0.addingTimeInterval(191)), "only fires once")
        XCTAssertTrue(f.justFinished(at: t0.addingTimeInterval(200)))
        XCTAssertFalse(f.justFinished(at: t0.addingTimeInterval(260)))
        XCTAssertEqual(FocusTimer(duration: 5).duration, 60, "at least a minute")
    }

    func testWeatherRejectsImpossibleTemperature() {
        let json = Data(#"{"current":{"time":"2026-11-21T21:45","temperature_2m":180,"weather_code":80}}"#.utf8)
        XCTAssertNil(Weather.parse(json, now: Date()))
    }

    func testFormattingEdges() {
        XCTAssertEqual(Format.degrees(.nan), "0°")
        XCTAssertEqual(Format.degrees(5000), "999°")
        XCTAssertEqual(Format.rpm(.infinity), "0 rpm")
        XCTAssertEqual(Format.gigabytes(999_600_000_000), "1.0 TB")
        XCTAssertEqual(Format.countdown(100 * 60), "100:00")
        XCTAssertEqual(Format.countdown(0.2), "00:01", "never shows 00:00 early")
    }

    // MARK: Month calendar

    private func mondayCal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Brunei")!
        c.locale = Locale(identifier: "en_GB")
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ c: Calendar) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testMonthGridStartsOnMondayAndPadsWithNeighbours() {
        let c = mondayCal()
        // 1 November 2026 is a Sunday, so the first row runs Mon 26 Oct to Sun 1 Nov.
        let weeks = MonthGrid.weeks(for: day(2026, 11, 21, 21, 47, c), today: day(2026, 11, 21, 21, 47, c), calendar: c)
        XCTAssertEqual(weeks.count, 6)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(weeks[0].map(\.day), [26, 27, 28, 29, 30, 31, 1])
        XCTAssertEqual(weeks[0].map(\.inMonth), [false, false, false, false, false, false, true])
        XCTAssertEqual(weeks[5].last?.day, 6, "pads to the end of the last week with December days")
        let today = weeks.flatMap { $0 }.filter(\.isToday)
        XCTAssertEqual(today.map(\.day), [21], "exactly one today")
        XCTAssertEqual(weeks.flatMap { $0 }.filter(\.inMonth).count, 30)
    }

    func testMonthGridUsesOnlyTheRowsItNeeds() {
        let c = mondayCal()
        // February 2027 starts on a Monday and has 28 days: exactly four rows.
        let weeks = MonthGrid.weeks(for: day(2027, 2, 10, 0, 0, c), today: day(2026, 11, 21, 0, 0, c), calendar: c)
        XCTAssertEqual(weeks.count, 4)
        XCTAssertEqual(weeks[0].first?.day, 1)
        XCTAssertFalse(weeks.flatMap { $0 }.contains { $0.isToday }, "today isn't in another month")
    }

    func testMonthGridSundayFirstCalendar() {
        var c = mondayCal()
        c.firstWeekday = 1
        let weeks = MonthGrid.weeks(for: day(2026, 11, 1, 0, 0, c), today: day(2026, 11, 1, 0, 0, c), calendar: c)
        XCTAssertEqual(weeks[0].first?.day, 1, "1 Nov 2026 is a Sunday, so it opens the first row")
        XCTAssertEqual(MonthGrid.weekdayInitials(calendar: c).first, "S")
        XCTAssertEqual(MonthGrid.weekdayInitials(calendar: mondayCal()), ["M", "T", "W", "T", "F", "S", "S"])
    }

    func testMonthShiftAndTitleAcrossTheYear() {
        let c = mondayCal()
        let now = day(2026, 12, 31, 23, 30, c)
        XCTAssertEqual(MonthGrid.title(MonthGrid.monthStart(of: now, offset: 1, calendar: c), calendar: c), "January 2027")
        XCTAssertEqual(MonthGrid.title(MonthGrid.monthStart(of: now, offset: -12, calendar: c), calendar: c), "December 2025")
        XCTAssertEqual(MonthGrid.monthStart(of: now, calendar: c), day(2026, 12, 1, 0, 0, c))
    }

    func testEventDaysCoverMultiDayEventsButNotMidnightEnds() {
        let c = mondayCal()
        let items = [
            CalendarItem(title: "Run", start: day(2026, 11, 22, 18, 30, c), end: day(2026, 11, 22, 19, 30, c), isAllDay: false),
            // All-day events end at midnight of the following day.
            CalendarItem(title: "Trip", start: day(2026, 11, 25, 0, 0, c), end: day(2026, 11, 28, 0, 0, c), isAllDay: true),
            CalendarItem(title: "Late", start: day(2026, 11, 29, 23, 0, c), end: day(2026, 11, 30, 1, 0, c), isAllDay: false),
            CalendarItem(title: "Off", start: day(2026, 11, 10, 9, 0, c), end: day(2026, 11, 10, 10, 0, c), isAllDay: false, isCancelled: true),
        ]
        let days = MonthGrid.eventDays(items, from: day(2026, 10, 26, 0, 0, c), to: day(2026, 12, 7, 0, 0, c), calendar: c)
        let expected: Set<Date> = [day(2026, 11, 22, 0, 0, c), day(2026, 11, 25, 0, 0, c), day(2026, 11, 26, 0, 0, c),
                                   day(2026, 11, 27, 0, 0, c), day(2026, 11, 29, 0, 0, c), day(2026, 11, 30, 0, 0, c)]
        XCTAssertEqual(days, expected)
    }

    func testEventDaysClipsLongEventsToTheWindow() {
        let c = mondayCal()
        // A three-year event still marks the shown month, and only that window.
        let items = [CalendarItem(title: "Long", start: day(2024, 1, 1, 0, 0, c), end: day(2027, 1, 1, 0, 0, c), isAllDay: true)]
        let days = MonthGrid.eventDays(items, from: day(2026, 11, 1, 0, 0, c), to: day(2026, 11, 4, 0, 0, c), calendar: c)
        XCTAssertEqual(days, [day(2026, 11, 1, 0, 0, c), day(2026, 11, 2, 0, 0, c), day(2026, 11, 3, 0, 0, c)])
    }

    func testEventDaysHandlesZeroLengthAndBackwardsEvents() {
        let c = mondayCal()
        let t = day(2026, 11, 5, 12, 0, c)
        let items = [CalendarItem(title: "Reminder", start: t, end: t, isAllDay: false),
                     CalendarItem(title: "Odd", start: t, end: t.addingTimeInterval(-3600), isAllDay: false)]
        XCTAssertEqual(MonthGrid.eventDays(items, from: day(2026, 11, 1, 0, 0, c), to: day(2026, 12, 1, 0, 0, c), calendar: c), [day(2026, 11, 5, 0, 0, c)])
    }
}
