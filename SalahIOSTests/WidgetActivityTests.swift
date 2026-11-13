import Foundation
import SalahCore
import SalahUI
import SwiftUI
import Testing
import WidgetKit

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

  /// iOS suspends Salah in the background, so a countdown nobody updates goes stale at its
  /// prayer's time. What it shows then must stay true with no further update.
  @Test func staleCountdownShowsThePrayerAsBegunAndCountsUpFromIt() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let display = SalahDisplay(
      date: prayer.time.addingTimeInterval(-10 * 60), settings: settings,
      schedule: settings.schedule)
    let state = try #require(SalahActivityAttributes.ContentState(display: display))
    let stale = state.stale
    #expect(stale.mode == .justStarted && stale.showsTimer)
    // Where, not "now" or "next prayer": the activity can stay for hours.
    #expect(stale.eyebrow == state.place && !state.place.isEmpty)
    #expect(stale.prayerName == state.prayerName && stale.prayerTimeText == state.prayerTimeText)
    // The system's timer runs from the prayer's time for as long as iOS keeps the activity.
    #expect(stale.timerInterval.lowerBound == prayer.time)
    #expect(stale.timerInterval.upperBound == prayer.time.addingTimeInterval(12 * 60 * 60))
    let later = prayer.time.addingTimeInterval(27 * 60 + 41)
    #expect(stale.timerSeconds(at: later) == 27 * 60 + 41)
    #expect(stale.progress(at: later) == 1)
  }

  @Test func staleCountUpKeepsCountingPastItsFifteenMinutes() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let display = SalahDisplay(
      date: prayer.time.addingTimeInterval(9 * 60), settings: settings,
      schedule: settings.schedule)
    let state = try #require(SalahActivityAttributes.ContentState(display: display))
    #expect(state.timerInterval.upperBound == prayer.time.addingTimeInterval(15 * 60))
    let stale = state.stale
    #expect(stale.mode == .justStarted && stale.eyebrow == state.place)
    // Twelve hours from going stale, which is no earlier than the activity's request.
    #expect(stale.timerInterval.lowerBound == prayer.time)
    #expect(stale.timerInterval.upperBound == state.validUntil.addingTimeInterval(12 * 60 * 60))
    #expect(stale.timerSeconds(at: prayer.time.addingTimeInterval(40 * 60)) == 40 * 60)
    #expect(stale.clockValue(at: prayer.time.addingTimeInterval(40 * 60)) == "0:40:00")
  }

  /// An adhan played at its prayer's time ends inside the count-up window, so its stale
  /// activity counts up like the prayer's own.
  @Test func staleAdhanAtThePrayersTimeCountsUpFromThePrayer() throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let playingAt = prayer.time.addingTimeInterval(60)
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: prayer, slot: .alert), startedAt: prayer.time,
      duration: 4 * 60)
    let display = SalahDisplay(date: playingAt, settings: settings, schedule: settings.schedule)
    let playing = try #require(
      SalahActivityAttributes.ContentState(display: display, playbackSession: session))
    #expect(playing.mode == .playing)
    let stale = playing.stale
    #expect(stale.mode == .justStarted)
    #expect(stale.timerInterval.lowerBound == prayer.time)
  }

  /// A sound played away from its prayer's time (before it, or an adhan replayed
  /// hours later) leaves nothing to count: the stale activity keeps the prayer and stops.
  @Test(arguments: [-20 * 60, 3 * 60 * 60] as [TimeInterval])
  func stalePlaybackAwayFromThePrayersTimeEnds(offset: TimeInterval) throws {
    let settings = try settings()
    let prayer = try event(.asr, settings: settings)
    let startedAt = prayer.time.addingTimeInterval(offset)
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: prayer, slot: .alert),
      startedAt: startedAt, duration: 4 * 60)
    let display = SalahDisplay(
      date: startedAt.addingTimeInterval(30), settings: settings, schedule: settings.schedule)
    let playing = try #require(
      SalahActivityAttributes.ContentState(display: display, playbackSession: session))
    #expect(playing.mode == .playing)
    let stale = playing.stale
    #expect(stale.mode == .ended && !stale.showsTimer)
    #expect(stale.eyebrow == playing.place)
    #expect(stale.progress(at: playing.validUntil) == 1)
    #expect(stale.timerInterval.lowerBound <= stale.timerInterval.upperBound)
    let spoken = stale.spokenLabel(at: playing.validUntil)
    #expect(spoken == "\(playing.prayerName), \(playing.prayerTimeText)")
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

  /// WidgetKit draws every entry of a timeline before it shows the first, so a newly added
  /// widget waits on its placeholder for all of them. The faces that count down and fill
  /// their bar by themselves take an entry only where what they show changes.
  @Test func selfRunningFacesPlanADozenEntriesAtStateChangesOnly() throws {
    for family in [WidgetFamily.systemSmall, .systemMedium, .systemLarge] {
      #expect(IOSPrayerWidgetProvider.cadence(for: family) == .stateChanges, "\(family)")
    }
    for family in [
      WidgetFamily.systemExtraLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular,
    ] {
      #expect(IOSPrayerWidgetProvider.cadence(for: family) == .steps, "\(family)")
    }
    #expect(SalahWidgetTimeline.Cadence.stateChanges.entryLimit == 12)

    let settings = try settings()
    let asr = try event(.asr, settings: settings)
    let now = asr.time.addingTimeInterval(-(2 * 3_600 + 16 * 60))
    let live = IOSSurfaceTimeline.make(
      settings: settings, session: nil, now: now, cadence: .stateChanges)
    let stepped = IOSSurfaceTimeline.make(settings: settings, session: nil, now: now)
    #expect(live.entries.count == 12)
    #expect(stepped.entries.count == SalahWidgetTimeline.entryLimit)
    #expect(live.cadence == .stateChanges)

    // What a face shows without its timers: the focus, its tone, the listed day and the rows.
    func shown(_ entry: SalahWidgetEntry) -> [String] {
      guard case .schedule(let display) = entry.content else { return ["expired"] }
      return [
        display.focus.map { "\($0.event.id) \($0.isCountUp)" } ?? "none",
        "\(display.prayerState?.isApproaching == true)",
        "\(String(describing: display.listedDay?.day))",
        "\(WidgetTimes.rows(of: display).map { "\($0.event.id) \($0.role)" })",
      ]
    }
    let faces = live.entries.map(shown)
    #expect(zip(faces, faces.dropFirst()).allSatisfy { $0 != $1 })
    // The stepped cadence repeats one face many times over, which is the work this avoids.
    let steppedFaces = stepped.entries.map(shown)
    #expect(zip(steppedFaces, steppedFaces.dropFirst()).contains { $0 == $1 })
    // A quarter of the entries still last longer, and the timeline reloads halfway through.
    let end = try #require(live.entries.last).date
    #expect(end > (try #require(stepped.entries.last).date))
    #expect(end.timeIntervalSince(now) >= 8 * 3_600)
    guard case .expired = try #require(live.entries.last).content else {
      Issue.record("A timeline cut at its entry limit must end by asking for a refresh")
      return
    }
    guard case .after(let reload) = live.reload else {
      Issue.record("A planned timeline asks for its successor")
      return
    }
    #expect(reload > now && reload < end)
  }

  /// A playing prayer's Stop face and the schedule after it fit the same dozen entries.
  @Test func playbackKeepsASelfRunningTimelineInsideItsEntryLimit() throws {
    let settings = try settings()
    let asr = try event(.asr, settings: settings)
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: asr, slot: .alert), startedAt: asr.time, duration: 90)
    let timeline = IOSSurfaceTimeline.make(
      settings: settings, session: session, now: asr.time, cadence: .stateChanges)
    #expect(timeline.entries.count <= 12)
    guard case .schedule(let first) = try #require(timeline.entries.first).content else {
      Issue.record("Expected the computed schedule")
      return
    }
    #expect(first.playback == session.playback)
    #expect(timeline.entries.contains { $0.date == session.expiresAt })
  }

  /// The gallery asks for its preview while a person scrolls through the sizes: it gets the
  /// sample day at once, without waiting for anything Salah saved.
  @Test func galleryPreviewIsTheSampleDayAndReadsNothingSaved() throws {
    let bundle = Bundle(for: WidgetProviderResources.self)
    let entry = IOSPrayerWidgetProvider.snapshot(
      isPreview: true, now: Date(timeIntervalSince1970: 0),
      loadSettings: {
        Issue.record("The gallery's preview must not read saved settings")
        return nil
      },
      loadSession: {
        Issue.record("The gallery's preview must not read what's playing")
        return nil
      }, bundle: bundle)
    // 2 June 2026, 1:19 PM in Makkah, standing still: Asr at 3:35 PM is 2:16:00 away.
    #expect(entry.date == IOSWidgetSample.date)
    #expect(entry.stillAt == IOSWidgetSample.date)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    #expect(
      calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entry.date)
        == DateComponents(year: 2026, month: 6, day: 2, hour: 13, minute: 19))
    guard case .schedule(let display) = entry.content else {
      Issue.record("The sample is a whole day's schedule")
      return
    }
    let focus = try #require(display.focus)
    #expect(focus.event.kind == .asr && !focus.isCountUp)
    #expect(focus.event.time.timeIntervalSince(entry.date) == 2 * 3_600 + 16 * 60)
    #expect(display.listedDay?.events.count == 6)
    #expect(display.playback == nil)
    #expect(display.settings.location.timeZone.identifier == "Asia/Riyadh")
  }

  /// The sample's place reads in the language its words do.
  @Test(arguments: [
    (AppLanguage.english, "Makkah"), (.arabic, "مكة المكرمة"), (.french, "La Mecque"),
    (.turkish, "Mekke"), (.persian, "مکه"), (.urdu, "مکہ مکرمہ"), (.bengali, "মক্কা"),
    (.indonesian, "Makkah"), (.malay, "Makkah"),
  ])
  func samplePlaceIsNamedInTheWidgetsLanguage(language: AppLanguage, name: String) throws {
    let settings = try #require(
      IOSWidgetSample.settings(
        language: language, bundle: Bundle(for: WidgetProviderResources.self)))
    #expect(settings.location.name == name)
    #expect(settings.language == language)
  }

  /// A placed widget shows a person's own schedule, or the setup face: never the sample.
  @Test func placedWidgetSnapshotIsTheSavedScheduleOrSetup() throws {
    let settings = try settings()
    let asr = try event(.asr, settings: settings)
    let session = IOSPlaybackSession(
      playback: SalahPlayback(event: asr, slot: .alert), startedAt: asr.time, duration: 90)
    let empty = IOSPrayerWidgetProvider.snapshot(
      isPreview: false, now: asr.time, loadSettings: { nil }, loadSession: { session })
    guard case .setupNeeded = empty.content else {
      Issue.record("Without saved settings a placed widget asks for setup")
      return
    }
    #expect(empty.date == asr.time && empty.stillAt == nil)
    let placed = IOSPrayerWidgetProvider.snapshot(
      isPreview: false, now: asr.time, loadSettings: { settings }, loadSession: { session })
    guard case .schedule(let display) = placed.content else {
      Issue.record("Saved settings give a placed widget its schedule")
      return
    }
    #expect(placed.date == asr.time && placed.stillAt == nil)
    #expect(display.settings.location.name == "Makkah")
    #expect(display.playback == session.playback)
  }

  /// A formatter costs far more to make than to use, and a timeline draws every row of every
  /// entry several times over. Making one per row is what slowed the archive down.
  @Test func aTimelinesClockTimesAndDigitsShareTheirFormatters() throws {
    let settings = try settings()
    let events = try #require(
      settings.schedule.day(CivilDay(year: 2026, month: 6, day: 2)).day?.events)
    let cache = SalahFormatterCache()
    var text = SalahText(locale: settings.locale, timeZone: settings.location.timeZone)
    text.formatters = cache
    for _ in 0..<SalahWidgetTimeline.entryLimit {
      for event in events {
        #expect(!text.compactTime(event.time).isEmpty)
        #expect(!text.clockTime(event.time).isEmpty)
        #expect(text.digits(16, minimumDigits: 2) == "16")
      }
    }
    // One clock formatter, the day period's beside it, and one for the digits.
    #expect(cache.creations == 3)
    let asr = try event(.asr, settings: settings)
    #expect(text.clockTime(asr.time) == text.timeFormatter().string(from: asr.time))
    #expect(text.clockTime(asr.time) == "3:35\u{202F}PM")
    #expect(text.compactTime(asr.time) == "\u{2068}3:35\u{2069}")
    // Another zone gets formatters of its own.
    var london = text
    london.timeZone = try #require(TimeZone(identifier: "Europe/London"))
    #expect(london.clockTime(asr.time) == "1:35\u{202F}PM")
    #expect(cache.creations == 5)
  }

  /// The large face's rows show the time with its day period; VoiceOver reads the same for
  /// the smaller faces, whose rows drop it.
  @Test func rowsReadThePrayerAndItsFullTime() throws {
    let settings = try settings()
    let asr = try event(.asr, settings: settings)
    let display = SalahDisplay(
      date: asr.time.addingTimeInterval(-600), settings: settings, schedule: settings.schedule)
    #expect(WidgetTimes.accessibilityLabel(of: asr, in: display) == "Asr, 3:35\u{202F}PM")
  }

  /// The bar runs from the prayer one is in to the next.
  @Test func progressSpansThePrayerOneIsInToTheNext() throws {
    let settings = try settings()
    let dhuhr = try event(.dhuhr, settings: settings)
    let asr = try event(.asr, settings: settings)
    let now = asr.time.addingTimeInterval(-(2 * 3_600 + 16 * 60))
    let display = SalahDisplay(date: now, settings: settings, schedule: settings.schedule)
    #expect(WidgetProgress.span(of: display) == dhuhr.time...asr.time)
    #expect(
      WidgetProgress.fraction(of: display)
        == CGFloat(now.timeIntervalSince(dhuhr.time) / asr.time.timeIntervalSince(dhuhr.time)))
  }

  /// The system draws its timer progress bar in the device's direction whatever the face's
  /// environment says, so the face mirrors it exactly when its own language reads the other way.
  @Test func runningProgressIsMirroredOnlyWhenTheFaceAndTheDeviceReadOppositeWays() {
    #expect(IOSRunningProgress.isMirrored(face: .rightToLeft, host: .leftToRight))
    #expect(IOSRunningProgress.isMirrored(face: .leftToRight, host: .rightToLeft))
    #expect(!IOSRunningProgress.isMirrored(face: .rightToLeft, host: .rightToLeft))
    #expect(!IOSRunningProgress.isMirrored(face: .leftToRight, host: .leftToRight))
    #expect(EnvironmentValues().hostLayoutDirection == .leftToRight)
  }

  /// A person who swipes the activity away on the Lock Screen sees it again the next time
  /// they open Salah. While Salah stays open, or wakes in the background, it stays away.
  @Test @MainActor func aDismissedActivityStartsAgainOnReturningToSalah() async throws {
    let suite = "SalahIOSTests.returning.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = try settings()
    let asr = try event(.asr, settings: settings)
    let now = asr.time.addingTimeInterval(-10 * 60)
    let state = try #require(
      SalahActivityAttributes.ContentState(
        display: SalahDisplay(date: now, settings: settings, schedule: settings.schedule)))
    let eventID = SalahActivityAttributes.eventID(for: state)
    var dismissals = IOSActivityDismissals(defaults: defaults)
    dismissals.insert(eventID, until: IOSActivityDismissals.deadline(for: state), now: now)

    var requested: [String] = []
    let coordinator = IOSActivityCoordinator(
      now: { now }, loadPlaybackSession: { nil },
      lifecycle: IOSActivityLifecycle(
        activities: { [] }, end: { _ in },
        request: { state in
          requested.append(SalahActivityAttributes.eventID(for: state))
          return nil
        }), defaults: defaults)
    // Still open, and refreshing every half minute: the dismissal holds.
    await coordinator.refresh(settings: settings, isForeground: true)
    #expect(requested.isEmpty)
    // Woken in the background: nothing starts, and the dismissal is kept.
    await coordinator.refresh(settings: settings, isForeground: false, returning: true)
    #expect(requested.isEmpty)
    #expect(coordinator.dismissals.contains(eventID, at: now))
    // Back in Salah: the approaching prayer's activity starts again.
    await coordinator.refresh(settings: settings, isForeground: true, returning: true)
    #expect(requested == [eventID])
    #expect(!coordinator.dismissals.contains(eventID, at: now))
    #expect(!IOSActivityDismissals(defaults: defaults).contains(eventID, at: now))
  }

  /// Returning to Salah outside a prayer's window starts nothing: only a near or current
  /// prayer has an activity.
  @Test @MainActor func returningStartsNoActivityFarFromAPrayer() async throws {
    let suite = "SalahIOSTests.returningFar.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = try settings()
    let asr = try event(.asr, settings: settings)
    var requested = 0
    let coordinator = IOSActivityCoordinator(
      now: { asr.time.addingTimeInterval(-2 * 3_600) }, loadPlaybackSession: { nil },
      lifecycle: IOSActivityLifecycle(
        activities: { [] }, end: { _ in },
        request: { _ in
          requested += 1
          return nil
        }), defaults: defaults)
    await coordinator.refresh(settings: settings, isForeground: true, returning: true)
    #expect(requested == 0)
  }

  /// A new language shows on the Live Activity before the notifications are rescheduled, which
  /// takes longer; a newer change stops the older one from scheduling them again.
  @Test @MainActor func aChangedPreferenceReachesTheActivityBeforeTheNotifications() async {
    var order: [String] = []
    await IOSSurfaceRefresh(
      activity: { order.append("activity") }, notifications: { order.append("notifications") }
    ).run()
    #expect(order == ["activity", "notifications"])

    order = []
    let superseded = Task { @MainActor in
      await IOSSurfaceRefresh(
        activity: {
          order.append("activity")
          withUnsafeCurrentTask { $0?.cancel() }
        }, notifications: { order.append("notifications") }
      ).run()
    }
    await superseded.value
    #expect(order == ["activity"])
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

private final class WidgetProviderResources: NSObject {}
