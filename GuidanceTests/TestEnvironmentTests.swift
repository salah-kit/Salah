import Foundation
import Testing
import UserNotifications

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

  /// A released suite's name is taken again, emptied, so runs leave a few preference
  /// files behind instead of one per test; suites in use at once never share a name.
  @Test func scratchSuitesReuseTheirNamesAndStartEmpty() {
    var first: ScratchDefaults? = ScratchDefaults()
    let name = first!.suiteName
    first!.defaults.set(true, forKey: "leftover")
    let other = ScratchDefaults()
    #expect(other.suiteName != name)

    first = nil
    let reused = ScratchDefaults()
    #expect(reused.suiteName == name)
    #expect(reused.defaults.object(forKey: "leftover") == nil)
  }

  /// The scheme's test action builds only this bundle. A build of the app registers
  /// its widget extension with PlugInKit under the identifier of the Guidance
  /// installed on the machine, and PlugInKit can then serve that user's widget from
  /// the build folder.
  @Test func testActionDoesNotBuildTheApp() throws {
    let scheme = BaselineStore.repositoryRoot.appending(
      path: "Guidance.xcodeproj/xcshareddata/xcschemes/Guidance.xcscheme")
    let document = try XMLDocument(contentsOf: scheme)
    let app = try document.nodes(
      forXPath: "//BuildActionEntry[BuildableReference/@BuildableName='Guidance.app']")
    #expect(app.count == 1)
    let buildForTesting = try document.nodes(
      forXPath:
        "//BuildActionEntry[BuildableReference/@BuildableName='Guidance.app']/@buildForTesting")
    #expect(buildForTesting.map(\.stringValue) == ["NO"])
  }

  /// The fake center holds its delegate weakly, like `UNUserNotificationCenter`, so
  /// a scheduler and the center it makes itself the delegate of don't keep each
  /// other alive.
  @Test func fakeCenterHoldsItsDelegateWeakly() {
    final class Delegate: NSObject, UNUserNotificationCenterDelegate {}
    let center = FakeNotificationCenter()
    var delegate: Delegate? = Delegate()
    center.delegate = delegate
    #expect(center.delegate != nil)
    delegate = nil
    #expect(center.delegate == nil)
  }
}
