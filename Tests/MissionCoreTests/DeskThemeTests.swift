import XCTest
@testable import MissionCore

/// Checks for the shared Desk Theme file (the same tests in every add-on).
final class DeskThemeTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "desktheme.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return d
    }

    func testAmberDuskIsTodaysLook() {
        XCTAssertEqual(ThemeColour.amberDusk.accent.hexString, "#FFC970")
        XCTAssertEqual(ThemeColour.amberDusk.accentDim.hexString, "#F0C27A")
        XCTAssertTrue(DeskThemeChoice.standard.isOriginal)
        XCTAssertEqual(DeskThemeChoice.standard.key, "amber-dusk/lines")
    }

    func testNothingChosenReadsAsTodaysLook() {
        let d = freshDefaults()
        XCTAssertEqual(DeskTheme.read(d), .standard)
        XCTAssertFalse(DeskTheme.hasChosen(d))
        XCTAssertTrue(DeskTheme.wallpaperFollows(d))
        XCTAssertTrue(DeskTheme.iconsFollow(d))
    }

    func testChoiceRoundTripsAndPublishesHexForOtherApps() {
        let d = freshDefaults()
        let c = DeskThemeChoice(colour: .roseGold, pattern: .artDeco)
        DeskTheme.write(c, to: d)
        XCTAssertEqual(DeskTheme.read(d), c)
        XCTAssertTrue(DeskTheme.hasChosen(d))
        XCTAssertEqual(d.string(forKey: DeskTheme.Key.accentHex), "#F7B5A6")
        XCTAssertEqual(d.string(forKey: DeskTheme.Key.colour), "rose-gold")
        XCTAssertEqual(d.string(forKey: DeskTheme.Key.pattern), "deco")
    }

    func testUnknownValuesFallBackToDefault() {
        XCTAssertEqual(DeskTheme.choice(colour: "purple", pattern: "zigzag"), .standard)
        XCTAssertEqual(DeskTheme.choice(colour: "emerald", pattern: nil), DeskThemeChoice(colour: .emerald, pattern: .goldLines))
    }

    func testEveryColourAndPatternHasDistinctNamesAndColours() {
        XCTAssertEqual(ThemeColour.allCases.count, 6)
        XCTAssertEqual(ThemePattern.allCases.count, 6)
        XCTAssertEqual(Set(ThemeColour.allCases.map(\.title)).count, 6)
        XCTAssertEqual(Set(ThemeColour.allCases.map(\.accent.hexString)).count, 6)
        XCTAssertEqual(Set(ThemePattern.allCases.map(\.title)).count, 6)
        XCTAssertEqual(Set(ThemeColour.allCases.map(\.wealthWallpaper)).count, 6)
    }

    func testGlintColourwaysMatchTheScreensaver() {
        XCTAssertEqual(ThemeColour.allCases.map(\.glintColourway),
                       ["goldNavy", "champagne", "roseGold", "platinum", "emerald", "oxblood"])
    }

    func testOriginalIconsAndWallpaperForTodaysLook() {
        let home = URL(fileURLWithPath: "/Users/a", isDirectory: true)
        XCTAssertEqual(DeskTheme.iconURL(named: "cpd", for: .standard, home: home).path,
                       "/Users/a/Developer/Wallpapers/Folder Icons/Named/cpd.png")
        XCTAssertEqual(DeskTheme.wallpaperURL(for: .standard, home: home).path,
                       "/Users/a/Developer/Wallpapers/wealth-gold-lines-macbook.png")
    }

    func testMadeIconsAndWallpapersForOtherLooks() {
        let home = URL(fileURLWithPath: "/Users/a", isDirectory: true)
        let silverLines = DeskThemeChoice(colour: .silverFrost, pattern: .goldLines)
        XCTAssertEqual(DeskTheme.iconURL(named: "ssd", for: silverLines, home: home).path,
                       "/Users/a/Developer/Wallpapers/Folder Icons/Themes/silver-frost/lines/ssd.png")
        XCTAssertEqual(DeskTheme.wallpaperURL(for: silverLines, home: home).path,
                       "/Users/a/Developer/Wallpapers/wealth-platinum-lines-macbook.png")
        let amberDeco = DeskThemeChoice(colour: .amberDusk, pattern: .artDeco)
        XCTAssertEqual(DeskTheme.iconURL(named: "cpd", for: amberDeco, home: home).path,
                       "/Users/a/Developer/Wallpapers/Folder Icons/Themes/amber-dusk/deco/cpd.png")
        XCTAssertEqual(DeskTheme.wallpaperURL(for: amberDeco, home: home).path,
                       "/Users/a/Developer/Wallpapers/Themes/amber-dusk-deco.jpg")
    }

    func testFolderListSkipsBadEntries() {
        let json = """
        [{"path": "~/Desktop/CPD", "icon": "cpd"},
         {"path": "", "icon": "nxu"},
         {"path": "~/Desktop/NoIcon"},
         {"path": "~/Desktop/X", "icon": "../../etc"},
         {"path": "/Volumes/awilliam", "icon": "ssd"}]
        """
        let t = DeskTheme.targets(fromJSON: Data(json.utf8))
        XCTAssertEqual(t, [ThemeIconTarget(path: "~/Desktop/CPD", icon: "cpd"), ThemeIconTarget(path: "/Volumes/awilliam", icon: "ssd")])
        XCTAssertEqual(DeskTheme.targets(fromJSON: Data("not json".utf8)), [])
    }

    func testExpandAndBackupNames() {
        let home = URL(fileURLWithPath: "/Users/a", isDirectory: true)
        XCTAssertEqual(DeskTheme.expand("~/Desktop/CPD", home: home).path, "/Users/a/Desktop/CPD")
        XCTAssertEqual(DeskTheme.expand("/Volumes/awilliam", home: home).path, "/Volumes/awilliam")
        XCTAssertEqual(DeskTheme.backupName(for: "~/Desktop/Calming Music"), "Desktop - Calming Music.png")
        XCTAssertEqual(DeskTheme.backupName(for: "/Volumes/awilliam"), "Volumes - awilliam.png")
    }

    func testOnlyFoldersNotYetChangedArePending() {
        let a = ThemeIconTarget(path: "~/Desktop/CPD", icon: "cpd")
        let b = ThemeIconTarget(path: "/Volumes/awilliam", icon: "ssd")
        let c = DeskThemeChoice(colour: .emerald, pattern: .honeycomb)
        XCTAssertEqual(DeskTheme.pending([a, b], applied: [a.path: c.key], choice: c), [b])
        XCTAssertEqual(DeskTheme.pending([a, b], applied: [a.path: "amber-dusk/lines"], choice: c), [a, b])
    }

    func testScreensaverFileRoundTrip() {
        let text = DeskTheme.saverFileContents(for: DeskThemeChoice(colour: .silverFrost, pattern: .plain))
        XCTAssertEqual(DeskTheme.saverColourway(fromFile: text), "platinum")
        XCTAssertNil(DeskTheme.saverColourway(fromFile: "pattern=plain\n"))
        XCTAssertEqual(DeskTheme.saverColourway(fromFile: " colourway = emerald \r\n"), "emerald")
    }
}
