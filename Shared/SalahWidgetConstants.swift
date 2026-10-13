import Foundation

/// Shared constants used by both the Salah app target and the WidgetKit extension.
///
/// These three strings are the only "contract" the two targets need to agree on:
/// the App Group they share, the kind the timeline reloads target, and the
/// Darwin notification name the Stop button uses to reach the running app.
///
/// `nonisolated` so these constants stay reachable from the widget's
/// `nonisolated` `AppIntent.perform()`; the app target's
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise make them
/// MainActor-isolated and unreachable from that context.
nonisolated enum SalahWidgetConstants {
  /// Enable this App Group on BOTH targets (Signing & Capabilities ▸ App Groups):
  /// - Salah
  /// - SalahWidgetsExtension
  static let appGroupID = "group.io.github.salah-kit.Salah"

  static let prayerTimesWidgetKind = "io.github.salah-kit.Salah.widgets.prayerTimes"
  static let snapshotDefaultsKey = "SalahWidgetSnapshot.v1"
  static let stopAudioCommandDefaultsKey = "SalahWidgetStopAudioCommand.v1"
  static let stopAudioDarwinNotification = "io.github.salah-kit.Salah.widget.stopAudio"

  /// Tap target for the widget. A menu-bar (`LSUIElement`) app can't open its
  /// `MenuBarExtra` popover via URL, so the widget routes taps to the Settings
  /// window - the app's only window, and where the config it reflects lives.
  static let deepLinkScheme = "salah"
  static let settingsDeepLinkURL = URL(string: "salah://settings")!
}
