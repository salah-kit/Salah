import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

@Suite("iOS calculation and persistence contracts")
struct CorePreferencesTests {
  @Test func eachPublishedMethodKeepsItsCompleteParameters() {
    for method in CalculationMethod.allCases {
      var preferences = IOSPreferences()
      preferences.method = .preset(method)
      preferences.madhab = .hanafi
      preferences.automaticHighLatitude = false
      preferences.highLatitudeRule = .twilightAngle
      preferences.delayedIshaInRamadan = false
      preferences.adjustments = PrayerAdjustments(fajr: 2, isha: -3)
      var expected = method.parameters
      expected.madhab = .hanafi
      expected.highLatitudeRule = .twilightAngle
      expected.adjustments = preferences.adjustments
      #expect(preferences.calculation.parameters == expected)
    }
  }

  @Test func customAnglesRamadanAndHijriOffsetAreOneCalculationContract() {
    var preferences = IOSPreferences()
    preferences.method = .custom
    preferences.customFajrAngle = 17
    preferences.customIshaAngle = 16
    preferences.hijriOffset = 2
    #expect(preferences.calculation.parameters.fajr == .angle(17))
    #expect(preferences.calculation.parameters.isha == .angle(16))
    #expect(
      preferences.calculation.parameters.ramadanIsha == .interval(minutes: 120, hijriDayOffset: 2))
    preferences.delayedIshaInRamadan = false
    #expect(preferences.calculation.parameters.ramadanIsha == .off)
  }

  @Test func normalizationCoversCorruptControlValuesAndEveryEvent() {
    var preferences = IOSPreferences()
    preferences.hijriOffset = 200
    preferences.customFajrAngle = .nan
    preferences.customIshaAngle = 999
    preferences.playbackVolume = .infinity
    preferences.adjustments.isha = .max
    preferences.notifications = [
      .fajr: IOSPrayerAlertSettings(beforeMinutes: -10, afterMinutes: 500)
    ]
    let normalized = preferences.normalized()
    #expect(normalized.hijriOffset == 3)
    #expect(normalized.customFajrAngle == 18)
    #expect(normalized.customIshaAngle == 30)
    #expect(normalized.playbackVolume == 0.75)
    #expect(normalized.adjustments.isha == 60)
    #expect(normalized.notifications.count == PrayerKind.allCases.count)
    #expect(normalized.notifications[.fajr]?.beforeMinutes == 1)
    #expect(normalized.notifications[.fajr]?.afterMinutes == 120)
    #expect(normalized.notifications[.sunrise]?.atTime == false)
  }

  @Test func absentNewPreferenceFieldsDecodeToTheirDocumentedDefaults() throws {
    let data = Data("{\"muteSounds\":true}".utf8)
    let preferences = try JSONDecoder().decode(IOSPreferences.self, from: data)
    #expect(preferences.muteSounds)
    #expect(preferences.location == nil)
    #expect(preferences.recentLocations.isEmpty)
    #expect(preferences.method == .automatic)
    #expect(preferences.notifications.count == 6)
  }

  @Test @MainActor func versionedDefaultsRoundTripAndRefuseFutureData() throws {
    let suite = "io.github.salah-kit.Salah.coretest.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = IOSUserDefaultsPreferencesRepository(defaults: defaults)
    var expected = IOSPreferences()
    expected.language = .arabic
    expected.notifications[.isha]?.afterEnabled = true
    expected.notifications[.isha]?.afterSound = .custom("my-sound.caf")
    try repository.save(expected)
    #expect(try repository.load() == expected)
    let future = Data("{\"schemaVersion\":2,\"preferences\":{}}".utf8)
    defaults.set(future, forKey: IOSUserDefaultsPreferencesRepository.key)
    #expect(throws: IOSPreferencesStorageError.unsupportedVersion(2)) {
      try repository.save(IOSPreferences())
    }
    #expect(defaults.data(forKey: IOSUserDefaultsPreferencesRepository.key) == future)
  }

  @Test func sharedFileUpdatesAreSerializedAcrossIndependentWriters() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IOSSharedPreferencesStore(directory: directory)
    var initial = IOSPreferences()
    initial.playbackVolume = 0
    try store.save(initial)
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<40 {
        group.addTask {
          let independentWriter = IOSSharedPreferencesStore(directory: directory)
          try independentWriter.update { $0.playbackVolume += 0.01 }
        }
      }
      try await group.waitForAll()
    }
    let result = try #require(try store.load())
    #expect(abs(result.playbackVolume - 0.4) < 0.000_001)
  }

  @Test func anExplicitEditRecoversCorruptPreferencesAndRetainsTheOriginalBytes() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IOSSharedPreferencesStore(directory: directory)
    try store.save(IOSPreferences())
    let folder = directory.appendingPathComponent("Library/Application Support/Salah")
    let broken = Data("{broken".utf8)
    try broken.write(to: folder.appendingPathComponent("preferences-v1.json"))
    #expect(throws: (any Error).self) { try store.load() }
    try store.update { $0.muteSounds = true }
    #expect(try store.load()?.muteSounds == true)
    let files = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)
    let retained = try #require(
      files.first { $0.lastPathComponent.hasPrefix("preferences-unreadable-") })
    #expect(try Data(contentsOf: retained) == broken)
  }

  @Test func freshAlertSoundsDistinguishFajrAndKeepSunriseOptional() {
    let preferences = IOSPreferences()
    #expect(preferences.alerts(for: .fajr).sound == .fajrAdhan)
    #expect(preferences.alerts(for: .dhuhr).sound == .adhan)
    #expect(preferences.alerts(for: .sunrise).sound == .softTone)
    #expect(!preferences.alerts(for: .sunrise).atTime)
    #expect(preferences.alerts(for: .fajr).beforeSound == .softTone)
    #expect(preferences.alerts(for: .isha).afterSound == .softTone)
  }

  @Test func anOlderManualMethodBecomesTheAutomaticFallbackWithoutInventingARegion() throws {
    var original = IOSPreferences()
    original.method = .preset(.karachi)
    let data = try JSONEncoder().encode(original)
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "automaticFallbackMethod")
    let older = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(IOSPreferences.self, from: older)
    #expect(decoded.automaticFallbackMethod == .karachi)
  }
}
