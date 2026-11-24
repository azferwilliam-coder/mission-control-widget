import SwiftUI
import AppKit
import Observation
import MissionCore

// MARK: - Desk Theme, live (shared file)
// The same file lives in Mission Control Widget, Smart Corner, Desk Drawer and Horizon Strip (only the import differs).
// Views read ThemeLive.shared (through Dusk.amber and friends), so SwiftUI redraws them as soon as the theme changes.

@Observable
final class ThemeLive {
    static let shared = ThemeLive()

    private(set) var choice: DeskThemeChoice
    private(set) var wallpaperFollows: Bool
    private(set) var iconsFollow: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// True while showing a preview look for review pictures: never touches the Mac.
    @ObservationIgnored private var isPreview = false

    private init() {
        defaults = UserDefaults(suiteName: DeskTheme.suiteName) ?? .standard
        choice = DeskTheme.read(defaults)
        wallpaperFollows = DeskTheme.wallpaperFollows(defaults)
        iconsFollow = DeskTheme.iconsFollow(defaults)
        // Review pictures can show any look without changing anything: DESK_THEME_PREVIEW=rose-gold/deco
        if let preview = ProcessInfo.processInfo.environment["DESK_THEME_PREVIEW"] {
            let parts = preview.split(separator: "/").map(String.init)
            choice = DeskTheme.choice(colour: parts.first, pattern: parts.count > 1 ? parts[1] : nil)
            isPreview = true
            return
        }
        let centre = DistributedNotificationCenter.default()
        observers.append(centre.addObserver(forName: Notification.Name(DeskTheme.changedNotification), object: nil, queue: .main) { [weak self] _ in
            self?.reload()
            // Preferences can reach this app a moment after the notification, so look once more.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.reload() }
        })
        // A screensaver installed after a theme was chosen still gets told the colour.
        if DeskTheme.hasChosen(defaults) { ThemeApply.writeSaverFile(for: choice) }
    }

    var accent: Color { Color(theme: choice.colour.accent) }
    var accentDim: Color { Color(theme: choice.colour.accentDim) }
    var accentDeep: Color { Color(theme: choice.colour.accentDeep) }

    /// Re-reads the shared choice (another add-on changed it).
    func reload() {
        let c = DeskTheme.read(defaults)
        if c != choice { choice = c }
        let w = DeskTheme.wallpaperFollows(defaults)
        if w != wallpaperFollows { wallpaperFollows = w }
        let i = DeskTheme.iconsFollow(defaults)
        if i != iconsFollow { iconsFollow = i }
    }

    /// Picks a colour and/or pattern for every add-on, then changes the wallpaper, screensaver and folder icons to match.
    func choose(colour: ThemeColour? = nil, pattern: ThemePattern? = nil) {
        guard !isPreview else { return }
        reload()   // another add-on may have changed the other half of the choice
        let new = DeskThemeChoice(colour: colour ?? choice.colour, pattern: pattern ?? choice.pattern)
        let firstTime = !DeskTheme.hasChosen(defaults)
        guard new != choice || firstTime else { return }
        DeskTheme.write(new, to: defaults)
        choice = new
        if wallpaperFollows { ThemeApply.setWallpaper(for: new, defaults: defaults) }
        ThemeApply.writeSaverFile(for: new)
        defaults.synchronize()
        ThemeApply.announce(DeskTheme.changedNotification)
        // Let the new colours paint first; the icons take a moment.
        if iconsFollow {
            let d = defaults
            // Read the choice again when it runs, in case another add-on picked a newer look meanwhile.
            DispatchQueue.main.async { ThemeApply.applyIcons(for: DeskTheme.read(d), defaults: d, onlyPending: false) }
        }
    }

    func setWallpaperFollows(_ on: Bool) {
        reload()
        defaults.set(on, forKey: DeskTheme.Key.wallpaperFollows)
        wallpaperFollows = on
        if on, DeskTheme.hasChosen(defaults) { ThemeApply.setWallpaper(for: choice, defaults: defaults) }
        defaults.synchronize()
        ThemeApply.announce(DeskTheme.changedNotification)
    }

    func setIconsFollow(_ on: Bool) {
        reload()
        defaults.set(on, forKey: DeskTheme.Key.iconsFollow)
        iconsFollow = on
        if on, DeskTheme.hasChosen(defaults) { ThemeApply.applyIcons(for: choice, defaults: defaults, onlyPending: true) }
        defaults.synchronize()
        ThemeApply.announce(DeskTheme.changedNotification)
    }

    /// Puts your original gold icons back on every folder in the list (and stops them following the theme).
    func putBackOriginalIcons() {
        // Before any theme is chosen the icons are already your originals.
        guard DeskTheme.hasChosen(defaults) else { return }
        defaults.set(false, forKey: DeskTheme.Key.iconsFollow)
        iconsFollow = false
        ThemeApply.applyIcons(for: .standard, defaults: defaults, onlyPending: false)
        defaults.synchronize()
        ThemeApply.announce(DeskTheme.changedNotification)
    }

    /// Catches up folders the last change couldn't reach (such as the SSD when it was unplugged). Safe to call often.
    func catchUpIcons() {
        guard !isPreview, DeskTheme.hasChosen(defaults), iconsFollow else { return }
        ThemeApply.applyIcons(for: choice, defaults: defaults, onlyPending: true)
    }
}

