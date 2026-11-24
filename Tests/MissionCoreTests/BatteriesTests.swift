import XCTest
@testable import MissionCore

final class BatteriesTests: XCTestCase {
    func testLevelsAsMacOSWritesThem() {
        XCTAssertEqual(BatteryRules.level(from: "72%")!, 0.72, accuracy: 1e-9)
        XCTAssertEqual(BatteryRules.level(from: " 5 %")!, 0.05, accuracy: 1e-9)
        XCTAssertEqual(BatteryRules.level(from: 100)!, 1, accuracy: 1e-9)
        XCTAssertEqual(BatteryRules.level(from: 0)!, 0, accuracy: 1e-9)
        XCTAssertEqual(BatteryRules.level(from: 62.0)!, 0.62, accuracy: 1e-9)
        XCTAssertNil(BatteryRules.level(from: nil))
        XCTAssertNil(BatteryRules.level(from: "n/a"))
        XCTAssertNil(BatteryRules.level(from: -1))
        XCTAssertNil(BatteryRules.level(from: 101))
        XCTAssertNil(BatteryRules.level(from: Double.nan))
    }

    func testOwnerIsDroppedFromNames() {
        XCTAssertEqual(BatteryRules.shortName("Azfer’s Magic Mouse"), "Magic Mouse")
        XCTAssertEqual(BatteryRules.shortName("Azfer's AirPods Pro"), "AirPods Pro")
        XCTAssertEqual(BatteryRules.shortName("Magic Keyboard"), "Magic Keyboard")
        XCTAssertEqual(DeviceBattery(name: "Azfer’s Magic Mouse", kind: .mouse, level: 0.5).name, "Magic Mouse")
    }

    func testKindFromNameOrType() {
        XCTAssertEqual(DeviceKind.guess(name: "AirPods Pro"), .headphones)
        XCTAssertEqual(DeviceKind.guess(name: "Beats Studio Buds"), .headphones)
        XCTAssertEqual(DeviceKind.guess(name: "Magic Mouse"), .mouse)
        XCTAssertEqual(DeviceKind.guess(name: "Magic Keyboard with Touch ID"), .keyboard)
        XCTAssertEqual(DeviceKind.guess(name: "Magic Trackpad"), .trackpad)
        XCTAssertEqual(DeviceKind.guess(name: "Something", type: "Headphones"), .headphones)
        XCTAssertEqual(DeviceKind.guess(name: "MX Master 3", type: "Mouse"), .mouse)
        XCTAssertEqual(DeviceKind.guess(name: "Speaker"), .other)
    }

    func testAirPodsUseTheLowerEarbudNotTheCase() {
        let d = BatteryRules.fromProfiler(name: "AirPods Pro", info: [
            "device_batteryLevelLeft": "72%", "device_batteryLevelRight": "70%", "device_batteryLevelCase": "15%",
            "device_minorType": "Headphones"])!
        XCTAssertEqual(d.kind, .headphones)
        XCTAssertEqual(d.level, 0.70, accuracy: 1e-9)
        XCTAssertFalse(d.isLow, "a low case alone isn't a low warning")
        XCTAssertEqual(d.parts.map(\.label), ["Left", "Right", "Case"])
        XCTAssertEqual(d.detail, "AirPods Pro: Left 72%, Right 70%, Case 15%")
    }

    func testOneEarbudOut() {
        let d = BatteryRules.fromProfiler(name: "AirPods", info: ["device_batteryLevelRight": "40%"])!
        XCTAssertEqual(d.level, 0.40, accuracy: 1e-9)
        XCTAssertEqual(d.kind, .headphones)
        XCTAssertEqual(d.parts, [BatteryPart(label: "Right", level: 0.40)])
    }

    func testSingleBatteryDevicesAndNoReading() {
        let beats = BatteryRules.fromProfiler(name: "Beats Solo", info: ["device_batteryLevelMain": "55%"])!
        XCTAssertEqual(beats.level, 0.55, accuracy: 1e-9)
        XCTAssertTrue(beats.parts.isEmpty)
        XCTAssertEqual(beats.detail, "Beats Solo: 55%")
        XCTAssertNil(BatteryRules.fromProfiler(name: "Speaker", info: ["device_minorType": "Speaker"]), "never guessed")
    }

    func testParsesSystemProfilerOutput() throws {
        let json = """
        {"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},
          "device_connected":[
            {"Azfer’s AirPods Pro":{"device_batteryLevelLeft":"72%","device_batteryLevelRight":"70%","device_batteryLevelCase":"45%","device_minorType":"Headphones"}},
            {"Magic Mouse":{"device_batteryLevelMain":"62%","device_minorType":"Mouse"}},
            {"Azfer’s iPhone":{"device_minorType":"Smartphone"}}
          ],
          "device_not_connected":[
            {"Old Headphones":{"device_batteryLevelMain":"30%","device_minorType":"Headphones"}}
          ]}]}
        """
        let list = BatteryRules.parseProfiler(Data(json.utf8))
        XCTAssertEqual(Set(list.map(\.name)), ["AirPods Pro", "Magic Mouse"], "disconnected devices and the iPhone are left out")
    }

    func testOlderProfilerLayoutWithConnectedFlag() {
        let json = """
        {"SPBluetoothDataType":[{"device_title":[
          {"AirPods":{"device_isconnected":"attrib_Yes","device_batteryLevelLeft":"80%","device_batteryLevelRight":"90%"}},
          {"Beats":{"device_isconnected":"attrib_No","device_batteryLevelMain":"20%"}}
        ]}]}
        """
        let list = BatteryRules.parseProfiler(Data(json.utf8))
        XCTAssertEqual(list.map(\.name), ["AirPods"])
        XCTAssertEqual(list.first!.level, 0.80, accuracy: 1e-9)
    }

