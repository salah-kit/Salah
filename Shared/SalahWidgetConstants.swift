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
  /// The App Group an app shares with its extensions.
  ///
  /// The build writes `APP_GROUP_IDENTIFIER` (Config/Shared.xcconfig, or your own in
  /// Config/Local.xcconfig) into each target's entitlements and into the
  /// `AppGroupIdentifier` key of its Info.plist, where this reads it, so the code and the
  /// entitlements always name the same group. A process without the key, such as the unit
  /// tests' runner, gets Salah's own.
  static let appGroupID =
    Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String
    ?? "group.com.omarkhaled.salah"

  static let prayerTimesWidgetKind = "com.omarkhaled.salah.widgets.prayerTimes"
  /// The settings mirror (`SalahSettings`). The version is in the key: a change to the
  /// value's shape takes a new key.
  static let settingsKey = "SalahSettings.v2"
  /// The settings mirror's previous key, which the app removes from the App Group.
  static let retiredSettingsKey = "SalahSettings.v1"
  /// What's playing (`SalahPlayback`), or nothing.
  static let playbackKey = "SalahPlayback.v1"
  /// The widget's Stop button posts this signal; the running app stops playback.
  static let stopAudioSignal = "com.omarkhaled.salah.widget.stopAudio"

  /// Tap target for the widget. A menu-bar (`LSUIElement`) app can't open its
  /// `MenuBarExtra` popover via URL, so the widget routes taps to the Settings
  /// window - the app's only window, and where the config it reflects lives.
  static let deepLinkScheme = "salah"
  static let settingsDeepLinkURL = URL(string: "salah://settings")!
}
