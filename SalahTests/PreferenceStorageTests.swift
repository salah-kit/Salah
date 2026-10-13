import Foundation
import Testing

/// Where preferences live and what a fresh install starts with. Salah has no installed
/// base (Amendment 4): its keys are its own namespace, and nothing reads or migrates the
/// `kBA*` keys of the app it was rebuilt from.
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

  /// Every key the preferences write is in Salah's namespace, apart from the system's
  /// `AppleLanguages`, which the language setting overrides on purpose.
  @Test func everyKeyIsInTheSalahNamespace() throws {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    for setting in PreferenceEffectsTests.Setting.allCases {
      PreferenceEffectsTests.expectation(for: setting).change(preferences)
    }
    let keys = try #require(scratch.defaults.persistentDomain(forName: scratch.suiteName)).keys
    let foreign = keys.filter { !$0.hasPrefix("salah.") && $0 != "AppleLanguages" }
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
