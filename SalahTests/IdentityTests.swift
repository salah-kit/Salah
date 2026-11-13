import Foundation
import SalahCore
import SalahWidgets
import Testing

/// Salah's identity where two processes must agree on it: the App Group the app and the
/// widget extension share, and the names they signal each other with.
@Suite("Identity")
struct IdentityTests {
  init() { TestEnvironment.configure() }

  /// The targets that open the App Group: each app, its extensions, and the Mac test
  /// processes that read what the app publishes.
  nonisolated static let targetsInTheAppGroup = [
    "Salah", "SalahWidgetsExtension", "SalahStopHarness", "SalahUITests",
    "SalahIOS", "SalahIOSWidgets", "SalahTV", "SalahTVTopShelf",
    "SalahWatch", "SalahWatchWidgets",
  ]

  /// Each of them takes its App Group from the one build setting, in its entitlements and
  /// in the Info.plist key the code reads, so the processes of a build always open the same
  /// group: the widget reads what the app writes.
  @Test(arguments: targetsInTheAppGroup)
  func targetTakesItsAppGroupFromTheBuild(_ target: String) throws {
    let folder = BaselineStore.repositoryRoot.appending(path: target)
    let entitlements = try Self.propertyList(folder.appending(path: "\(target).entitlements"))
    #expect(
      entitlements["com.apple.security.application-groups"] as? [String]
        == ["$(APP_GROUP_IDENTIFIER)"])
    let info = try Self.propertyList(folder.appending(path: "Info.plist"))
    #expect(info["AppGroupIdentifier"] as? String == "$(APP_GROUP_IDENTIFIER)")
  }

  /// The test above leaves out no target that has entitlements.
  @Test func everyTargetWithEntitlementsIsChecked() throws {
    let root = BaselineStore.repositoryRoot
    let folders = try FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: nil)
    let withEntitlements = folders.map(\.lastPathComponent).filter {
      FileManager.default.fileExists(atPath: root.appending(path: "\($0)/\($0).entitlements").path)
    }
    #expect(Set(withEntitlements) == Set(Self.targetsInTheAppGroup))
  }

  /// Salah's own identifiers are the build's defaults, the ones the scripts pin, and the
  /// App Group a process without a build's Info.plist opens, as these tests' runner does.
  @Test func salahsOwnIdentifiersAreTheDefaults() throws {
    let root = BaselineStore.repositoryRoot
    #expect(SalahWidgetConstants.appGroupID == "group.com.omarkhaled.salah")
    let settings = try String(
      contentsOf: root.appending(path: "Config/Shared.xcconfig"), encoding: .utf8)
    #expect(settings.contains("\nAPP_BUNDLE_IDENTIFIER = com.omarkhaled.salah\n"))
    #expect(settings.contains("\nAPP_GROUP_IDENTIFIER = \(SalahWidgetConstants.appGroupID)\n"))
    let scripts = try String(
      contentsOf: root.appending(path: "scripts/identity.sh"), encoding: .utf8)
    #expect(scripts.contains("\nbundle_identifier=com.omarkhaled.salah\n"))
    #expect(scripts.contains("\napp_group=\(SalahWidgetConstants.appGroupID)\n"))
  }

  /// The permission journey must find the installed iPhone app in Settings, including
  /// when the simulator ignores the direct Settings link.
  @Test func iOSPermissionJourneyUsesTheMainAppIdentifier() throws {
    let info = try Self.propertyList(
      BaselineStore.repositoryRoot.appending(path: "SalahIOSUITests/Info.plist"))
    #expect(info["AppBundleIdentifier"] as? String == "$(APP_BUNDLE_IDENTIFIER)")
  }

  private static func propertyList(_ url: URL) throws -> [String: Any] {
    try #require(
      PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: Any])
  }

  /// The names the app and the extension exchange are Salah's own.
  @Test func sharedNamesAreSalahs() {
    #expect(
      SalahWidgetConstants.prayerTimesWidgetKind == "com.omarkhaled.salah.widgets.prayerTimes")
    #expect(SalahWidgetConstants.stopAudioSignal == "com.omarkhaled.salah.widget.stopAudio")
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
    #expect(claim["CFBundleURLName"] as? String == "com.omarkhaled.salah")
    #expect(claim["CFBundleTypeRole"] as? String == "Editor")
  }

  /// Prayer alerts are requested under the app's bundle identifier, in one namespace, a
  /// notification thread per prayer day and one category.
  @Test func alertIdentifiersAreSalahs() {
    #expect(PrayerAlertCoordinator.identifierPrefix == "com.omarkhaled.salah.")
    #expect(PrayerAlertCoordinator.namespace == "prayers")
    #expect(
      PrayerAlertCoordinator.threadIdentifier(for: CivilDay(year: 2026, month: 6, day: 2))
        == "salah-prayers-2026-06-02")
    #expect(PrayerAlertCoordinator.categoryIdentifier == "salah-prayer")
    #expect(
      PrayerAlertCoordinator.isPrayerAlert(
        "com.omarkhaled.salah.prayers/2026-06-02/dhuhr/before"))
    #expect(!PrayerAlertCoordinator.isPrayerAlert("salah.prayer.dhuhr.preReminder.1780391340"))
  }
}
