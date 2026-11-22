import SwiftUI
import AppKit
import MissionCore

/// Pictures of the widget made from sample data, for checking the design without touching the screen.
@MainActor
enum Snapshots {
    struct Failed: Error, CustomStringConvertible {
        var description: String
    }

    /// A desktop-like backdrop, like the mockup, with the widget at its top-left.
    struct Scene: View {
        @ObservedObject var model: DashboardModel
        var open: Bool

        var body: some View {
            ZStack(alignment: .topLeading) {
                RadialGradient(colors: [Color(red: 0.45, green: 0.40, blue: 0.33), Color(red: 0.20, green: 0.24, blue: 0.28), Color(red: 0.10, green: 0.12, blue: 0.15)],
                               center: UnitPoint(x: 0.9, y: 0.2), startRadius: 0, endRadius: 520)
                Group {
                    if open {
                        DrawerPanelView(model: model, animate: false)
                    } else {
                        TabStrip(model: model, animate: false)
                    }
                }
                .shadow(color: .black.opacity(0.35), radius: 24, x: 10)
                .padding(.top, Dusk.topGap)
                Text(open ? "REVEALED" : "HIDDEN")
                    .font(.system(size: 11)).tracking(2.6)
                    .foregroundStyle(Color(red: 0.72, green: 0.67, blue: 0.61))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(16)
            }
            .frame(width: open ? 452 : 300, height: 760)
            .clipped()
        }
    }

    struct Pair: View {
        @ObservedObject var model: DashboardModel
        var body: some View {
            HStack(spacing: 8) {
                Scene(model: model, open: false)
                Scene(model: model, open: true)
            }
            .background(Color(red: 0.02, green: 0.016, blue: 0.012))
        }
    }

    static func render(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Dusk.snapshotMode = true
        let calm = DashboardModel.demo()
        try save(Pair(model: calm), to: dir.appendingPathComponent("1-hidden-and-revealed.png"))
        try save(TabStrip(model: calm, animate: false).padding(20).background(Color.black), to: dir.appendingPathComponent("2-tab-closeup.png"), scale: 4)

        // Same scene when something needs attention (low battery), to check the coral state.
        let alert = DashboardModel.demo()
        alert.battery = BatteryReading(level: 0.12, charging: false, onPower: false)
        alert.recomputeStatus()
        try save(Pair(model: alert), to: dir.appendingPathComponent("3-attention-low-battery.png"))

        // A Mac with no battery, no fan, no calendar access and no weather yet.
        let bare = DashboardModel.demo()
        bare.battery = nil
        bare.fan = nil
        bare.temperature = nil
        bare.nextEvent = nil
        bare.weather = nil
        bare.focus = FocusTimer()
        bare.recomputeStatus()
        try save(Pair(model: bare), to: dir.appendingPathComponent("4-desktop-mac-no-extras.png"))

        // The Clear Glass option, over a real-looking backdrop.
        Dusk.snapshotClear = true
        try save(Pair(model: calm), to: dir.appendingPathComponent("5-clear-glass.png"))
        Dusk.snapshotClear = false
    }

    private static func save<V: View>(_ view: V, to url: URL, scale: CGFloat = 2) throws {
        let r = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        r.scale = scale
        guard let image = r.cgImage else { throw Failed(description: "could not render \(url.lastPathComponent)") }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failed(description: "could not encode \(url.lastPathComponent)") }
        try png.write(to: url)
        print("Saved \(url.path)")
    }
}
