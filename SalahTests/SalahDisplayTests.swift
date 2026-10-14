import Foundation
import SalahCore
import SalahUI
import Testing

/// What Salah's surfaces show at a moment, now that SalahCore decides the state: the
/// focus, the tones, each row's state and the "since" text. The rules the app's own
/// one-day snapshot kept are pinned again here; the two it got wrong (no previous
/// prayer before Fajr, and an invented next prayer without tomorrow's times) now have
/// regressions.
///
/// The day is the fixture's, in Riyadh: Fajr 04:11, Sunrise 05:38, Dhuhr 12:19, Asr
/// 15:35, Maghrib 19:00, Isha 20:30, and tomorrow's Fajr 04:11.
@Suite("Display state")
struct SalahDisplayTests {
  init() { TestEnvironment.configure() }

  static func settings(_ configure: (Preferences) -> Void = { _ in }) -> SalahSettings {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.appLanguage = .english
    configure(preferences)
    return preferences.mirroredSettings
  }

  static func display(
    at date: Date, playback: SalahPlayback? = nil,
    _ configure: (Preferences) -> Void = { _ in }
  ) -> SalahDisplay {
    let settings = settings(configure)
    return SalahDisplay(
      date: date, settings: settings, schedule: settings.schedule, playback: playback)
  }

  func event(_ kind: PrayerKind, dayOffset: Int = 0) -> PrayerEvent {
    Fixture.event(kind, dayOffset: dayOffset)
  }

