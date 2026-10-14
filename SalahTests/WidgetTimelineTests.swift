import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import SalahWidgets
import Testing

/// The widget's timelines, built in the extension from the mirrored settings with
/// SalahWidgets' `PrayerTimelineBuilder` and Salah's steps cadence, with a fixed clock.
/// They replace the app's one-day snapshot, whose timeline ended at midnight and went
/// stale when the app didn't republish; these cross midnight and end with an explicit
/// expired entry instead.
@Suite("Widget timeline")
struct WidgetTimelineTests {
  init() { TestEnvironment.configure() }

  static var settings: SalahSettings {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.appLanguage = .english
    return preferences.mirroredSettings
  }

  static func displays(_ timeline: SalahWidgetTimeline) -> [(Date, SalahDisplay)] {
    timeline.entries.compactMap { entry in
      if case .schedule(let display) = entry.content { return (entry.date, display) }
      return nil
    }
  }

  /// Without settings, the widget asks to set up the app and waits for it: one entry,
  /// no reload until the app saves its first settings.
  @Test func withoutSettingsTheWidgetWaitsForSetup() {
    let timeline = SalahWidgetTimeline.make(settings: nil, playback: nil, now: Fixture.date(13, 0))
    #expect(timeline.entries.count == 1)
    guard case .setupNeeded = timeline.entries.first?.content else {
      Issue.record("expected the setup entry")
      return
    }
    #expect(timeline.reload == .never)
  }

  /// Salah's cadence for its static countdowns: an entry every five minutes, and every
  /// minute within 15 minutes of a prayer, so the imminent red and the count-up advance
  /// minute by minute; a minute before the prayer the live timer takes over.
  @Test func theCadenceIsFiveMinutesAndEveryMinuteAroundAPrayer() throws {
    let start = Fixture.date(13, 0)
    let timeline = SalahWidgetTimeline.make(settings: Self.settings, playback: nil, now: start)
    let asr = Fixture.time(.asr)
    let dates = timeline.entries.map(\.date).filter { $0 <= Fixture.date(16, 0) }
    let expected =
      stride(from: 0, through: 135, by: 5).map { start.adding(minutes: Double($0)) }
      + (-15...15).map { asr.adding(minutes: Double($0)) }
      + [Fixture.date(15, 55), Fixture.date(16, 0)]
    #expect(dates == expected)
  }