    func testBadProfilerOutputGivesNothing() {
        XCTAssertTrue(BatteryRules.parseProfiler(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(BatteryRules.parseProfiler(Data("{}".utf8)).isEmpty)
    }

    func testRegistryReading() {
        let d = BatteryRules.fromRegistry(["Product": "Magic Keyboard", "BatteryPercent": 91])!
        XCTAssertEqual(d.kind, .keyboard)
        XCTAssertEqual(d.level, 0.91, accuracy: 1e-9)
        XCTAssertNil(BatteryRules.fromRegistry(["Product": "Apple Internal Keyboard / Trackpad"]), "built-in, no battery")
        XCTAssertNil(BatteryRules.fromRegistry(["BatteryPercent": 50]), "no name")
    }

    func testCombineOrdersAndRemovesDuplicates() {
        let mac = DeviceBattery(name: "This Mac", kind: .mac, level: 0.84, charging: true)
        let registry = [DeviceBattery(name: "Magic Keyboard", kind: .keyboard, level: 0.91),
                        DeviceBattery(name: "Magic Mouse", kind: .mouse, level: 0.60)]
        let profiler = [DeviceBattery(name: "Azfer’s Magic Mouse", kind: .mouse, level: 0.50),
                        DeviceBattery(name: "AirPods Pro", kind: .headphones, level: 0.70)]
        let list = BatteryRules.combine(mac: mac, registry: registry, profiler: profiler)
        XCTAssertEqual(list.map(\.kind), [.mac, .headphones, .mouse, .keyboard])
        XCTAssertEqual(list[2].level, 0.60, accuracy: 1e-9, "the registry reading wins")
    }

    func testTooManyDropsTheFullestNeverTheLow() {
        let mac = DeviceBattery(name: "This Mac", kind: .mac, level: 0.99)
        let many = (0..<6).map { DeviceBattery(name: "Device \($0)", kind: .other, level: Double($0) / 10 + 0.05) }
        let list = BatteryRules.combine(mac: mac, registry: many, profiler: [])
        XCTAssertEqual(list.count, BatteryRules.maxShown)
        XCTAssertEqual(list.first?.kind, .mac, "the Mac always stays")
        XCTAssertTrue(list.contains { $0.name == "Device 0" }, "the lowest is kept")
        XCTAssertFalse(list.contains { $0.name == "Device 5" }, "the fullest drops off")
    }

    func testDesktopMacWithNoAccessories() {
        XCTAssertTrue(BatteryRules.combine(mac: nil, registry: [], profiler: []).isEmpty)
    }

    func testLowAccessoryRaisesTheWarning() {
        let devices = [DeviceBattery(name: "This Mac", kind: .mac, level: 0.10),
                       DeviceBattery(name: "Magic Mouse", kind: .mouse, level: 0.12),
                       DeviceBattery(name: "Magic Keyboard", kind: .keyboard, level: 0.18),
                       DeviceBattery(name: "AirPods", kind: .headphones, level: 0.50)]
        XCTAssertEqual(BatteryRules.lowestAccessory(devices)?.name, "Magic Mouse", "the Mac has its own rule")
        XCTAssertNil(BatteryRules.lowestAccessory([DeviceBattery(name: "Magic Mouse", kind: .mouse, level: 0.21)]))
        XCTAssertNil(BatteryRules.lowestAccessory([DeviceBattery(name: "Magic Keyboard", kind: .keyboard, level: 0.1, charging: true)]))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(lowDevice: "Magic Mouse")), .attention("Magic Mouse battery low"))
    }

    func testMacBatteryWarningStillComesFirst() {
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(batteryLevel: 0.1, lowDevice: "Magic Mouse")), .attention("Battery low"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(focusJustFinished: true, lowDevice: "Magic Mouse")),
                       .attention("Focus done"), "a mouse can stay low for days, so it mustn't hide other alerts")
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(diskFreeFraction: 0.05, lowDevice: "Magic Mouse")), .attention("Disk nearly full"))
        XCTAssertEqual(StatusRules.evaluate(StatusInputs(cpu: 0.99, lowDevice: "Magic Mouse")), .attention("Magic Mouse battery low"))
    }

    func testEarbudOutOfTheCaseAtZeroIsIgnored() {
        let d = BatteryRules.fromProfiler(name: "AirPods", info: ["device_batteryLevelLeft": "0%", "device_batteryLevelRight": "64%"])!
        XCTAssertEqual(d.level, 0.64, accuracy: 1e-9)
        let both = BatteryRules.fromProfiler(name: "AirPods", info: ["device_batteryLevelLeft": "0%", "device_batteryLevelRight": "0%"])!
        XCTAssertEqual(both.level, 0, "both flat really is flat")
    }

    func testRenamedDeviceLearnsItsKind() {
        let registry = [DeviceBattery(name: "Desk KB", kind: .other, level: 0.5)]
        let profiler = [DeviceBattery(name: "Desk KB", kind: .keyboard, level: 0.5)]
        XCTAssertEqual(BatteryRules.combine(mac: nil, registry: registry, profiler: profiler).map(\.kind), [.keyboard])
    }

    func testLevelsAreClamped() {
        XCTAssertEqual(DeviceBattery(name: "X", kind: .other, level: 1.4).level, 1)
        XCTAssertEqual(DeviceBattery(name: "X", kind: .other, level: -0.2).level, 0)
    }
}
