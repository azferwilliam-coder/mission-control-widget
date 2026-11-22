// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MissionControlWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MissionCore", targets: ["MissionCore"]),
        .executable(name: "MissionControlWidget", targets: ["MissionControlWidget"]),
    ],
    targets: [
        // Pure logic (maths, formatting, rules, timers). No screens, no system calls. Fully unit-tested.
        .target(name: "MissionCore"),
        // The desktop drawer: reads the Mac's stats and draws them.
        .executableTarget(
            name: "MissionControlWidget",
            dependencies: ["MissionCore"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "MissionCoreTests", dependencies: ["MissionCore"]),
    ]
)
