import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import Testing

/// Salah's calculation on SalahCalculation: what its settings mean in SalahTimes'
/// parameters, the times they give at the fixture, the delayed Ramadan Isha and the
/// Jumu'ah Salah declares. The comparison with the old adhan-swift times over many
/// places and methods ran outside these tests (the 1.0.0 release notes summarize it);
/// SalahKit's `docs/calculation-parity.md` explains every difference.
@Suite("Calculation")
struct CalculationTests {
  init() { TestEnvironment.configure() }

  func clock(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = Fixture.timeZone
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  /// The fixture's times, as the baselines show them; adhan-swift 1.4.0 gave the same.
  @Test func theFixtureDayKeepsItsTimes() {
    #expect(
      Fixture.day().events.map { clock($0.time) }
        == ["04:11", "05:38", "12:19", "15:35", "19:00", "20:30"])
    #expect(
      Fixture.day(dayOffset: 1).events.map { clock($0.time) }
        == ["04:11", "05:38", "12:19", "15:36", "19:00", "20:30"])
    #expect(clock(Fixture.time(.isha, ishaAdjustment: -78)) == "19:12")
  }

  /// The default preferences mean the fixture's settings: the parameters the app
  /// mirrors to the widget are the ones the tests calculate with.
  @Test func theDefaultPreferencesAreTheFixture() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    #expect(preferences.calculationChoices == Fixture.choices())
    #expect(preferences.mirroredSettings.calculation == Fixture.choices().calculationSettings)
    #expect(preferences.prayerLocation == Fixture.location)
  }

  /// Every method Salah offers maps to SalahTimes' published method, unchanged apart from
  /// the user's choices; the custom method is the user's two angles.
  @Test func everyMethodMapsToItsPublishedParameters() {
    let expected: [MethodPreference: CalculationMethod] = [
      .egyptian: .egyptian, .karachi: .karachi, .northAmerica: .isna,
      .muslimWorldLeague: .muslimWorldLeague, .ummAlQura: .ummAlQura, .gulf: .dubai,
      .moonsightingCommittee: .moonsightingCommittee, .kuwait: .kuwait, .qatar: .qatar,
      .singapore: .muis, .tehran: .tehran,
    ]
    for preference in MethodPreference.allCases {
      var choices = Fixture.choices()
      choices.method = preference
      choices.madhab = .hanafi
      choices.highLatitudeRule = .twilightAngle
      choices.delayedIshaInRamadan = false
      choices.adjustments = PrayerAdjustments(
        fajr: 1, sunrise: -2, dhuhr: 3, asr: -4, maghrib: 5, isha: -6)
      let parameters = choices.calculationSettings.parameters
      var published =
        expected[preference]?.parameters
        ?? CalculationParameters(fajr: .angle(18), isha: .angle(17.5))
      published.madhab = .hanafi
      published.highLatitudeRule = .twilightAngle
      published.adjustments = choices.adjustments
      #expect(parameters == published, "\(preference)")
    }
  }

  /// The delayed Isha: an interval Isha is 120 minutes after Maghrib in Ramadan (read
  /// after the Hijri offset), 90 otherwise; with the toggle off it stays 90, and an
  /// angle-based Isha never moves.
  @Test func theDelayedIshaFollowsRamadanAndTheHijriOffset() throws {
    func ishaMinutes(
      _ day: CivilDay, delayed: Bool, offset: Int = 0, method: MethodPreference = .ummAlQura
    )
      throws -> Double
    {
      var choices = Fixture.choices()
      choices.method = method
      choices.delayedIshaInRamadan = delayed
      choices.hijriOffset = offset
      let schedule = PrayerSchedule(
        source: SalahPrayerSource(choices.calculationSettings), location: Fixture.location)
      let events = try #require(schedule.day(day).day)
      return try #require(events[.isha]).time.timeIntervalSince(try #require(events[.maghrib]).time)
        / 60
    }
    // 1 Ramadan 1447 in Umm al-Qura is 18 February 2026.
    let firstOfRamadan = CivilDay(year: 2026, month: 2, day: 18)
    #expect(try ishaMinutes(firstOfRamadan, delayed: true) == 120)
    #expect(try ishaMinutes(firstOfRamadan.adding(days: -1), delayed: true) == 90)
    #expect(try ishaMinutes(firstOfRamadan, delayed: false) == 90)
    // An offset of 1 starts Ramadan a day earlier, as the Hijri date the app shows.
    #expect(try ishaMinutes(firstOfRamadan.adding(days: -1), delayed: true, offset: 1) == 120)
    #expect(try ishaMinutes(firstOfRamadan, delayed: true, method: .muslimWorldLeague) != 120)
  }

  /// Salah's source declares Friday's Dhuhr as Jumu'ah, on Fridays only, and changes
  /// nothing else of the calculation.
  @Test func fridaysDhuhrIsJumuahAndNothingElseChanges() {
    let settings = Fixture.choices().calculationSettings
    let salah = SalahPrayerSource(settings)
    let plain = CalculationSource(settings)
    #expect(salah.expectedKinds == plain.expectedKinds)
    #expect(salah.maximumLead == plain.maximumLead)
    for offset in 0..<7 {
      let day = Fixture.civilDay(offset: offset)
      let ours = salah.prayerDay(day, at: Fixture.location)
      let theirs = plain.prayerDay(day, at: Fixture.location)
      #expect(ours.coverage == theirs.coverage)
      #expect(ours.day?.events.map(\.time) == theirs.day?.events.map(\.time))
      let observances = ours.day?.events.filter { $0.observance == .jumuah }.map(\.kind)
      #expect(observances == (day.weekday == 6 ? [.dhuhr] : []), "\(day)")
    }
  }

  /// Ordinary places always calculate a complete day, the equator included, and the
  /// same inputs give the same times.
  @Test func ordinaryPlacesGiveCompleteDays() throws {
    let equator = PrayerLocation(latitude: 0, longitude: 0, timeZone: .gmt)
    var choices = Fixture.choices()
    choices.method = .muslimWorldLeague
    let schedule = PrayerSchedule(
      source: SalahPrayerSource(choices.calculationSettings), location: equator)
    let solstice = CivilDay(year: 2026, month: 6, day: 21)
    #expect(schedule.day(solstice).coverage == .complete)
    #expect(schedule.day(solstice) == schedule.day(solstice))
    #expect(Fixture.schedule().day(Fixture.civilDay()).coverage == .complete)
  }
}
