import Foundation
import Testing

/// Guards the harness itself: if these fail, every other result is suspect.
@Suite("Test environment")
struct TestEnvironmentTests {
  init() { TestEnvironment.configure() }

  @Test func sharedPreferencesNeverUseTheRealDefaults() {
    #expect(Preferences.shared.defaults !== UserDefaults.standard)
    #expect(Preferences.shared.appLanguage == .english)
  }

  @Test func processTimeZoneIsTheFixtureZone() {
    #expect(TimeZone.current.identifier == "Asia/Riyadh")
    #expect(Calendar.current.timeZone.identifier == "Asia/Riyadh")
  }

  @Test func catalogAndSoundsResolveFromTheTestBundle() {
    #expect(AppResources.bundle != Bundle.main)
    #expect(localizedString("prayer.fajr", locale: Locale(identifier: "en")) == "Fajr")
    #expect(localizedString("prayer.fajr", locale: AppLanguage.arabic.locale) == "الفجر")
    #expect(
      localizedString("prayer.sunrise", locale: Locale(identifier: "fr")) == "Lever du soleil")
    #expect(BuiltInAdhanSound.allCases.allSatisfy { $0.bundledURL != nil })
    #expect(AppResources.bundle.url(forResource: "Dua", withExtension: "m4a") != nil)
  }
}
