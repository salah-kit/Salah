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

  /// Every defaults suite the tests use keeps its file in this run's own folder
  /// under the temporary directory: nothing lands in `~/Library/Preferences`, and
  /// two test runs at once never share a suite.
  @Test func defaultsSuitesLiveInTheRunsOwnFolder() {
    let folder = TestEnvironment.preferencesDirectory
    #expect(folder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    #expect(TestEnvironment.sharedSuiteName.hasPrefix(folder.path + "/"))

    let scratch = ScratchDefaults()
    scratch.defaults.set(true, forKey: "probe")
    #expect(CFPreferencesAppSynchronize(scratch.suiteName as CFString))
    let file = URL(fileURLWithPath: scratch.suiteName + ".plist")
    #expect(file.deletingLastPathComponent().path == folder.path)
    #expect(FileManager.default.fileExists(atPath: file.path))
    let library = FileManager.default.homeDirectoryForCurrentUser.appending(
      path: "Library/Preferences")
    #expect(
      !FileManager.default.fileExists(atPath: library.appending(path: file.lastPathComponent).path))
    #expect(ScratchDefaults().suiteName != scratch.suiteName)
  }

  /// The scheme pins the test process's preferred languages. With a tall script such
  /// as Arabic among them, macOS gives system-font text taller lines in every
  /// language, so every visual baseline would depend on the machine's list.
  @Test func processLanguagesArePinned() {
    #expect(Locale.preferredLanguages == ["en-US"])
  }

  /// The scheme's test action builds only this bundle. A build of the app registers
  /// its widget extension with PlugInKit under the identifier of the Guidance
  /// installed on the machine, and PlugInKit can then serve that user's widget from
  /// the build folder.
  @Test func testActionDoesNotBuildTheApp() throws {
    let scheme = BaselineStore.repositoryRoot.appending(
      path: "Salah.xcodeproj/xcshareddata/xcschemes/Salah.xcscheme")
    let document = try XMLDocument(contentsOf: scheme)
    let app = try document.nodes(
      forXPath: "//BuildActionEntry[BuildableReference/@BuildableName='Salah.app']")
    #expect(app.count == 1)
    let buildForTesting = try document.nodes(
      forXPath:
        "//BuildActionEntry[BuildableReference/@BuildableName='Salah.app']/@buildForTesting")
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

  /// Adding a request whose identifier is pending replaces it, as Apple documents,
  /// also when the new request has no trigger and is delivered at once.
  @Test func fakeCenterReplacesAPendingRequestOnEveryAdd() async throws {
    let center = FakeNotificationCenter()
    let content = UNMutableNotificationContent()
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
    try await center.add(UNNotificationRequest(identifier: "a", content: content, trigger: trigger))
    try await center.add(UNNotificationRequest(identifier: "a", content: content, trigger: trigger))
    #expect(center.pending.map(\.identifier) == ["a"])
    try await center.add(UNNotificationRequest(identifier: "a", content: content, trigger: nil))
    #expect(center.pending.isEmpty)
    #expect(center.immediate.map(\.identifier) == ["a"])
  }
}