  @Test func theListedDayIsTheCivilDayOfTheMoment() {
    let display = Self.display(at: Fixture.date(13, 0))
    #expect(display.listedDay?.day == Fixture.civilDay())
    #expect(display.slots.map(\.kind) == PrayerKind.allCases)
    // Just after midnight, the next day is listed.
    #expect(
      Self.display(at: Fixture.date(0, 10, dayOffset: 1)).listedDay?.day
        == Fixture.civilDay(offset: 1))
  }

  /// The focus counts down to the next event, sunrise included.
  @Test func theFocusIsTheNextEventSunriseIncluded() {
    #expect(Self.display(at: Fixture.date(13, 0)).focus == .countdown(event(.asr)))
    #expect(Self.display(at: Fixture.date(5, 0)).focus == .countdown(event(.sunrise)))
    let atAsr = Self.display(at: event(.asr).time)
    #expect(atAsr.focus == .countUp(event(.asr)), "at its start a prayer counts up")
  }

  /// The imminent red: the next prayer's last 15 minutes, start inclusive; never before
  /// sunrise, which isn't a prayer.
  @Test func theNextPrayerIsImminentInItsLastFifteenMinutes() {
    let asr = event(.asr).time
    #expect(Self.display(at: asr.adding(minutes: -15, seconds: -1)).tone == .normal)
    #expect(Self.display(at: asr.adding(minutes: -15)).tone == .imminent)
    #expect(Self.display(at: asr.adding(seconds: -1)).tone == .imminent)
    let beforeSunrise = Self.display(at: event(.sunrise).time.adding(minutes: -5))
    #expect(beforeSunrise.tone == .normal)
    #expect(beforeSunrise.focus == .countdown(event(.sunrise)))
  }

  /// A prayer that just started leads as the green count-up for exactly 15 minutes (end
  /// exclusive); its row reads "Now", then the next prayer's countdown takes over and
  /// the row dims. Sunrise never counts up.
  @Test func aPrayerCountsUpForFifteenMinutesAndSunriseNever() {
    let dhuhr = event(.dhuhr)
    let during = Self.display(at: dhuhr.time.adding(minutes: 14, seconds: 59))
    #expect(during.focus == .countUp(dhuhr))
    #expect(during.backgroundTone == .playingPrayerAudio)
    #expect(during.rowState(for: dhuhr, status: during.prayerState?.status(of: dhuhr)) == .current)
    let after = Self.display(at: dhuhr.time.adding(minutes: 15))
    #expect(after.focus == .countdown(event(.asr)))
    #expect(after.rowState(for: dhuhr, status: after.prayerState?.status(of: dhuhr)) == .passed)
    let afterSunrise = Self.display(at: event(.sunrise).time.adding(minutes: 2))
    #expect(afterSunrise.focus == .countdown(dhuhr))
    #expect(afterSunrise.backgroundTone == .normal)
  }

  /// When the next prayer is already imminent during a count-up, the count-up keeps the
  /// focus and the next row turns red.
  @Test func theCountUpKeepsTheFocusWhileTheNextPrayerIsImminent() {
    let settings = Self.settings { $0.ishaAdjustment = -78 }
    let maghrib = Fixture.event(.maghrib, ishaAdjustment: -78)
    let isha = Fixture.event(.isha, ishaAdjustment: -78)
    let display = SalahDisplay(
      date: maghrib.time.adding(minutes: 4), settings: settings, schedule: settings.schedule)
    #expect(display.focus == .countUp(maghrib))
    #expect(
      display.rowState(for: isha, status: display.prayerState?.status(of: isha)) == .next(.imminent)
    )
  }

  /// The "since" count-up marks the latest event, sunrise included, once its count-up
  /// is over; the small widget's line names it.
  @Test func sinceTextMarksTheLatestEventAfterItsCountUp() {
    let display = Self.display(at: event(.dhuhr).time.adding(minutes: 90))
    let dhuhr = event(.dhuhr)
    #expect(display.sinceText(for: dhuhr, status: .passed) == "\u{2068}+1:30\u{2069}")
    #expect(display.sinceText(for: event(.fajr), status: .passed) == nil)
    #expect(display.sinceLine == "Dhuhr since: \u{2068}+1:30\u{2069}")
    let afterSunrise = Self.display(at: event(.sunrise).time.adding(minutes: 20))
    #expect(afterSunrise.sinceText(for: event(.sunrise), status: .passed) == "\u{2068}+20m\u{2069}")
    let countingUp = Self.display(at: dhuhr.time.adding(minutes: 4))
    #expect(countingUp.sinceText(for: dhuhr, status: .justStarted) == nil)
    #expect(countingUp.sinceLine == nil)
    // While its adhan plays, the row is the playing one, not "Now": it keeps the text.
    let playing = Self.display(
      at: dhuhr.time.adding(minutes: 2), playback: SalahPlayback(event: dhuhr, slot: .alert))
    #expect(playing.sinceText(for: dhuhr, status: .justStarted) == "\u{2068}+2m\u{2069}")
  }

  /// Regression for the one-day snapshot's defect: before Fajr there was no previous
  /// prayer, because yesterday wasn't in the snapshot. SalahCore's state crosses
  /// midnight: at 04:00 yesterday's Isha is the latest prayer and the previous event.
  @Test func beforeFajrTheLatestPrayerIsYesterdaysIsha() throws {
    let display = Self.display(at: Fixture.date(4, 0))
    let state = try #require(display.prayerState)
    let yesterdaysIsha = Fixture.event(.isha, dayOffset: -1)
    #expect(state.previous == yesterdaysIsha)
    #expect(state.latestPrayer == yesterdaysIsha)
    #expect(display.focus == .countdown(event(.fajr)))
    let elapsed = display.text.duration(
      display.date.timeIntervalSince(yesterdaysIsha.time), direction: .elapsed, bidiIsolated: true)
    #expect(display.sinceLine == "Isha since: \(elapsed)")
    #expect(elapsed.hasPrefix("\u{2068}+7:"))
  }

  /// After Isha's count-up, the focus is tomorrow's Fajr, which has no row today; today's
  /// Fajr row stays passed.
  @Test func afterIshaTheFocusIsTomorrowsFajr() throws {
    let display = Self.display(at: event(.isha).time.adding(minutes: 60))
    #expect(display.focus == .countdown(event(.fajr, dayOffset: 1)))
    #expect(display.focusIsTomorrow)
    #expect(display.floatingFocus == .countdown(event(.fajr, dayOffset: 1)))
    let fajr = event(.fajr)
    #expect(display.rowState(for: fajr, status: display.prayerState?.status(of: fajr)) == .passed)
  }

  @Test func silentModeMutesEveryToneButKeepsTheFocus() {
    let display = Self.display(at: event(.asr).time.adding(minutes: -10)) { $0.silentMode = true }
    #expect(display.tone == .silent)
    #expect(display.backgroundTone == .silent)
    #expect(display.focus == .countdown(event(.asr)))
    let asr = event(.asr)
    #expect(
      display.rowState(for: asr, status: display.prayerState?.status(of: asr)) == .next(.silent))
  }

  /// Playing audio sets the tone by slot and marks its prayer's row active; silent mode
  /// still wins.
  @Test func playingAudioSetsTheToneAndTheActiveRow() {
    let maghrib = event(.maghrib)
    let at = maghrib.time.adding(minutes: -10)
    for (slot, tone) in [
      (SalahPlayback.Slot.alert, SalahWidgetTone.playingPrayerAudio),
      (.preReminder, .playingPreReminderAudio), (.postReminder, .playingPostReminderAudio),
    ] {
      let display = Self.display(at: at, playback: SalahPlayback(event: maghrib, slot: slot))
      #expect(display.tone == tone)
      #expect(display.backgroundTone == tone)
      #expect(display.rowState(for: maghrib, status: .next(approaching: true)) == .active(tone))
    }
    let silent = Self.display(at: at, playback: SalahPlayback(event: maghrib, slot: .alert)) {
      $0.silentMode = true
    }
    #expect(silent.tone == .silent)
  }

  /// Without a known state, rows are passed or upcoming by their times alone.
  @Test func withoutAStateRowsFollowTheirTimes() {
    let display = Self.display(at: Fixture.date(13, 0))
    #expect(display.rowState(for: event(.fajr), status: nil) == .passed)
    #expect(display.rowState(for: event(.asr), status: nil) == .upcoming)
  }

  // MARK: - Missing schedule data

  /// Regression for the snapshot's defect: without tomorrow's times the next prayer
  /// wrapped to today's Fajr, already passed, and the focus counted down to it. Now the
  /// next prayer is unknown: no focus, no countdown, the place says so.
  @Test func withoutTomorrowTheNextPrayerIsUnknownNotInvented() throws {
    let today = Fixture.day()
    let schedule = PrayerSchedule(
      source: PreviewSource(days: [Fixture.civilDay(): today.events]), location: Fixture.location)
    let at = event(.isha).time.adding(minutes: 60)
    let display = SalahDisplay(
      date: at, settings: Self.settings(), day: schedule.day(Fixture.civilDay()),
      state: schedule.state(at: at, through: at.addingTimeInterval(SalahDisplay.lookahead)))
    let state = try #require(display.prayerState)
    #expect(state.previous == event(.isha))
    #expect(state.next == nil && state.nextPrayer == nil)
    #expect(display.focus == nil)
    #expect(display.floatingFocus == nil)
    #expect(display.tone == .normal)
  }

  /// A kind the source can't give today stays a place in the day, in canonical order,
  /// so the views show it with a dash instead of leaving it out.
  @Test func aMissingKindKeepsItsPlace() throws {
    var events = Fixture.day().events
    events.removeAll { $0.kind == .sunrise || $0.kind == .isha }
    let schedule = PrayerSchedule(
      source: PreviewSource(days: [Fixture.civilDay(): events]), location: Fixture.location)
    let display = SalahDisplay(
      date: Fixture.date(13, 0), settings: Self.settings(), day: schedule.day(Fixture.civilDay()),
      state: schedule.state(at: Fixture.date(13, 0), through: Fixture.date(13, 0, dayOffset: 2)))
    #expect(
      display.slots == [
        .event(event(.fajr)), .missing(.sunrise), .event(event(.dhuhr)), .event(event(.asr)),
        .event(event(.maghrib)), .missing(.isha),
      ])
  }
}
