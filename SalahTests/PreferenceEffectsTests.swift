import Foundation
import SalahCore
import Testing

/// Characterizes the refresh effects a preference change posts on
/// `.salahPreferencesDidChange` (`Preferences.swift`), the signal the widget's settings
/// mirror (`WidgetMirror`) publishes on: `display`, `prayerTimes` and `localization`,
/// plus `audioRuntime`. `PrayerManager.applyPreferenceRefresh` is the one consumer.
@Suite("Preference effects")
struct PreferenceEffectsTests {
  init() { TestEnvironment.configure() }

  final class Recorder {
    var effects: [PreferenceRefresh] = []
  }

  /// The effects posted, in order, while `change` runs. Delivery is synchronous on
  /// the posting (main) thread, and the test is synchronous, so nothing else posts
  /// in between.
  static func effects(of change: (Preferences) -> Void, on preferences: Preferences)
    -> [PreferenceRefresh]
  {
    let recorder = Recorder()
    let token = NotificationCenter.default.addObserver(
      forName: .salahPreferencesDidChange, object: nil, queue: nil
    ) { note in
      let raw = note.userInfo?[PreferenceRefresh.userInfoKey] as? Int ?? -1
      MainActor.assumeIsolated { recorder.effects.append(PreferenceRefresh(rawValue: raw)) }
    }
    change(preferences)
    NotificationCenter.default.removeObserver(token)
    return recorder.effects
  }

  /// Every state-affecting preference. Plain data, because Swift Testing builds
  /// arguments outside the main actor; `expectation(for:)` maps each to its change.
  nonisolated enum Setting: String, Sendable, CaseIterable {
    case displayNextPrayer, nextPrayerDisplayType, nextPrayerDisplayName, displayIcon
    case useCurrentLocation, city, state, country, countryName, hijriOffset
    case widgetThemeID, widgetCustomAccent, widgetCustomPrimary, widgetCustomBase, widgetAppearance
    case storedTimeZone, latitude, longitude, methodPreference, madhabPreference
    case autoDetectMethod, autoDetectHighLatitudeRule, highLatitudeRulePreference
    case customFajrAngle, customIshaAngle
    case fajrAdjustment, shuruqAdjustment, dhuhrAdjustment, asrAdjustment, maghribAdjustment,
      ishaAdjustment
    case delayedIshaInRamadan, notificationSettings, jumuahOverrideEnabled
    case silentMode, alertVolume, duaEnabled, appLanguage
  }

  /// The change each setting gets, and the effects it posts.
  static func expectation(for setting: Setting) -> (
    effects: [PreferenceRefresh], change: (Preferences) -> Void
  ) {
    switch setting {
    // Display: the menu bar's format, the location label, the Hijri offset, the theme.
    case .displayNextPrayer: ([.display], { $0.displayNextPrayer = false })
    case .nextPrayerDisplayType: ([.display], { $0.nextPrayerDisplayType = .timeOfPrayer })
    case .nextPrayerDisplayName: ([.display], { $0.nextPrayerDisplayName = .abbreviation })
    case .displayIcon: ([.display], { $0.displayIcon = false })
    case .useCurrentLocation: ([.display], { $0.useCurrentLocation = false })
    case .city: ([.display], { $0.city = "Madinah" })
    case .state: ([.display], { $0.state = "Madinah" })
    case .country: ([.display], { $0.country = "EG" })
    case .countryName: ([.display], { $0.countryName = "Egypt" })
    case .hijriOffset: ([.display], { $0.hijriOffset = 1 })
    case .widgetThemeID: ([.display], { $0.widgetThemeID = "dawn" })
    case .widgetCustomAccent: ([.display], { $0.widgetCustomAccent = SalahColorSpec(1, 0, 0) })
    case .widgetCustomPrimary: ([.display], { $0.widgetCustomPrimary = SalahColorSpec(0, 1, 0) })
    case .widgetCustomBase: ([.display], { $0.widgetCustomBase = .sand })
    case .widgetAppearance: ([.display], { $0.widgetAppearance = .alwaysDark })
    // Prayer times: anything that moves a time, plus the notification settings.
    case .storedTimeZone: ([.prayerTimes], { $0.storedTimeZone = "Africa/Cairo" })
    case .latitude: ([.prayerTimes], { $0.latitude = 30.0444 })
    case .longitude: ([.prayerTimes], { $0.longitude = 31.2357 })
    case .methodPreference: ([.prayerTimes], { $0.methodPreference = .egyptian })
    case .madhabPreference: ([.prayerTimes], { $0.madhabPreference = .hanafi })
    case .autoDetectMethod: ([.prayerTimes], { $0.autoDetectMethod = false })
    case .autoDetectHighLatitudeRule: ([.prayerTimes], { $0.autoDetectHighLatitudeRule = false })
    case .highLatitudeRulePreference:
      ([.prayerTimes], { $0.highLatitudeRulePreference = .twilightAngle })
    case .customFajrAngle: ([.prayerTimes], { $0.customFajrAngle = 19 })
    case .customIshaAngle: ([.prayerTimes], { $0.customIshaAngle = 18 })
    case .fajrAdjustment: ([.prayerTimes], { $0.fajrAdjustment = 2 })
    case .shuruqAdjustment: ([.prayerTimes], { $0.shuruqAdjustment = 2 })
    case .dhuhrAdjustment: ([.prayerTimes], { $0.dhuhrAdjustment = 2 })
    case .asrAdjustment: ([.prayerTimes], { $0.asrAdjustment = 2 })
    case .maghribAdjustment: ([.prayerTimes], { $0.maghribAdjustment = 2 })
    case .ishaAdjustment: ([.prayerTimes], { $0.ishaAdjustment = 2 })
    case .delayedIshaInRamadan: ([.prayerTimes], { $0.delayedIshaInRamadan = false })
    case .notificationSettings: ([.prayerTimes], { $0.setConfig(.alert(before: 15), for: .asr) })
    // Turning the override on seeds the Jumu'ah settings from Dhuhr's first: two posts.
    case .jumuahOverrideEnabled:
      ([.prayerTimes, .prayerTimes], { $0.jumuahOverrideEnabled = true })
    // Silent mode decides the scheduled sounds, so it reschedules as well.
    case .silentMode: ([[.prayerTimes, .audioRuntime]], { $0.silentMode = true })
    // Audio runtime: the live player only.
    case .alertVolume: ([.audioRuntime], { $0.alertVolume = 80 })
    case .duaEnabled: ([.audioRuntime], { $0.duaEnabled = false })
    // Localization: language only, no prayer-time or display flag of its own.
    case .appLanguage: ([.localization], { $0.appLanguage = .arabic })
    }
  }

