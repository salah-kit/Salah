import Foundation
import SalahWidgets
import Testing

/// Salah's identity where two processes must agree on it: the App Group the app and the
/// widget extension share, and the names they signal each other with.
@Suite("Identity")
struct IdentityTests {
  init() { TestEnvironment.configure() }

  /// Each target's entitlements grant exactly the App Group the shared store opens, so
  /// the widget reads what the app writes.
  @Test(arguments: [
    "Salah/Salah.entitlements", "SalahWidgetsExtension/SalahWidgetsExtension.entitlements",
  ])
  func entitlementsGrantTheSharedAppGroup(_ path: String) throws {
    let url = BaselineStore.repositoryRoot.appending(path: path)
    let entitlements =
      try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
      as? [String: Any]
    let groups = entitlements?["com.apple.security.application-groups"] as? [String]
    #expect(groups == [SalahWidgetConstants.appGroupID])
    #expect(SalahWidgetConstants.appGroupID == "group.io.github.salah-kit.Salah")
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
    let url = BaselineStore.repositoryRoot.appending(path: "Salah/Info.plist")
    let info = try #require(
      PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: Any])
    let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
    let claims = urlTypes.filter {
      ($0["CFBundleURLSchemes"] as? [String])?.contains(SalahWidgetConstants.deepLinkScheme) == true
    }
    #expect(claims.count == 1)
    let claim = try #require(claims.first)
    #expect(claim["CFBundleURLName"] as? String == "io.github.salah-kit.Salah")
    #expect(claim["CFBundleTypeRole"] as? String == "Editor")
  }

  /// Prayer alerts are requested under the app's bundle identifier, in one namespace and
  /// one notification thread.
  @Test func alertIdentifiersAreSalahs() {
    #expect(PrayerAlertCoordinator.identifierPrefix == "io.github.salah-kit.Salah.")
    #expect(PrayerAlertCoordinator.namespace == "prayers")
    #expect(PrayerAlertCoordinator.threadIdentifier == "salah-prayers")
    #expect(
      PrayerAlertCoordinator.isPrayerAlert(
        "io.github.salah-kit.Salah.prayers/2026-06-02/dhuhr/before"))
    #expect(!PrayerAlertCoordinator.isPrayerAlert("salah.prayer.dhuhr.preReminder.1780391340"))
  }
}
