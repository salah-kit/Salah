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

  /// Play works on any row, so the Stop face's times and progress keep to the real time.
  @Test func stopFaceRowsAndProgressFollowTheRealTimeWhenAnotherPrayerPlays() throws {
    let settings = try settings()
    let dhuhr = try event(.dhuhr, settings: settings)
    let asr = try event(.asr, settings: settings)
    for (kind, now) in [
      (PrayerKind.maghrib, dhuhr.time.addingTimeInterval(-2 * 60 * 60)),
      (.fajr, asr.time.addingTimeInterval(-30 * 60)),
    ] {
      let prayer = try event(kind, settings: settings)
      let quiet = SalahDisplay(date: now, settings: settings, schedule: settings.schedule)
      let playing = SalahDisplay(
        date: now, settings: settings, schedule: settings.schedule,
        playback: SalahPlayback(event: prayer, slot: .alert))
      let roles = WidgetTimes.rows(of: quiet).map(\.role)
      #expect(roles.contains(.next))
      #expect(WidgetTimes.rows(of: playing).map(\.role) == roles, "\(kind)")
      let marked = WidgetTimes.markedRows(of: playing)
      #expect(marked.filter { $0.role == .current }.map(\.event.id) == [prayer.id])
      #expect(
        marked.filter { $0.event.id != prayer.id }.map(\.role)
          == WidgetTimes.rows(of: quiet).filter { $0.event.id != prayer.id }.map(\.role))
      #expect(WidgetProgress.fraction(of: playing) == WidgetProgress.fraction(of: quiet))
      #expect(WidgetProgress.fraction(of: playing) < 1)
    }
  }

  /// The adhan of the prayer that just began keeps the face it always had.
  @Test func stopFaceAtThePrayerTimeKeepsItsRowsAndProgress() throws {
    let settings = try settings()
    let maghrib = try event(.maghrib, settings: settings)
    let isha = try event(.isha, settings: settings)
    let now = maghrib.time.addingTimeInterval(2 * 60)
    let playing = SalahDisplay(
      date: now, settings: settings, schedule: settings.schedule,
      playback: SalahPlayback(event: maghrib, slot: .alert))
    let expected: [WidgetTimes.Role] = [.passed, .passed, .passed, .passed, .current, .next]
    #expect(WidgetTimes.markedRows(of: playing).map(\.role) == expected)
    #expect(WidgetTimes.rows(of: playing).map(\.role) == expected)
    #expect(
      WidgetProgress.fraction(of: playing)
        == CGFloat(now.timeIntervalSince(maghrib.time) / isha.time.timeIntervalSince(maghrib.time)))
  }

  @Test @MainActor func dismissalsPersistAcrossLaunchesUntilTheirWindowCloses() throws {
    let suite = "SalahIOSTests.dismissals.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = try settings()
    let asr = try event(.asr, settings: settings)
    let now = asr.time.addingTimeInterval(-10 * 60)
    let state = try #require(
      SalahActivityAttributes.ContentState(
        display: SalahDisplay(date: now, settings: settings, schedule: settings.schedule)))
    let eventID = SalahActivityAttributes.eventID(for: state)
    let deadline = IOSActivityDismissals.deadline(for: state)
    // The approach and the count-up that follows it are one activity for one prayer.
    #expect(deadline == asr.time.addingTimeInterval(15 * 60))
    var dismissals = IOSActivityDismissals(defaults: defaults)
    dismissals.insert(eventID, until: deadline, now: now)
    // A new process reads what the last one recorded.
    let relaunched = IOSActivityCoordinator(
      now: { now }, loadPlaybackSession: { nil }, defaults: defaults)
    #expect(relaunched.dismissals.contains(eventID, at: now))
    #expect(relaunched.dismissals.contains(eventID, at: deadline.addingTimeInterval(-1)))
    #expect(!relaunched.dismissals.contains(eventID, at: deadline))
    // A later dismissal forgets the ones whose window has closed, so the record stays small.
    let maghrib = try event(.maghrib, settings: settings)
    let later = maghrib.time.addingTimeInterval(-10 * 60)
    let laterState = try #require(
      SalahActivityAttributes.ContentState(
        display: SalahDisplay(date: later, settings: settings, schedule: settings.schedule)))
    let laterID = SalahActivityAttributes.eventID(for: laterState)
    dismissals.insert(laterID, until: IOSActivityDismissals.deadline(for: laterState), now: later)
    #expect(defaults.dictionary(forKey: IOSActivityDismissals.key)?.keys.sorted() == [laterID])
    dismissals.remove(laterID)
    #expect(!IOSActivityDismissals(defaults: defaults).contains(laterID, at: later))
  }

  /// A dismissed playback that ends before its prayer's approach holds only for its session:
  /// Maghrib played at midday and dismissed doesn't keep Maghrib's own approach and count-up
  /// from showing that evening. Inside the prayer's window it holds until the count-up ends, as
  /// the approach or count-up it replaced would. An explicit Play clears a prayer's dismissal.
  @Test @MainActor func aDismissedPlaybackHoldsForItsSessionOrItsPrayersWindow() async throws {
    let suite = "SalahIOSTests.playbackDismissals.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = try settings()
    let maghrib = try event(.maghrib, settings: settings)
    let now = maghrib.time.addingTimeInterval(-5 * 60 * 60)
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: maghrib, slot: .alert), startedAt: now, duration: 90)
    let playing = try #require(
      SalahActivityAttributes.ContentState(
        display: SalahDisplay(date: now, settings: settings, schedule: settings.schedule),
        playbackSession: session))
    #expect(playing.mode == .playing)
    #expect(IOSActivityDismissals.deadline(for: playing) == playing.validUntil)
    #expect(IOSActivityDismissals.deadline(for: playing) < maghrib.time)
    let near = maghrib.time.addingTimeInterval(-5 * 60)
    let nearSession = IOSPlaybackSession(
      playback: SalahPlayback(event: maghrib, slot: .alert), startedAt: near, duration: 90)
    let nearPlaying = try #require(
      SalahActivityAttributes.ContentState(
        display: SalahDisplay(date: near, settings: settings, schedule: settings.schedule),
        playbackSession: nearSession))
    #expect(nearPlaying.mode == .playing)
    #expect(
      IOSActivityDismissals.deadline(for: nearPlaying) == maghrib.time.addingTimeInterval(15 * 60))

    var dismissals = IOSActivityDismissals(defaults: defaults)
    dismissals.insert(
      SalahActivityAttributes.eventID(for: playing),
      until: IOSActivityDismissals.deadline(for: playing), now: now)
    let coordinator = IOSActivityCoordinator(
      now: { now }, loadPlaybackSession: { session },
      lifecycle: IOSActivityLifecycle(activities: { [] }, end: { _ in }), defaults: defaults)
    #expect(coordinator.dismissals.contains(SalahActivityAttributes.eventID(for: playing), at: now))
    await coordinator.start(settings: settings)
    #expect(
      !coordinator.dismissals.contains(SalahActivityAttributes.eventID(for: playing), at: now))
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
