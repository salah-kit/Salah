import Foundation
import SalahCalculation
import SalahCore
import Testing

/// Where preferences live and what a fresh install starts with. Salah's keys are its own
/// namespace, and nothing reads or migrates Guidance's `kBA*` keys.
@Suite("Preference storage")
struct PreferenceStorageTests {
  init() { TestEnvironment.configure() }

  /// The alert settings an empty store starts with: every prayer's default, except that
  /// each before-reminder sounds the prayer's own alert sound, and Sunrise's alert, off,
  /// is set to the Fajr adhan. These came from the v2 key migration's defaults until
  /// Salah removed it; this pins that removing it changed nothing.
  @Test func freshInstallNotificationSettings() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    let fajr = PrayerNotificationConfig(
      alertEnabled: true, alertSound: .fajr,
      preReminderEnabled: false, preReminderOffset: 30, preReminderSound: .fajr,
      postReminderEnabled: false, postReminderOffset: 5, postReminderSound: .system)
    var sunrise = fajr
    sunrise.alertEnabled = false
    let adhan = PrayerNotificationConfig.alert(sound: .alafasy, beforeSound: .alafasy)
    #expect(
      preferences.notificationSettings == [
        "fajr": fajr, "sunrise": sunrise,
        "dhuhr": adhan, "asr": adhan, "maghrib": adhan, "isha": adhan,
      ])
    #expect(!preferences.jumuahOverrideEnabled)
  }

  /// Calculation input SalahTimes can't calculate with never reaches it: a custom angle
  /// outside 1...30 degrees snaps back to the previous one, and an adjustment beyond a
  /// day either way stops at a day, so the schedule keeps its days.
  ///
  /// Regression: the settings accepted any positive angle and any adjustment, and
  /// SalahTimes rejected them, leaving every day unavailable and no alerts.
  @Test func calculationInputStaysWhereSalahTimesCalculates() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.customFajrAngle = 35
    #expect(preferences.customFajrAngle == 18)
    preferences.customFajrAngle = 15.5
    preferences.customFajrAngle = 0.5
    #expect(preferences.customFajrAngle == 15.5)
    preferences.customIshaAngle = 185
    #expect(preferences.customIshaAngle == 17.5)
    preferences.customIshaAngle = 30
    #expect(preferences.customIshaAngle == 30)
    preferences.methodPreference = .custom
    let schedule = PrayerSchedule(
      source: SalahPrayerSource(preferences.calculationChoices.calculationSettings),
      location: Fixture.location)
    #expect(schedule.day(Fixture.civilDay()).coverage == .complete)

    preferences.fajrAdjustment = 5_000
    #expect(preferences.fajrAdjustment == 1_440)
    preferences.ishaAdjustment = -2_000
    #expect(preferences.ishaAdjustment == -1_440)
    #expect(scratch.defaults.integer(forKey: Preferences.Key.adjustmentIsha) == -1_440)

    // Stored values out of range load as the defaults or the bounds.
    let stored = ScratchDefaults()
    stored.defaults.set(40.0, forKey: Preferences.Key.customFajrAngle)
    stored.defaults.set(9_999, forKey: Preferences.Key.adjustmentDhuhr)
    let loaded = Preferences(defaults: stored.defaults)
    #expect(loaded.customFajrAngle == 18)
    #expect(loaded.dhuhrAdjustment == 1_440)
  }

  /// Every key the preferences write is in Salah's namespace, apart from the system's
  /// `AppleLanguages` and `AppleTextDirection`, which the language setting overrides on
  /// purpose.
  @Test func everyKeyIsInTheSalahNamespace() throws {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    for setting in PreferenceEffectsTests.Setting.allCases {
      PreferenceEffectsTests.expectation(for: setting).change(preferences)
    }
    let keys = try #require(scratch.defaults.persistentDomain(forName: scratch.suiteName)).keys
    let system: Set = ["AppleLanguages", "AppleTextDirection"]
    let foreign = keys.filter { !$0.hasPrefix("salah.") && !system.contains($0) }
    #expect(foreign.isEmpty, "\(foreign.sorted())")
    #expect(keys.contains("salah.notificationSettings"))
  }

  /// Values under Guidance's `kBA*` keys reach nothing: an install that has them starts
  /// exactly like an empty one.
  @Test func guidanceKeysAreIgnored() {
    let legacy = ScratchDefaults()
    let values: [String: Any] = [
      "kBAUserDefaultsVersion": "2.0.1",
      "kBAUserDefaultsMethod": MethodPreference.gulf.rawValue,
      "kBAUserDefaultsAutoDetectMethod": false,
      "kBAUserDefaultsLocationCity": "Reykjavík",
      "kBAUserDefaultsSilentMode": true,
      "kBAUserDefaultsAlertFajrEnabled": false,
      "kBAUserDefaultsAlertDhuhrSound": 0,
      "kBAUserDefaultsAppLanguage": AppLanguage.arabic.rawValue,
    ]
    for (key, value) in values {
      legacy.defaults.set(value, forKey: key)
    }
    let empty = ScratchDefaults()
    let migrated = Preferences(defaults: legacy.defaults)
    let fresh = Preferences(defaults: empty.defaults)
    #expect(migrated.methodPreference == fresh.methodPreference)
    #expect(migrated.autoDetectMethod == fresh.autoDetectMethod)
    #expect(migrated.city == fresh.city)
    #expect(migrated.silentMode == fresh.silentMode)
    #expect(migrated.notificationSettings == fresh.notificationSettings)
    #expect(migrated.appLanguage == fresh.appLanguage)
  }

  /// Alert sounds round-trip through the stored settings' JSON, and only in its
  /// current shape: the bare strings an older format wrote don't decode.
  @Test func alertSoundsRoundTrip() throws {
    let custom = CustomAdhanFile(fileName: "Adhan.m4a", bookmarkData: Data([1, 2, 3]))
    for sound in AdhanSound.adhanSounds + [.system, .none, .custom(custom)] {
      let data = try JSONEncoder().encode(sound)
      #expect(try JSONDecoder().decode(AdhanSound.self, from: data) == sound)
    }
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(AdhanSound.self, from: Data(#""Adhan-Alafasy""#.utf8))
    }
  }
}