  @Test(arguments: Setting.allCases)
  func eachPreferencePostsItsEffects(_ setting: Setting) {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    let expected = Self.expectation(for: setting)
    #expect(Self.effects(of: expected.change, on: preferences) == expected.effects)
  }

  /// Loading stored values posts nothing.
  @Test func loadingPostsNothing() {
    let scratch = ScratchDefaults()
    scratch.defaults.set(true, forKey: "salah.silentMode")
    var loaded: Preferences?
    let posted = Self.effects(
      of: { _ in loaded = Preferences(defaults: scratch.defaults) }, on: Preferences.shared)
    #expect(posted.isEmpty)
    #expect(loaded?.silentMode == true)
  }

  /// A location change is one coalesced post: the union of its fields' effects,
  /// with the auto-detected method and high-latitude rule folded in.
  @Test func locationChangeCoalescesIntoOnePost() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    let posted = Self.effects(
      of: {
        $0.updateLocation(
          latitude: 64.1466, longitude: -21.9426, city: "Reykjavík", state: "",
          country: "IS", countryName: "Iceland", timeZone: "Atlantic/Reykjavik")
      }, on: preferences)
    #expect(posted == [[.prayerTimes, .display]])
    #expect(preferences.methodPreference == .muslimWorldLeague)
    #expect(preferences.highLatitudeRulePreference == .seventhOfTheNight)
  }

  /// Changing the language writes the `AppleLanguages` override into the app's own
  /// domain, so system chrome (the Settings window title) follows on next launch;
  /// `.system` removes it again.
  @Test func languageWritesTheAppleLanguagesOverride() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    func stored() -> Any? {
      scratch.defaults.persistentDomain(forName: scratch.suiteName)?["AppleLanguages"]
    }
    preferences.appLanguage = .french
    #expect(stored() as? [String] == ["fr"])
    preferences.appLanguage = .system
    #expect(stored() == nil)
  }

  /// Out-of-range values are corrected in the setter, which posts once for the
  /// corrected value.
  @Test func correctedValuesPostOnce() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    #expect(Self.effects(of: { $0.alertVolume = 150 }, on: preferences) == [.audioRuntime])
    #expect(preferences.alertVolume == 100)
    // A non-positive custom angle snaps back to the previous value.
    #expect(Self.effects(of: { $0.customFajrAngle = 0 }, on: preferences) == [.prayerTimes])
    #expect(preferences.customFajrAngle == 18)
  }

  /// The menu bar always shows something: hiding both the icon and the prayer brings
  /// the icon back, which posts a second `display`.
  @Test func hidingEverythingInTheMenuBarRestoresTheIcon() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.displayNextPrayer = false
    #expect(Self.effects(of: { $0.displayIcon = false }, on: preferences) == [.display, .display])
    #expect(preferences.displayIcon)
  }

  /// The imperative helpers post through `Preferences.shared`.
  @Test func imperativeRefreshes() {
    #expect(Self.effects(of: { _ in notifyChange() }, on: Preferences.shared) == [.prayerTimes])
    #expect(
      Self.effects(of: { _ in notifyNotificationRuntimePreferenceChange() }, on: Preferences.shared)
        == [.audioRuntime])
  }

  /// The wire format the consumer reads.
  @Test func notificationCarriesTheRawEffects() {
    #expect(
      Notification.Name.salahPreferencesDidChange.rawValue == "salahPreferencesDidChange")
    #expect(PreferenceRefresh.userInfoKey == "effects")
    #expect(
      [PreferenceRefresh.display, .prayerTimes, .audioRuntime, .localization].map(\.rawValue) == [
        1, 2, 4, 8,
      ])
  }
}
