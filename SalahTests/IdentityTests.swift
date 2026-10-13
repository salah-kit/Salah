import Foundation
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
    #expect(
      SalahWidgetConstants.stopAudioDarwinNotification
        == "io.github.salah-kit.Salah.widget.stopAudio")
    #expect(SalahWidgetConstants.snapshotDefaultsKey == "SalahWidgetSnapshot.v1")
    #expect(SalahWidgetConstants.stopAudioCommandDefaultsKey == "SalahWidgetStopAudioCommand.v1")
    #expect(SalahWidgetConstants.deepLinkScheme == "salah")
    #expect(SalahWidgetConstants.settingsDeepLinkURL.scheme == SalahWidgetConstants.deepLinkScheme)
  }
}
