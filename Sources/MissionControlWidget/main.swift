import AppKit
import SwiftUI
import MissionCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = DashboardModel()
    lazy var drawer = DrawerController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = ThemeLive.shared
        model.start()
        drawer.install()
    }

    // It lives on the edge of the screen, so closing windows never quits it. Quit from its right-click menu.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    // Renders the hidden tab and open drawer with sample data into PNGs, for review. No window, no real data.
    let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
    MainActor.assumeIsolated {
        do {
            try Snapshots.render(to: dir)
            exit(0)
        } catch {
            FileHandle.standardError.write("Snapshot failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
