import Foundation

// MARK: - Desk Theme (shared file)
//
// One colour and one pattern, chosen from the right-click Theme menu of any desktop add-on and followed by all of them:
// Mission Control Widget, Smart Corner, Desk Drawer, Horizon Strip and Liquid Gold Glint.
// The same file lives in each app's core module. Keep every copy identical.
//
// How the apps talk to each other (also the hook for anything new, such as a future wallpaper app):
//   • The choice is stored in the shared preferences suite "com.azferwilliam.desktheme"
//     (keys below; accentHex / accentDimHex / wallpaperPath are written for apps that don't know these types).
//   • After a change, the app that changed it posts the distributed notification "com.azferwilliam.desktheme.changed".
//   • After folder icons change, it posts "com.azferwilliam.desktheme.iconsChanged".
// Nothing changes on the Mac until a theme has been chosen at least once (Key.chosen).

/// A colour as red, green and blue from 0 to 1.
public struct ThemeRGB: Equatable, Sendable {
    public let r: Double, g: Double, b: Double

    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    /// "#FFC970"
    public var hexString: String {
        let v = [r, g, b].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }
}

/// The six colours. Amber Dusk is today's look and the default.
public enum ThemeColour: String, CaseIterable, Sendable {
    case amberDusk = "amber-dusk"
    case champagne = "champagne"
    case roseGold = "rose-gold"
    case silverFrost = "silver-frost"
    case emerald = "emerald"
    case oxblood = "oxblood"

    public var title: String {
        switch self {
        case .amberDusk: return "Amber Dusk"
        case .champagne: return "Champagne"
        case .roseGold: return "Rose Gold"
        case .silverFrost: return "Silver Frost"
        case .emerald: return "Emerald"
        case .oxblood: return "Oxblood"
        }
    }

    /// The highlight colour on glass (was "amber").
    public var accent: ThemeRGB {
        switch self {
        case .amberDusk: return ThemeRGB(hex: 0xFFC970)
        case .champagne: return ThemeRGB(hex: 0xF2E3C4)
        case .roseGold: return ThemeRGB(hex: 0xF7B5A6)
        case .silverFrost: return ThemeRGB(hex: 0xDCE6F2)
        case .emerald: return ThemeRGB(hex: 0x86E3B8)
        case .oxblood: return ThemeRGB(hex: 0xFFA877)
        }
    }

    /// A softer partner to the accent, for secondary highlights and gradients (was "amberDim").
    public var accentDim: ThemeRGB {
        switch self {
        case .amberDusk: return ThemeRGB(hex: 0xF0C27A)
        case .champagne: return ThemeRGB(hex: 0xDCCBA8)
        case .roseGold: return ThemeRGB(hex: 0xE39D8E)
        case .silverFrost: return ThemeRGB(hex: 0xBAC6D4)
        case .emerald: return ThemeRGB(hex: 0xD6B468)
        case .oxblood: return ThemeRGB(hex: 0xDEA054)
        }
    }

    /// The deeper end of gradients (Smart Corner's progress bars).
    public var accentDeep: ThemeRGB {
        switch self {
        case .amberDusk: return ThemeRGB(hex: 0xE8B55E)
        case .champagne: return ThemeRGB(hex: 0xCDB98F)
        case .roseGold: return ThemeRGB(hex: 0xD98D7E)
        case .silverFrost: return ThemeRGB(hex: 0xA3B1C2)
        case .emerald: return ThemeRGB(hex: 0x5FC496)
        case .oxblood: return ThemeRGB(hex: 0xE8895A)
        }
    }

    /// The matching Liquid Gold Glint colourway (its Colourway raw value).
    public var glintColourway: String {
        switch self {
        case .amberDusk: return "goldNavy"
        case .champagne: return "champagne"
        case .roseGold: return "roseGold"
        case .silverFrost: return "platinum"
        case .emerald: return "emerald"
        case .oxblood: return "oxblood"
        }
    }

