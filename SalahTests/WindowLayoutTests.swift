import AppKit
import Testing

/// Salah's window: Today's columns, the pane a Debug launch opens on, and the layout
/// direction AppKit takes from the app's language.
@Suite("Window layout")
struct WindowLayoutTests {
  init() { TestEnvironment.configure() }

  /// The next prayer is as wide as the prayers card's rows: the card is wider by its inset
  /// on each side, and the two with their gap fill the width.
  @Test func theNextPrayerIsAsWideAsThePrayerRows() {
    let columns = TodayColumns(spacing: 20, inset: 6)
    let (first, second) = columns.widths(610)
    #expect(first == 289)
    #expect(second == 301)
    #expect(first + 20 + second == 610)
    #expect(columns.widths(10) == (0, 12), "Never negative")
  }

  /// A Debug launch can open the window on a pane by its name.
  @Test func readsTheLaunchPane() {
    let scratch = ScratchDefaults()
    scratch.defaults.set("notifications", forKey: DebugOptions.paneKey)
    #expect(DebugOptions.pane(defaults: scratch.defaults) == .notifications)
    scratch.defaults.set("settings", forKey: DebugOptions.paneKey)
    #expect(DebugOptions.pane(defaults: scratch.defaults) == nil)
  }

  /// Light and Dark set the app's appearance; System leaves it to macOS.
  @Test @MainActor func theAppearanceSettingSetsTheApps() {
    #expect(AppAppearance.appearance(for: .system) == nil)
    #expect(AppAppearance.appearance(for: .light)?.name == .aqua)
    #expect(AppAppearance.appearance(for: .dark)?.name == .darkAqua)
  }

  /// AppKit lays out right to left for Arabic, Urdu and Persian, left to right for the other
  /// languages, and as the system does when Salah follows it.
  @Test @MainActor func theAppLanguageSetsAppKitsDirection() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    // The store's own value, not the Mac's global one.
    func stored() -> Bool? {
      scratch.defaults.persistentDomain(forName: scratch.suiteName)?["AppleTextDirection"] as? Bool
    }
    preferences.appLanguage = .arabic
    #expect(stored() == true)
    preferences.appLanguage = .english
    #expect(stored() == false)
    preferences.appLanguage = .system
    #expect(stored() == nil)
    for language in AppLanguage.allCases where language != .system {
      #expect(
        language.appleTextDirectionOverride
          == (language.locale.language.characterDirection == .rightToLeft), "\(language)")
    }
  }
}
