import Foundation
import SalahCore
import SalahWidgets
import Testing

/// Salah's identity where two processes must agree on it: the App Group the app and the
/// widget extension share, and the names they signal each other with.
@Suite("Identity")
struct IdentityTests {
  init() { TestEnvironment.configure() }

  /// Each target takes its App Group from the one build setting, in its entitlements and
  /// in the Info.plist key the code reads, so the processes of a build always open the same
  /// group: the widget reads what the app writes.
  @Test(arguments: ["Salah", "SalahWidgetsExtension", "SalahStopHarness", "SalahUITests"])
  func targetTakesItsAppGroupFromTheBuild(_ target: String) throws {
    let folder = BaselineStore.repositoryRoot.appending(path: target)
    let entitlements = try Self.propertyList(folder.appending(path: "\(target).entitlements"))
    #expect(
      entitlements["com.apple.security.application-groups"] as? [String]
        == ["$(APP_GROUP_IDENTIFIER)"])
    let info = try Self.propertyList(folder.appending(path: "Info.plist"))
    #expect(info["AppGroupIdentifier"] as? String == "$(APP_GROUP_IDENTIFIER)")
  }

  /// Salah's own identifiers are the build's defaults, the ones the scripts pin, and the
  /// App Group a process without a build's Info.plist opens, as these tests' runner does.
  @Test func salahsOwnIdentifiersAreTheDefaults() throws {
    let root = BaselineStore.repositoryRoot
    #expect(SalahWidgetConstants.appGroupID == "group.io.github.salah-kit.Salah.shared")
    let settings = try String(
      contentsOf: root.appending(path: "Config/Shared.xcconfig"), encoding: .utf8)
    #expect(settings.contains("\nAPP_BUNDLE_IDENTIFIER = io.github.salah-kit.Salah\n"))
    #expect(settings.contains("\nAPP_GROUP_IDENTIFIER = \(SalahWidgetConstants.appGroupID)\n"))
    let scripts = try String(
      contentsOf: root.appending(path: "scripts/identity.sh"), encoding: .utf8)
    #expect(scripts.contains("\nbundle_identifier=io.github.salah-kit.Salah\n"))
    #expect(scripts.contains("\napp_group=\(SalahWidgetConstants.appGroupID)\n"))
  }

  private static func propertyList(_ url: URL) throws -> [String: Any] {
    try #require(
      PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: Any])
  }

  /// The names the app and the extension exchange are Salah's own.
  @Test func sharedNamesAreSalahs() {
    #expect(
      SalahWidgetConstants.prayerTimesWidgetKind == "io.github.salah-kit.Salah.widgets.prayerTimes")
    #expect(SalahWidgetConstants.stopAudioSignal == "io.github.salah-kit.Salah.widget.stopAudio")
    #expect(DarwinSignal.stopAudio.name == SalahWidgetConstants.stopAudioSignal)
    #expect(SalahWidgetConstants.settingsKey == "SalahSettings.v2")
    #expect(SalahWidgetConstants.playbackKey == "SalahPlayback.v1")
    #expect(SharedValue.settings.appGroup == SalahWidgetConstants.appGroupID)
    #expect(SharedValue.settings.key == SalahWidgetConstants.settingsKey)
    #expect(SharedValue.playback.appGroup == SalahWidgetConstants.appGroupID)
    #expect(SharedValue.playback.key == SalahWidgetConstants.playbackKey)
    #expect(SalahWidgetConstants.deepLinkScheme == "salah")
    #expect(SalahWidgetConstants.settingsDeepLinkURL.scheme == SalahWidgetConstants.deepLinkScheme)
  }

  /// LaunchServices checks the app's declared schemes before delivering a widget's
  /// Settings link from a sandboxed caller, even when the app is already running.
  @Test func appClaimsTheWidgetsSettingsURLScheme() throws {
    let info = try Self.propertyList(
      BaselineStore.repositoryRoot.appending(path: "Salah/Info.plist"))
    let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
    let claims = urlTypes.filter {
      ($0["CFBundleURLSchemes"] as? [String])?.contains(SalahWidgetConstants.deepLinkScheme) == true
    }
    #expect(claims.count == 1)
    let claim = try #require(claims.first)
    #expect(claim["CFBundleURLName"] as? String == "io.github.salah-kit.Salah")
    #expect(claim["CFBundleTypeRole"] as? String == "Editor")
  }

  /// Prayer alerts are requested under the app's bundle identifier, in one namespace, a
  /// notification thread per prayer day and one category.
  @Test func alertIdentifiersAreSalahs() {
    #expect(PrayerAlertCoordinator.identifierPrefix == "io.github.salah-kit.Salah.")
    #expect(PrayerAlertCoordinator.namespace == "prayers")
    #expect(
      PrayerAlertCoordinator.threadIdentifier(for: CivilDay(year: 2026, month: 6, day: 2))
        == "salah-prayers-2026-06-02")
    #expect(PrayerAlertCoordinator.categoryIdentifier == "salah-prayer")
    #expect(
      PrayerAlertCoordinator.isPrayerAlert(
        "io.github.salah-kit.Salah.prayers/2026-06-02/dhuhr/before"))
    #expect(!PrayerAlertCoordinator.isPrayerAlert("salah.prayer.dhuhr.preReminder.1780391340"))
  }
}
