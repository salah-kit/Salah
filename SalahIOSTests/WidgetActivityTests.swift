import Foundation
import SalahCore
import SalahUI
import Testing

@Suite("iOS widget and activity boundaries")
struct WidgetActivityTests {
  private func settings() throws -> SalahSettings {
    var preferences = IOSPreferences()
    preferences.language = .english
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262,
      timeZone: try #require(TimeZone(identifier: "Asia/Riyadh")),
      countryCode: "SA", name: "Makkah")
    return try #require(preferences.mirror)
  }

  private func event(_ kind: PrayerKind, settings: SalahSettings) throws -> PrayerEvent {
    try #require(settings.schedule.day(CivilDay(year: 2026, month: 6, day: 2)).day?[kind])
  }

  @Test func manualPlaybackUsesActualStartForAnEarlierPrayer() throws {
    let settings = try settings()
    let fajr = try event(.fajr, settings: settings)
    let now = fajr.time.addingTimeInterval(3 * 60 * 60)
    let playback = SalahPlayback(event: fajr, slot: .alert)
    // The old alert-based bound is expired, but a person may press Play now.
    #expect(playback.playing(at: now) == nil)
    let session = IOSPlaybackSession(playback: playback, startedAt: now, duration: 90)
    #expect(session.playing(at: now) == playback)
    #expect(session.playing(at: now.addingTimeInterval(89)) == playback)
    #expect(session.playing(at: now.addingTimeInterval(90)) == nil)
    #expect(session.playing(at: now.addingTimeInterval(-1)) == nil)
    let timeline = IOSSurfaceTimeline.make(settings: settings, session: session, now: now)
    guard case .schedule(let first) = try #require(timeline.entries.first).content else {
      Issue.record("Expected the computed schedule")
      return
    }
    #expect(first.playback == playback)
    let ended = try #require(timeline.entries.first { $0.date == session.expiresAt })
    guard case .schedule(let after) = ended.content else {
      Issue.record("Expected schedule after Stop expires")
      return
    }
    #expect(after.playback == nil)
    #expect(timeline.entries.count <= SalahWidgetTimeline.entryLimit)
  }

  @Test func stopDuringPlanningDoesNotPublishTheCapturedSession() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let now = prayer.time
    var session: IOSPlaybackSession? = IOSPlaybackSession(
      playback: SalahPlayback(event: prayer, slot: .alert), startedAt: now, duration: 90)
    var planned = false
    let timeline = IOSSurfaceTimeline.makeForPublication(
      settings: settings, now: now,
      loadSession: {
        #expect(planned)
        return session
      },
      planSchedule: { settings, now in
        let result = SalahWidgetTimeline.make(settings: settings, playback: nil, now: now)
        session = nil
        planned = true
        return result
      })
    guard case .schedule(let first) = try #require(timeline.entries.first).content else {
      Issue.record("Expected schedule")
      return
    }
    #expect(first.playback == nil)
  }

  @Test func noSettingsCannotPublishInventedPlaybackOrTimes() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: prayer, slot: .alert), startedAt: prayer.time, duration: 60)
    let timeline = IOSSurfaceTimeline.make(settings: nil, session: session, now: prayer.time)
    #expect(timeline.entries.count == 1)
    guard case .setupNeeded = timeline.entries[0].content else {
      Issue.record("A new install must prompt for setup")
      return
    }
  }

  @Test func sessionRejectsInvalidDurationsAndBoundsStalePlayback() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let playback = SalahPlayback(event: prayer, slot: .alert)
    for duration in [Double.nan, Double.infinity, -1, 0] {
      let session = IOSPlaybackSession(
        playback: playback, startedAt: prayer.time, duration: duration)
      #expect(session.playing(at: prayer.time) == nil)
    }
    let bounded = IOSPlaybackSession(
      playback: playback, startedAt: prayer.time, duration: 8 * 60 * 60)
    #expect(IOSPlaybackSession.maximumRecordingDuration == 30 * 60)
    #expect(IOSPlaybackSession.maximumDuration == 32 * 60)
    #expect(bounded.expiresAt.timeIntervalSince(prayer.time) == IOSPlaybackSession.maximumDuration)
    #expect(bounded.playing(at: prayer.time.addingTimeInterval(31 * 60 + 59)) == playback)
    #expect(bounded.playing(at: prayer.time.addingTimeInterval(32 * 60)) == nil)
    var corrupted = bounded
    corrupted.expiresAt = prayer.time.addingTimeInterval(86_400)
    #expect(corrupted.playing(at: prayer.time) == nil)
  }

  @Test func countdownExpiresAtThePrayerInsteadOfCountingPastIt() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let now = prayer.time.addingTimeInterval(-10 * 60)
    let display = SalahDisplay(date: now, settings: settings, schedule: settings.schedule)
    let state = try #require(SalahActivityAttributes.ContentState(display: display))
    #expect(state.mode == .countdown)
    #expect(state.prayerKind == .asr)
    #expect(state.validUntil == prayer.time)
    #expect(state.isValid(at: prayer.time.addingTimeInterval(-1)))
    #expect(!state.isValid(at: prayer.time))
    #expect(state.progress(at: state.progressStart.addingTimeInterval(-60)) == 0)
    #expect(state.progress(at: state.progressEnd.addingTimeInterval(60)) == 1)
  }

  @Test func justStartedCountsUpOnlyWithinThePrayerWindow() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let now = prayer.time.addingTimeInterval(4 * 60)
    let display = SalahDisplay(date: now, settings: settings, schedule: settings.schedule)
    let state = try #require(SalahActivityAttributes.ContentState(display: display))
    #expect(state.mode == .justStarted)
    #expect(state.validUntil == prayer.time.addingTimeInterval(15 * 60))
    #expect(state.eyebrow == display.labels.now)
  }

  @Test func notificationDoesNotProduceAPlayingActivity() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    var display = SalahDisplay(
      date: prayer.time.addingTimeInterval(60), settings: settings, schedule: settings.schedule)
    // Even an old display mirror alone cannot establish actual iOS playback.
    display.playback = SalahPlayback(event: prayer, slot: .alert)
    let state = try #require(SalahActivityAttributes.ContentState(display: display))
    #expect(state.mode == .justStarted)
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: prayer, slot: .alert), startedAt: display.date, duration: 90)
    let playing = try #require(
      SalahActivityAttributes.ContentState(display: display, playbackSession: session))
    #expect(playing.mode == .playing)
    #expect(playing.validUntil == session.expiresAt)
    #expect(playing.progressStart == session.startedAt)
  }

  @Test func everyMeaningfulActivityFieldPublishesInsideTheTimestampThrottle() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let display = SalahDisplay(
      date: prayer.time.addingTimeInterval(-10 * 60), settings: settings,
      schedule: settings.schedule)
    let previous = try #require(SalahActivityAttributes.ContentState(display: display))
    let changes: [(String, (inout SalahActivityAttributes.ContentState) -> Void)] = [
      ("mode", { $0.mode = .justStarted }),
      ("kind", { $0.prayerKind = .fajr }),
      ("observance", { $0.prayerObservance = .jumuah }),
      ("name", { $0.prayerName += " changed" }),
      ("prayerTime", { $0.prayerTime = $0.prayerTime.addingTimeInterval(1) }),
      ("validUntil", { $0.validUntil = $0.validUntil.addingTimeInterval(1) }),
      ("progressStart", { $0.progressStart = $0.progressStart.addingTimeInterval(1) }),
      ("progressEnd", { $0.progressEnd = $0.progressEnd.addingTimeInterval(1) }),
      ("eyebrow", { $0.eyebrow = "Playing du’a" }),
      ("clock text", { $0.prayerTimeText += " changed" }),
      ("place", { $0.place = "Cairo" }),
      ("language", { $0.languageIdentifier = "ar" }),
      ("time zone", { $0.timeZoneIdentifier = "Africa/Cairo" }),
      ("phase", { $0.phase = .isha }),
      ("mute", { $0.muteSounds.toggle() }),
      ("next name", { $0.nextPrayerName = "different" }),
      ("next time", { $0.nextPrayerTime = "different" }),
    ]
    for (field, change) in changes {
      var state = previous
      state.updatedAt = previous.updatedAt.addingTimeInterval(1)
      change(&state)
      #expect(
        IOSActivityCoordinator.shouldPublish(state, after: previous),
        "A change to \(field) must reach ActivityKit before the minute throttle")
    }
    #expect(IOSActivityCoordinator.shouldPublish(previous, after: nil))
    #expect(!IOSActivityCoordinator.shouldPublish(previous, after: previous))
    var timestampOnly = previous
    timestampOnly.updatedAt = previous.updatedAt.addingTimeInterval(59)
    #expect(!IOSActivityCoordinator.shouldPublish(timestampOnly, after: previous))
    timestampOnly.updatedAt = previous.updatedAt.addingTimeInterval(60)
    #expect(IOSActivityCoordinator.shouldPublish(timestampOnly, after: previous))
  }

  @Test func restartingAndChangingToDuaPublishImmediatelyForTheSamePrayer() throws {
    let settings = try settings()
    let fajr = try event(.fajr, settings: settings)
    let startedAt = fajr.time.addingTimeInterval(3 * 60 * 60)
    let playback = SalahPlayback(event: fajr, slot: .alert)
    let firstSession = IOSPlaybackSession(playback: playback, startedAt: startedAt, duration: 90)
    let firstDisplay = SalahDisplay(
      date: startedAt, settings: settings, schedule: settings.schedule)
    let first = try #require(
      SalahActivityAttributes.ContentState(
        display: firstDisplay, playbackSession: firstSession))
    let restartedAt = startedAt.addingTimeInterval(10)
    let restartedSession = IOSPlaybackSession(
      playback: playback, startedAt: restartedAt, duration: 90)
    let restartedDisplay = SalahDisplay(
      date: restartedAt, settings: settings, schedule: settings.schedule)
    let restarted = try #require(
      SalahActivityAttributes.ContentState(
        display: restartedDisplay, playbackSession: restartedSession))
    #expect(IOSActivityCoordinator.shouldPublish(restarted, after: first))
    var duaPlayback = playback
    duaPlayback.isDua = true
    let duaAt = startedAt.addingTimeInterval(20)
    let duaSession = IOSPlaybackSession(playback: duaPlayback, startedAt: startedAt, duration: 120)
    let duaDisplay = SalahDisplay(date: duaAt, settings: settings, schedule: settings.schedule)
    let dua = try #require(
      SalahActivityAttributes.ContentState(
        display: duaDisplay, playbackSession: duaSession))
    #expect(dua.eyebrow == duaDisplay.labels.playingDua)
    #expect(IOSActivityCoordinator.shouldPublish(dua, after: restarted))
  }

  @Test func manualHistoricalPlaybackVisibleAndSpokenTimeUseTheActualStart() throws {
    let settings = try settings()
    let fajr = try event(.fajr, settings: settings)
    let startedAt = fajr.time.addingTimeInterval(3 * 60 * 60)
    let now = startedAt.addingTimeInterval(90)
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: fajr, slot: .alert), startedAt: startedAt, duration: 120)
    let display = SalahDisplay(date: now, settings: settings, schedule: settings.schedule)
    let state = try #require(
      SalahActivityAttributes.ContentState(display: display, playbackSession: session))
    #expect(state.mode == .playing)
    #expect(state.timerInterval.lowerBound == startedAt)
    #expect(state.timerSeconds(at: now) == 90)
    #expect(state.clockValue(at: now) == "0:01:30")
    #expect(state.spokenLabel(at: now) == "Fajr, Playing adhan, 1 minute")
    #expect(state.timerSeconds(at: startedAt.addingTimeInterval(-1)) == 0)
    #expect(state.clockValue(at: startedAt.addingTimeInterval(7)) == "0:00:07")
  }

  @Test func sunriseDoesNotBecomeAPrayerActivity() throws {
    let settings = try settings()
    let sunrise = try event(.sunrise, settings: settings)
    let display = SalahDisplay(
      date: sunrise.time.addingTimeInterval(-60), settings: settings, schedule: settings.schedule)
    #expect(display.focus?.event.kind == .sunrise)
    #expect(SalahActivityAttributes.ContentState(display: display) == nil)
  }
}
