import Foundation

/// Shared constants used by both the Salah app target and the WidgetKit extension.
///
/// These strings are the only "contract" the two targets need to agree on: the App
/// Group they share, the keys of the values the app mirrors there, the kind the
/// timeline reloads target, and the signal the Stop button uses to reach the running
/// app.
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
  /// The settings mirror (`SalahSettings`). The version is in the key: a change to the
  /// value's shape takes a new key.
  static let settingsKey = "SalahSettings.v2"
  /// What's playing (`SalahPlayback`), or nothing.
  static let playbackKey = "SalahPlayback.v1"
  /// The widget's Stop button posts this signal; the running app stops playback.
  static let stopAudioSignal = "io.github.salah-kit.Salah.widget.stopAudio"

  /// Tap target for the widget. A menu-bar (`LSUIElement`) app can't open its
  /// `MenuBarExtra` popover via URL, so the widget routes taps to the Settings
  /// window - the app's only window, and where the config it reflects lives.
  static let deepLinkScheme = "salah"
  static let settingsDeepLinkURL = URL(string: "salah://settings")!
}
