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
    #expect(preferences.calculation.parameters.ramadanIsha == .off)
    preferences.method = .preset(.ummAlQura)
    #expect(
      preferences.calculation.parameters.ramadanIsha == .interval(minutes: 120, hijriDayOffset: 2))
    preferences.delayedIshaInRamadan = false
    #expect(preferences.calculation.parameters.ramadanIsha == .off)
  }

  /// Only Umm al-Qura's timetables delay Isha in Ramadan. Qatar's interval Isha keeps its 90
  /// minutes, so a place in Qatar on the automatic method never gets the 120.
  @Test func onlyUmmAlQuraDelaysIshaInRamadan() throws {
    var preferences = IOSPreferences()
    let doha = try #require(TimeZone(identifier: "Asia/Qatar"))
    preferences.location = PrayerLocation(
      latitude: 25.2854, longitude: 51.531, timeZone: doha, countryCode: "QA", name: "Doha")
    #expect(preferences.resolvedMethod == .qatar)
    #expect(preferences.calculation.parameters.ramadanIsha == .off)
    preferences.method = .preset(.ummAlQura)
    #expect(
      preferences.calculation.parameters.ramadanIsha == .interval(minutes: 120, hijriDayOffset: 0))
  }

  /// The geocoder names a place in the device's language. In another language Salah keeps
  /// the name it looked up, and the widgets, the activity and notifications read it.
  @Test func aPlaceIsNamedInTheSelectedLanguageOnceLookedUp() throws {
    var preferences = IOSPreferences()
    let cairo = try #require(TimeZone(identifier: "Africa/Cairo"))
    let place = PrayerLocation(
      latitude: 30.0444, longitude: 31.2357, timeZone: cairo, countryCode: "EG",
      name: "Sheikh Zayed")
    preferences.location = place
    preferences.language = .arabic
    #expect(preferences.placeLanguageCode == "ar")
    #expect(preferences.placeName == "Sheikh Zayed")
    #expect(preferences.needsPlaceName)

    preferences.setPlaceName(" الشيخ زايد ", languageCode: "ar", for: place)
    #expect(preferences.placeName == "الشيخ زايد")
    #expect(!preferences.needsPlaceName)
    #expect(preferences.mirror?.location.name == "الشيخ زايد")
    #expect(IOSPrayerNotificationContent(preferences: preferences).locationName == "الشيخ زايد")
    // The saved location keeps what the geocoder gave it.
    #expect(preferences.location?.name == "Sheikh Zayed")

    // Each language has its own name; one that wasn't looked up reads as saved.
    preferences.language = .french
    #expect(preferences.placeName == "Sheikh Zayed")
    #expect(preferences.needsPlaceName)
    preferences.setPlaceName("Cheikh Zayed", languageCode: "fr", for: place)
    #expect(preferences.mirror?.location.name == "Cheikh Zayed")
    preferences.language = .arabic
    #expect(preferences.mirror?.location.name == "الشيخ زايد")
    preferences.language = .english
    #expect(preferences.mirror?.location.name == "Sheikh Zayed")
    #expect(preferences.needsPlaceName)

    // The names survive a round trip, and an older save without them still decodes.
    let decoded = try JSONDecoder().decode(
      IOSPreferences.self, from: JSONEncoder().encode(preferences))
    #expect(decoded.placeNames == preferences.placeNames)
    #expect(try JSONDecoder().decode(IOSPreferences.self, from: Data("{}".utf8)).placeNames == nil)
  }

  /// A fix never lands on the same coordinates twice. The next fix of the same place keeps
  /// the names already looked up, so opening Salah asks for none again; another place starts
  /// over. The geocoder's own answer is the name in the device's language.
  @Test func aNewFixOfTheSamePlaceKeepsItsNames() throws {
    let cairo = try #require(TimeZone(identifier: "Africa/Cairo"))
    func fix(_ latitude: Double, _ longitude: Double, name: String) -> PrayerLocation {
      PrayerLocation(
        latitude: latitude, longitude: longitude, timeZone: cairo, countryCode: "EG", name: name)
    }
    var saved = IOSPreferences()
    saved.language = .arabic
    var first = saved
    first.location = fix(30.0444, 31.2357, name: "Sheikh Zayed")
    first.settlePlaceNames(after: saved, deviceLanguageCode: "en")
    #expect(first.placeNames?.names == ["en": "Sheikh Zayed"])
    #expect(first.needsPlaceName)
    first.setPlaceName("الشيخ زايد", languageCode: "ar", for: try #require(first.location))
    #expect(!first.needsPlaceName)

    var second = first
    second.location = fix(30.0449, 31.2351, name: "Sheikh Zayed")
    second.settlePlaceNames(after: first, deviceLanguageCode: "en")
    second = second.normalized()
    #expect(second.placeName == "الشيخ زايد")
    #expect(!second.needsPlaceName)
    #expect(second.placeNames?.latitude == 30.0449)

    // The same edit again, or one that leaves the place alone, changes nothing.
    var untouched = second
    untouched.muteSounds.toggle()
    untouched.settlePlaceNames(after: second, deviceLanguageCode: "fr")
    #expect(untouched.placeNames == second.placeNames)

    var moved = second
    moved.location = fix(30.0131, 31.2089, name: "Giza")
    moved.settlePlaceNames(after: second, deviceLanguageCode: "en")
    #expect(moved.placeNames?.names == ["en": "Giza"])
    #expect(moved.placeName == "Giza")
    #expect(moved.needsPlaceName)

    // A device that now answers in Arabic names the next place in Arabic at once.
    var arabicDevice = moved
    arabicDevice.location = fix(30.0444, 31.2357, name: "الشيخ زايد")
    arabicDevice.settlePlaceNames(after: moved, deviceLanguageCode: "ar")
    #expect(!arabicDevice.needsPlaceName)

    // Preferences that arrive with their place's names, as the iPhone's do on the watch,
    // keep them.
    var sent = IOSPreferences()
    sent.language = .arabic
    sent.location = fix(30.0444, 31.2357, name: "Sheikh Zayed")
    sent.placeNames = IOSPlaceNames(
      latitude: 30.0444, longitude: 31.2357, names: ["en": "Sheikh Zayed", "ar": "الشيخ زايد"])
    var received = sent
    received.settlePlaceNames(after: IOSPreferences(), deviceLanguageCode: "fr")
    #expect(received == sent)
    #expect(received.mirror?.location.name == "الشيخ زايد")

    // A place saved before names were kept files its name under the device's language once.
    var older = IOSPreferences()
    older.language = .english
    older.location = fix(30.0444, 31.2357, name: "Sheikh Zayed")
    #expect(older.needsPlaceName)
    older.seedPlaceNames(deviceLanguageCode: "en")
    #expect(!older.needsPlaceName)
    let seeded = older
    older.seedPlaceNames(deviceLanguageCode: "ar")
    #expect(older == seeded)
  }

  /// A name belongs to the place it was looked up for. A late answer for a place the person
  /// has left is dropped, and a new place never shows the old one's name.
  @Test func placeNamesNeverLabelAnotherPlace() throws {
    var preferences = IOSPreferences()
    let cairo = try #require(TimeZone(identifier: "Africa/Cairo"))
    let riyadh = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let zayed = PrayerLocation(
      latitude: 30.0444, longitude: 31.2357, timeZone: cairo, countryCode: "EG",
      name: "Sheikh Zayed")
    let makkah = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: riyadh, countryCode: "SA", name: "Makkah")
    preferences.language = .arabic
    preferences.location = zayed
    preferences.setPlaceName("الشيخ زايد", languageCode: "ar", for: zayed)

    preferences.location = makkah
    #expect(preferences.placeName == "Makkah")
    #expect(preferences.needsPlaceName)
    #expect(preferences.normalized().placeNames == nil)
    // The lookup for the old place answers late.
    preferences.setPlaceName("الشيخ زايد", languageCode: "ar", for: zayed)
    #expect(preferences.placeName == "Makkah")
    preferences.setPlaceName("مكة المكرمة", languageCode: "ar", for: makkah)
    #expect(preferences.placeName == "مكة المكرمة")
    #expect(preferences.placeNames?.names == ["ar": "مكة المكرمة"])
    // An empty answer changes nothing, and without a place there's nothing to name.
    preferences.setPlaceName("  ", languageCode: "ar", for: makkah)
    #expect(preferences.placeName == "مكة المكرمة")
    preferences.location = nil
    #expect(preferences.placeName == nil)
    #expect(!preferences.needsPlaceName)
    #expect(preferences.normalized().placeNames == nil)

    // Another process's edit keeps the names this one looked up, and the reverse.
    var stored = IOSPreferences()
    stored.location = makkah
    var before = stored
    before.language = .arabic
    var after = before
    after.setPlaceName("مكة المكرمة", languageCode: "ar", for: makkah)
    stored.muteSounds = true
    stored.mergeChanges(from: before, to: after)
    #expect(stored.muteSounds)
    #expect(stored.placeNames?.names == ["ar": "مكة المكرمة"])
  }

  /// A new language changes the words on every widget and control, so all of them reload at
  /// once; any other setting reloads the surfaces that show it; nothing reloads unchanged.
  @Test @MainActor func aLanguageChangeReloadsEveryWidgetAndControl() throws {
    var preferences = IOSPreferences()
    preferences.language = .english
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262,
      timeZone: try #require(TimeZone(identifier: "Asia/Riyadh")), countryCode: "SA",
      name: "Makkah")
    var saved: SalahSettings?
    var events: [String] = []
    let publisher = IOSWidgetPublisher(
      system: IOSWidgetPublisher.System(
        load: { saved },
        save: { settings, kinds in
          guard settings != saved else { return false }
          saved = settings
          events.append("save reloading \(kinds)")
          return true
        },
        reloadAllTimelines: { events.append("all timelines") },
        reloadControls: { events.append("control \($0)") },
        reloadAllControls: { events.append("all controls") }))
    let kind = SalahWidgetConstants.prayerTimesWidgetKind

    #expect(try publisher.publish(try #require(preferences.mirror)))
    #expect(events == ["save reloading [\"\(kind)\"]", "control \(IOSControlKind.muteSounds)"])
    events = []
    #expect(try !publisher.publish(try #require(preferences.mirror)))
    #expect(events.isEmpty)

    preferences.language = .arabic
    #expect(try publisher.publish(try #require(preferences.mirror)))
    #expect(events == ["save reloading []", "all timelines", "all controls"])
    #expect(saved?.language == .arabic)

    events = []
    preferences.muteSounds = true
    #expect(try publisher.publish(try #require(preferences.mirror)))
    #expect(events == ["save reloading [\"\(kind)\"]", "control \(IOSControlKind.muteSounds)"])
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