  /// Every timeline ends with the expired entry at its validity's end, and asks for the
  /// next one halfway there; the entries fit WidgetKit's budget.
  @Test func aTimelineEndsExpiredAndReloadsHalfway() throws {
    let start = Fixture.date(13, 0)
    let timeline = SalahWidgetTimeline.make(settings: Self.settings, playback: nil, now: start)
    let planned = try #require(timeline.planned)
    guard case .expired = try #require(timeline.entries.last).content else {
      Issue.record("the last entry isn't the expired one")
      return
    }
    #expect(timeline.entries.last?.date == planned.validUntil)
    #expect(
      timeline.reload
        == .after(start.addingTimeInterval(planned.validUntil.timeIntervalSince(start) / 2)))
    #expect(planned.entries.count <= 96)
    #expect(timeline.entries.first?.date == start)
  }

  /// The timeline crosses midnight, and the listed day turns over at it: an entry at the
  /// start of the next day lists that day (the snapshot's timeline stopped at midnight).
  @Test func theListedDayTurnsOverAtMidnight() throws {
    let start = Fixture.date(21, 32)
    let timeline = SalahWidgetTimeline.make(settings: Self.settings, playback: nil, now: start)
    let midnight = Fixture.civilDay(offset: 1).start(in: Fixture.timeZone)
    let displays = Self.displays(timeline)
    let atMidnight = try #require(displays.first { $0.0 == midnight }?.1)
    #expect(atMidnight.listedDay?.day == Fixture.civilDay(offset: 1))
    let before = try #require(displays.last { $0.0 < midnight }?.1)
    #expect(before.listedDay?.day == Fixture.civilDay())
    #expect(before.focusIsTomorrow)
    #expect(!atMidnight.focusIsTomorrow)
    #expect(atMidnight.focus == .countdown(Fixture.event(.fajr, dayOffset: 1)))
  }

  /// Seven days of successive timelines, each asked for at the previous one's reload
  /// date, with no app in between: they cover the week without a hole, and every
  /// entry shows the state SalahCore gives at its date, in the day listed then.
  @Test func sevenDaysOfTimelinesWithoutTheApp() throws {
    let settings = Self.settings
    let schedule = settings.schedule
    var now = Fixture.date(13, 0)
    let end = now.addingTimeInterval(7 * 86_400)
    var timelines = 0
    while now < end {
      let timeline = SalahWidgetTimeline.make(settings: settings, playback: nil, now: now)
      guard case .after(let reload) = timeline.reload else {
        Issue.record("a timeline without a reload date")
        return
      }
      let planned = try #require(timeline.planned)
      #expect(reload <= planned.validUntil && reload > now)
      for (date, display) in Self.displays(timeline) {
        let fresh = schedule.state(
          at: date, through: date.addingTimeInterval(SalahDisplay.lookahead),
          policy: SalahDisplay.policy)
        #expect(display.prayerState?.next == fresh.prayerState?.next, "\(date)")
        #expect(display.prayerState?.justStarted == fresh.prayerState?.justStarted, "\(date)")
        #expect(display.prayerState?.isApproaching == fresh.prayerState?.isApproaching, "\(date)")
        #expect(display.listedDay?.day == CivilDay(containing: date, in: Fixture.timeZone))
      }
      now = reload
      timelines += 1
    }
    #expect(timelines > 7)
  }

  /// What's playing reaches every entry while it can still be playing, so the widget
  /// shows the Stop control until the app publishes that it stopped, and drops it after
  /// that even if the app never does (it crashed): 30 minutes after the alert's time.
  ///
  /// Regression: every entry of the 48-hour timeline, and every timeline after it, showed
  /// the Stop control when the app quit while the adhan played.
  @Test func whatsPlayingReachesTheEntriesWhileItCanPlay() throws {
    let playback = SalahPlayback(event: Fixture.event(.maghrib), slot: .alert)
    let timeline = SalahWidgetTimeline.make(
      settings: Self.settings, playback: playback, now: Fixture.time(.maghrib).adding(minutes: 1))
    let end = Fixture.time(.maghrib).adding(minutes: 30)
    let playing = Self.displays(timeline).filter { $0.0 < end }
    let after = Self.displays(timeline).filter { $0.0 >= end }
    #expect(!playing.isEmpty)
    #expect(playing.allSatisfy { $0.1.playback == playback })
    #expect(!after.isEmpty)
    #expect(after.allSatisfy { $0.1.playback == nil })
    // Within five minutes of the bound, the widget shows the schedule again.
    let first = try #require(after.first?.0)
    #expect(first.timeIntervalSince(end) <= 5 * 60)

    // A reminder's sound is bounded from the reminder's time.
    let reminder = SalahPlayback(
      event: Fixture.event(.maghrib), slot: .preReminder, offsetMinutes: 10)
    #expect(reminder.alertDate == Fixture.time(.maghrib).adding(minutes: -10))
    #expect(reminder.mayBePlaying(at: Fixture.time(.maghrib).adding(minutes: 19)))
    #expect(!reminder.mayBePlaying(at: Fixture.time(.maghrib).adding(minutes: 20)))
    // The widget's snapshot reads it the same way.
    #expect(reminder.playing(at: Fixture.time(.maghrib).adding(minutes: 19)) == reminder)
    #expect(reminder.playing(at: Fixture.time(.maghrib).adding(minutes: 20)) == nil)
  }

  /// A timeline built long after the alert, from a value a crashed app left, shows no
  /// Stop control at all.
  @Test func aLeftoverPlaybackShowsNoStop() {
    let playback = SalahPlayback(event: Fixture.event(.maghrib), slot: .alert, isDua: true)
    let timeline = SalahWidgetTimeline.make(
      settings: Self.settings, playback: playback, now: Fixture.time(.maghrib).adding(minutes: 180))
    #expect(Self.displays(timeline).allSatisfy { $0.1.playback == nil })
  }

  // MARK: - Missing schedule data

  /// Tromsø in the polar night: the calculation gives no sunrise, Asr or Maghrib. The
  /// listed day keeps their places with a dash, and while the schedule can't say what
  /// comes next the entries have no state, so the widget shows that the times aren't
  /// available instead of a countdown.
  @Test func polarNightShowsWhatTheScheduleDoesntKnow() throws {
    let oslo = try #require(TimeZone(identifier: "Europe/Oslo"))
    var settings = Self.settings
    settings.location = PrayerLocation(
      latitude: 69.6492, longitude: 18.9553, timeZone: oslo, countryCode: "NO", name: "Tromsø")
    var parameters = CalculationMethod.muslimWorldLeague.parameters
    parameters.highLatitudeRule = .seventhOfTheNight
    settings.calculation = CalculationSettings(parameters: parameters)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = oslo
    let start = try #require(
      calendar.date(from: DateComponents(year: 2026, month: 12, day: 20, hour: 9)))
    let timeline = SalahWidgetTimeline.make(settings: settings, playback: nil, now: start)
    let displays = Self.displays(timeline)
    let first = try #require(displays.first?.1)
    let missing = first.slots.compactMap { slot -> PrayerKind? in
      if case .missing(let kind) = slot { return kind }
      return nil
    }
    #expect(Set(missing).isSuperset(of: [.sunrise, .maghrib]))
    #expect(first.slots.map(\.kind) == PrayerKind.allCases)
    #expect(displays.contains { $0.1.prayerState == nil })
    for (date, display) in displays where display.prayerState == nil {
      #expect(display.focus == nil, "\(date)")
    }
    guard case .expired = try #require(timeline.entries.last).content else {
      Issue.record("the last entry isn't the expired one")
      return
    }
  }
}