    /// Your own wealth wallpaper in this colour (in ~/Developer/Wallpapers), used with the Gold Lines pattern.
    public var wealthWallpaper: String {
        switch self {
        case .amberDusk: return "wealth-gold-lines-macbook.png"
        case .champagne: return "wealth-champagne-minimal-macbook.png"
        case .roseGold: return "wealth-rose-gold-lines-macbook.png"
        case .silverFrost: return "wealth-platinum-lines-macbook.png"
        case .emerald: return "wealth-emerald-gold-lines-macbook.png"
        case .oxblood: return "wealth-oxblood-gold-lines-macbook.png"
        }
    }
}

/// The six patterns behind the folder labels and on the wallpaper.
public enum ThemePattern: String, CaseIterable, Sendable {
    case goldLines = "lines"
    case artDeco = "deco"
    case constellation = "constellation"
    case honeycomb = "honeycomb"
    case pinstripe = "pinstripe"
    case plain = "plain"

    public var title: String {
        switch self {
        case .goldLines: return "Gold Lines"
        case .artDeco: return "Art Deco"
        case .constellation: return "Constellation"
        case .honeycomb: return "Honeycomb"
        case .pinstripe: return "Pinstripe"
        case .plain: return "Plain"
        }
    }
}

/// One colour plus one pattern.
public struct DeskThemeChoice: Equatable, Sendable {
    public var colour: ThemeColour
    public var pattern: ThemePattern

    public init(colour: ThemeColour, pattern: ThemePattern) {
        self.colour = colour
        self.pattern = pattern
    }

    /// Today's look: Amber Dusk with Gold Lines, using your original icons and wallpaper.
    public static let standard = DeskThemeChoice(colour: .amberDusk, pattern: .goldLines)

    public var isOriginal: Bool { self == .standard }

    /// "amber-dusk/lines": recorded against each folder once its icon matches this choice.
    public var key: String { "\(colour.rawValue)/\(pattern.rawValue)" }

    public var title: String { "\(colour.title), \(pattern.title)" }
}

/// One folder (or drive) whose icon follows the theme, from folders.json.
public struct ThemeIconTarget: Codable, Equatable, Sendable {
    /// "~/Desktop/CPD" or "/Volumes/awilliam".
    public var path: String
    /// The icon's file name without ".png", such as "cpd" or "ssd".
    public var icon: String

    public init(path: String, icon: String) {
        self.path = path
        self.icon = icon
    }
}

public enum DeskTheme {
    public static let suiteName = "com.azferwilliam.desktheme"
    public static let changedNotification = "com.azferwilliam.desktheme.changed"
    public static let iconsChangedNotification = "com.azferwilliam.desktheme.iconsChanged"

    public enum Key {
        public static let colour = "colour"
        public static let pattern = "pattern"
        /// True once a theme has been picked. Until then nothing on the Mac is changed.
        public static let chosen = "chosen"
        public static let wallpaperFollows = "wallpaperFollows"     // default true
        public static let iconsFollow = "iconsFollow"               // default true
        public static let accentHex = "accentHex"
        public static let accentDimHex = "accentDimHex"
        public static let wallpaperPath = "wallpaperPath"
        /// The wallpaper you had before the first theme change.
        public static let originalWallpaperPath = "originalWallpaperPath"
        /// [folder path from folders.json: choice key] for icons already changed.
        public static let appliedIcons = "appliedIcons"
    }

    // MARK: Reading and writing the choice

    public static func choice(colour: String?, pattern: String?) -> DeskThemeChoice {
        DeskThemeChoice(colour: colour.flatMap(ThemeColour.init(rawValue:)) ?? .amberDusk,
                        pattern: pattern.flatMap(ThemePattern.init(rawValue:)) ?? .goldLines)
    }

    public static func read(_ d: UserDefaults) -> DeskThemeChoice {
        choice(colour: d.string(forKey: Key.colour), pattern: d.string(forKey: Key.pattern))
    }

    public static func write(_ c: DeskThemeChoice, to d: UserDefaults) {
        d.set(c.colour.rawValue, forKey: Key.colour)
        d.set(c.pattern.rawValue, forKey: Key.pattern)
        d.set(c.colour.accent.hexString, forKey: Key.accentHex)
        d.set(c.colour.accentDim.hexString, forKey: Key.accentDimHex)
        d.set(true, forKey: Key.chosen)
    }

    public static func hasChosen(_ d: UserDefaults) -> Bool { d.bool(forKey: Key.chosen) }