extension Color {
    init(theme c: ThemeRGB) { self.init(red: c.r, green: c.g, blue: c.b) }
}

/// Right-click > Theme. The same menu in every add-on; a tick shows the current colour and pattern.
struct ThemeMenu: View {
    private var theme: ThemeLive { ThemeLive.shared }

    var body: some View {
        Menu("Theme") {
            Section("Colour") {
                ForEach(ThemeColour.allCases, id: \.self) { c in
                    Toggle(c.title, isOn: Binding(get: { theme.choice.colour == c }, set: { _ in theme.choose(colour: c) }))
                }
            }
            Section("Pattern") {
                ForEach(ThemePattern.allCases, id: \.self) { p in
                    Toggle(p.title, isOn: Binding(get: { theme.choice.pattern == p }, set: { _ in theme.choose(pattern: p) }))
                }
            }
            Divider()
            Toggle("Wallpaper Follows Theme", isOn: Binding(get: { theme.wallpaperFollows }, set: { theme.setWallpaperFollows($0) }))
            Toggle("Folder Icons Follow Theme", isOn: Binding(get: { theme.iconsFollow }, set: { theme.setIconsFollow($0) }))
            Button("Put Back My Original Folder Icons") { theme.putBackOriginalIcons() }
        }
    }
}

/// The parts that change the Mac: wallpaper, screensaver file and folder icons.
enum ThemeApply {
    /// The real home folder (these apps aren't sandboxed).
    static var home: URL { URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true) }

    static func announce(_ name: String) {
        DistributedNotificationCenter.default().postNotificationName(Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Sets the matching wallpaper on every screen. Missing file: leaves the wallpaper alone.
    static func setWallpaper(for c: DeskThemeChoice, defaults: UserDefaults) {
        let url = DeskTheme.wallpaperURL(for: c, home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // Remember the wallpaper you had before the first change, so it can always be found again.
        if defaults.string(forKey: DeskTheme.Key.originalWallpaperPath) == nil, let s = NSScreen.main,
           let old = NSWorkspace.shared.desktopImageURL(for: s) {
            defaults.set(old.path, forKey: DeskTheme.Key.originalWallpaperPath)
        }
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        defaults.set(url.path, forKey: DeskTheme.Key.wallpaperPath)
    }

    /// Writes "Desk Theme.txt" beside the installed screensaver so Liquid Gold Glint can follow the colour.
    static func writeSaverFile(for c: DeskThemeChoice) {
        let dir = home.appendingPathComponent("Library/Screen Savers", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try? DeskTheme.saverFileContents(for: c).write(to: dir.appendingPathComponent(DeskTheme.saverFileName), atomically: true, encoding: .utf8)
    }

    /// Changes each listed folder's icon to this choice. Only folders that already have a custom icon are touched,
    /// and each one's current icon is saved to Themes/Backups the first time.
    static func applyIcons(for c: DeskThemeChoice, defaults: UserDefaults, onlyPending: Bool) {
        guard let data = try? Data(contentsOf: DeskTheme.folderListURL(home: home)) else { return }
        let targets = DeskTheme.targets(fromJSON: data)
        var applied = defaults.dictionary(forKey: DeskTheme.Key.appliedIcons) as? [String: String] ?? [:]
        let todo = onlyPending ? DeskTheme.pending(targets, applied: applied, choice: c) : targets
        guard !todo.isEmpty else { return }
        let fm = FileManager.default
        var changed = false
        for t in todo {
            let folder = DeskTheme.expand(t.path, home: home)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue, hasCustomIcon(folder) else { continue }
            guard let image = NSImage(contentsOf: DeskTheme.iconURL(named: t.icon, for: c, home: home)) else { continue }
            let backup = backUpOnce(folder, path: t.path)
            if NSWorkspace.shared.setIcon(image, forFile: folder.path, options: []) {
                applied[t.path] = c.key
                changed = true
            } else if let backup {
                // macOS said no (no access yet): the saved picture may not be the real icon, so try again next time.
                try? fm.removeItem(at: backup)
            }
        }
        defaults.set(applied, forKey: DeskTheme.Key.appliedIcons)
        if changed { announce(DeskTheme.iconsChangedNotification) }
    }

    /// A folder's own icon lives in a hidden "Icon\r" file; a drive's in ".VolumeIcon.icns".
    static func hasCustomIcon(_ folder: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: folder.appendingPathComponent("Icon\r").path)
            || fm.fileExists(atPath: folder.appendingPathComponent(".VolumeIcon.icns").path)
    }

    /// Saves what the folder looks like now, once, so nothing is ever lost.
    /// Returns the backup file if this call made it.
    @discardableResult
    static func backUpOnce(_ folder: URL, path: String) -> URL? {
        let dir = DeskTheme.backupsFolder(home: home)
        let file = dir.appendingPathComponent(DeskTheme.backupName(for: path))
        let fm = FileManager.default
        guard !fm.fileExists(atPath: file.path) else { return nil }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let icon = NSWorkspace.shared.icon(forFile: folder.path)
        let size = NSSize(width: 1024, height: 1024)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: file)) != nil else { return nil }
        return file
    }
}