    public static func wallpaperFollows(_ d: UserDefaults) -> Bool {
        d.object(forKey: Key.wallpaperFollows) as? Bool ?? true
    }

    public static func iconsFollow(_ d: UserDefaults) -> Bool {
        d.object(forKey: Key.iconsFollow) as? Bool ?? true
    }

    // MARK: Files (all in ~/Developer/Wallpapers)

    public static func wallpapersFolder(home: URL) -> URL {
        home.appendingPathComponent("Developer/Wallpapers", isDirectory: true)
    }

    public static func iconsFolder(home: URL) -> URL {
        wallpapersFolder(home: home).appendingPathComponent("Folder Icons", isDirectory: true)
    }

    /// Where the made-for-the-theme icons, wallpapers, folder list and backups live.
    public static func themesFolder(home: URL) -> URL {
        iconsFolder(home: home).appendingPathComponent("Themes", isDirectory: true)
    }

    /// Gold Lines uses your own wealth wallpapers; other patterns use the matching made ones.
    public static func wallpaperURL(for c: DeskThemeChoice, home: URL) -> URL {
        if c.pattern == .goldLines {
            return wallpapersFolder(home: home).appendingPathComponent(c.colour.wealthWallpaper)
        }
        return wallpapersFolder(home: home).appendingPathComponent("Themes/\(c.colour.rawValue)-\(c.pattern.rawValue).jpg")
    }

    /// Amber Dusk with Gold Lines is your untouched original; every other look has its own copy.
    public static func iconURL(named icon: String, for c: DeskThemeChoice, home: URL) -> URL {
        if c.isOriginal {
            return iconsFolder(home: home).appendingPathComponent("Named/\(icon).png")
        }
        return themesFolder(home: home).appendingPathComponent("\(c.colour.rawValue)/\(c.pattern.rawValue)/\(icon).png")
    }

    public static func folderListURL(home: URL) -> URL {
        themesFolder(home: home).appendingPathComponent("folders.json")
    }

    public static func backupsFolder(home: URL) -> URL {
        themesFolder(home: home).appendingPathComponent("Backups", isDirectory: true)
    }

    /// A file name for a folder's backup icon: "~/Desktop/CPD" → "Desktop - CPD.png".
    public static func backupName(for path: String) -> String {
        var p = path
        if p.hasPrefix("~/") { p.removeFirst(2) }
        let parts = p.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        let name = parts.joined(separator: " - ")
        return (name.isEmpty ? "root" : name) + ".png"
    }

    /// The folder list. Bad or missing entries are skipped; a broken file gives an empty list (nothing changes).
    public static func targets(fromJSON data: Data) -> [ThemeIconTarget] {
        struct Loose: Decodable { var path: String?; var icon: String? }
        guard let loose = try? JSONDecoder().decode([Loose].self, from: data) else { return [] }
        let list = loose.compactMap { e -> ThemeIconTarget? in
            guard let p = e.path, let i = e.icon else { return nil }
            return ThemeIconTarget(path: p, icon: i)
        }
        return list.filter { !$0.path.isEmpty && !$0.icon.isEmpty && !$0.icon.contains("/") && !$0.icon.contains("..") }
    }

    /// "~/Desktop/CPD" → /Users/you/Desktop/CPD. Absolute paths are kept.
    public static func expand(_ path: String, home: URL) -> URL {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home.appendingPathComponent(String(path.dropFirst(2))) }
        return URL(fileURLWithPath: path)
    }

    /// The folders that don't yet show this choice.
    public static func pending(_ targets: [ThemeIconTarget], applied: [String: String], choice: DeskThemeChoice) -> [ThemeIconTarget] {
        targets.filter { applied[$0.path] != choice.key }
    }

    /// The line Liquid Gold Glint reads to follow the theme.
    public static func saverFileContents(for c: DeskThemeChoice) -> String {
        "colourway=\(c.colour.glintColourway)\npattern=\(c.pattern.rawValue)\n"
    }

    /// Reads the colourway back out of that file ("goldNavy"), or nil.
    public static func saverColourway(fromFile text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "colourway", !parts[1].isEmpty { return parts[1] }
        }
        return nil
    }

    /// The file the screensaver reads, next to the installed saver.
    public static let saverFileName = "Desk Theme.txt"
}
