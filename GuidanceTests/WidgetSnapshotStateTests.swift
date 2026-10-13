import Foundation
import Testing

/// Characterizes the widget snapshot's state and timeline logic
/// (`Shared/GuidanceWidgetModels.swift:57-257`) before SalahCore's `ScheduleState`
/// and `RefreshPlan` replace it (Appendix C). Tests named `characterizes…` pin
/// behavior the proposal corrects.
///
/// The day is the app's own `GuidanceWidgetSnapshot.sample`, in Riyadh: Fajr 04:18
/// (30 min before-reminder), Sunrise 05:41 (no alert), Dhuhr 12:06, Asr 15:31,
/// Maghrib 18:42 (10 min before, 5 min after), Isha 20:00, and tomorrow's Fajr 04:18.
@Suite("Widget snapshot state")
struct WidgetSnapshotStateTests {
  let snapshot: GuidanceWidgetSnapshot

  init() {
    TestEnvironment.configure()
    // After configure(): the sample day is built in the process time zone.
    snapshot = GuidanceWidgetSnapshot.sample(now: Fixture.date(9, 0))
  }

  func at(_ hour: Int, _ minute: Int, _ second: Int = 0, dayOffset: Int = 0) -> Date {
    Fixture.date(hour, minute, second, dayOffset: dayOffset)
  }

  func prayer(_ id: String) -> GuidanceWidgetPrayer {
    snapshot.prayer(id: id)!
  }

  @Test func sampleDay() {
    #expect(snapshot.prayers.map(\.id) == ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"])
    #expect(
      snapshot.prayers.map(\.time) == [
        at(4, 18), at(5, 41), at(12, 6), at(15, 31), at(18, 42), at(20, 0),
      ])
    #expect(snapshot.tomorrowFajr?.time == at(4, 18, dayOffset: 1))
    #expect(snapshot.todayStart == at(0, 0))
    #expect(snapshot.nextDayStart == at(0, 0, dayOffset: 1))
  }

  // MARK: - Current, next and approaching prayers

  @Test func nextPrayerIsTheFirstOneStrictlyLater() {
    #expect(snapshot.nextPrayer(at: at(3, 0))?.id == "fajr")
    #expect(snapshot.nextPrayer(at: at(12, 5, 59))?.id == "dhuhr")
    // A prayer is no longer next at its own time.
    #expect(snapshot.nextPrayer(at: at(12, 6))?.id == "asr")
    #expect(snapshot.nextPrayer(at: at(5, 0))?.id == "sunrise")
  }

  /// The current prayer is the last one started, skipping Sunrise; the previous one
  /// includes Sunrise. Neither exists before Fajr: yesterday isn't in the snapshot.
  @Test func currentPrayerSkipsSunriseAndPreviousPrayerDoesNot() {
    #expect(snapshot.currentPrayer(at: at(4, 17)) == nil)
    #expect(snapshot.previousPrayer(at: at(4, 17)) == nil)
    #expect(snapshot.currentPrayer(at: at(4, 18))?.id == "fajr")
    #expect(snapshot.currentPrayer(at: at(6, 0))?.id == "fajr")
    #expect(snapshot.previousPrayer(at: at(6, 0))?.id == "sunrise")
  }

  /// Approaching: the next prayer turns imminent in its last 15 minutes, both ends
  /// inclusive; the focus stays its countdown.
  @Test func theNextPrayerIsImminentInItsLastFifteenMinutes() {
    #expect(snapshot.tone(at: at(15, 15, 59)) == .normal)
    #expect(snapshot.tone(at: at(15, 16)) == .imminent)
    #expect(snapshot.tone(at: at(15, 30, 59)) == .imminent)
    #expect(snapshot.rowState(for: prayer("asr"), at: at(15, 20)) == .next(.imminent))
    #expect(snapshot.rowState(for: prayer("asr"), at: at(15, 0)) == .next(.normal))
    #expect(snapshot.focus(at: at(15, 20)) == .countdown(prayer("asr")))
    #expect(snapshot.backgroundTone(at: at(15, 20)) == .imminent)
  }

  /// Sunrise is a marker, not an alerted prayer: never imminent, never counting up.
  @Test func sunriseIsNeverImminentAndNeverCountsUp() {
    #expect(snapshot.tone(at: at(5, 30)) == .normal)
    #expect(snapshot.rowState(for: prayer("sunrise"), at: at(5, 30)) == .next(.normal))
    #expect(snapshot.focus(at: at(5, 45)) == .countdown(prayer("dhuhr")))
    #expect(snapshot.rowState(for: prayer("sunrise"), at: at(5, 45)) == .passed)
  }

  // MARK: - Just started and the count-up

  /// A prayer that just started leads as the green count-up for exactly 15 minutes
  /// (end exclusive), its row reads "Now", then the next prayer's countdown takes
  /// over and the row dims.
  @Test func aPrayerJustStartedCountsUpForFifteenMinutes() {
    let dhuhr = prayer("dhuhr")
    #expect(snapshot.focus(at: at(12, 6)) == .countUp(dhuhr))
    #expect(snapshot.focus(at: at(12, 20, 59)) == .countUp(dhuhr))
    #expect(snapshot.focus(at: at(12, 21)) == .countdown(prayer("asr")))
    #expect(snapshot.rowState(for: dhuhr, at: at(12, 10)) == .current)
    #expect(snapshot.rowState(for: dhuhr, at: at(12, 21)) == .passed)
    #expect(snapshot.backgroundTone(at: at(12, 10)) == .playingPrayerAudio)
    #expect(snapshot.tone(at: at(12, 10)) == .normal)  // tone follows the next prayer only
  }

  /// When the next prayer is already imminent during a count-up, the count-up keeps
  /// the focus and the next row turns red.
  @Test func theCountUpKeepsTheFocusWhileTheNextPrayerIsImminent() {
    var close = snapshot
    close.prayers[5].time = at(18, 50)  // Isha eight minutes after Maghrib
    #expect(close.focus(at: at(18, 45)) == .countUp(close.prayers[4]))
    #expect(close.tone(at: at(18, 45)) == .imminent)
    #expect(close.rowState(for: close.prayers[5], at: at(18, 45)) == .next(.imminent))
    #expect(close.backgroundTone(at: at(18, 45)) == .playingPrayerAudio)
  }

  /// The "since" count-up marks the most recent prayer once its green window is
  /// over, Sunrise included.
  @Test func sinceTextMarksTheMostRecentPrayerAfterItsCountUp() {
    #expect(snapshot.sinceText(for: prayer("dhuhr"), at: at(13, 36)) == "\u{2068}+1:30\u{2069}")
    #expect(snapshot.sinceText(for: prayer("dhuhr"), at: at(12, 10)) == nil)
    #expect(snapshot.sinceText(for: prayer("fajr"), at: at(13, 36)) == nil)
    #expect(snapshot.sinceText(for: prayer("sunrise"), at: at(6, 0)) == "\u{2068}+19m\u{2069}")
  }

  // MARK: - Silent mode and playing audio

  @Test func silentModeMutesEveryToneButKeepsTheFocus() {
    var silent = snapshot
    silent.silentMode = true
    #expect(silent.tone(at: at(15, 20)) == .silent)
    #expect(silent.backgroundTone(at: at(12, 10)) == .silent)
    #expect(silent.focus(at: at(12, 10)) == .countUp(prayer("dhuhr")))
    #expect(silent.rowState(for: prayer("asr"), at: at(15, 20)) == .next(.silent))
  }

  /// Playing audio sets the tone by slot and marks its prayer's row active; silent
  /// mode still wins.
  @Test func playingAudioSetsTheToneAndTheActiveRow() {
    var playing = snapshot
    playing.activeAlert = GuidanceWidgetActiveAlert(
      prayerID: "maghrib", prayerName: "Maghrib", slot: .preReminder, offsetMinutes: 10,
      prayerTime: at(18, 42), title: "", subtitle: "")
    #expect(playing.tone(at: at(18, 32)) == .playingPreReminderAudio)
    #expect(playing.backgroundTone(at: at(18, 32)) == .playingPreReminderAudio)
    #expect(
      playing.rowState(for: prayer("maghrib"), at: at(18, 32)) == .active(.playingPreReminderAudio))
    #expect(playing.isActive(prayer("maghrib")))
    #expect(GuidanceWidgetAlertSlot.alert.tone == .playingPrayerAudio)
    #expect(GuidanceWidgetAlertSlot.postReminder.tone == .playingPostReminderAudio)

    playing.silentMode = true
    #expect(playing.tone(at: at(18, 32)) == .silent)

    let stopped = playing.clearingActiveAlert(generatedAt: at(18, 33))
    #expect(stopped.activeAlert == nil)
    #expect(stopped.generatedAt == at(18, 33))
  }

  // MARK: - After Isha, tomorrow's Fajr and staleness

  /// Once Isha's count-up ends, the focus is tomorrow's Fajr, which has no row
  /// today; today's Fajr row, which shares its id, stays passed.
  @Test func afterIshaTheFocusIsTomorrowsFajr() throws {
    let tomorrowFajr = try #require(snapshot.tomorrowFajr)
    #expect(snapshot.focus(at: at(20, 14)) == .countUp(prayer("isha")))
    #expect(snapshot.focus(at: at(20, 15)) == .tomorrow(tomorrowFajr))
    #expect(snapshot.focus(at: at(23, 59)) == .tomorrow(tomorrowFajr))
    #expect(snapshot.nextPrayer(at: at(21, 0)) == tomorrowFajr)
    #expect(snapshot.rowState(for: prayer("fajr"), at: at(21, 0)) == .passed)
    #expect(snapshot.tone(at: at(21, 0)) == .normal)
  }

  /// Defect (missing schedule data, §7.1): without tomorrow's Fajr the next prayer
  /// wraps to today's first prayer, already passed, and the focus counts down to it.
  /// SalahCore reports an unknown next prayer instead of inventing one.
  @Test func characterizesNextPrayerWrapsToTodaysFajrWithoutTomorrow() {
    var partial = snapshot
    partial.tomorrowFajr = nil
    #expect(partial.nextPrayer(at: at(21, 0)) == partial.prayers[0])
    #expect(partial.focus(at: at(21, 0)) == .countdown(partial.prayers[0]))
  }

  /// Defect (F2): the snapshot holds one day and goes stale five minutes after the
  /// next midnight; the widget then asks to open the app, which republishes at
  /// midnight while it runs (`:250-257`). SalahWidgets builds timelines in the
  /// extension instead.
  @Test func characterizesTheSnapshotGoesStaleFiveMinutesAfterMidnight() {
    #expect(!snapshot.isStale(at: at(23, 59)))
    #expect(!snapshot.isStale(at: at(0, 4, 59, dayOffset: 1)))
    #expect(snapshot.isStale(at: at(0, 5, dayOffset: 1)))
  }

  // MARK: - Timeline

  /// From 13:00 the timeline steps every five minutes to just past Asr, every minute
  /// inside Asr's ±15-minute window, then jumps to the remaining prayer and
  /// reminder edges and midnight, and asks to reload at 15:46.
  @Test func timelineFromEarlyAfternoon() {
    let timeline = snapshot.timeline(from: at(13, 0))
    let everyFive = stride(from: 0, through: 165, by: 5).map {
      at(13, 0).adding(minutes: Double($0))
    }
    let asrWindow = (16...46).map { at(15, $0) }
    let edges = [at(18, 32), at(18, 42), at(18, 47), at(20, 0), at(0, 0, dayOffset: 1)]
    #expect(timeline.dates == Set(everyFive + asrWindow + edges).sorted())
    #expect(timeline.dates.count == 64)
    #expect(timeline.reload == at(15, 46))
  }

  /// After Isha the timeline runs every five minutes to midnight and reloads there.
  @Test func timelineAfterIshaEndsAtMidnight() {
    let timeline = snapshot.timeline(from: at(21, 0))
    #expect(
      timeline.dates
        == stride(from: 0, through: 180, by: 5).map { at(21, 0).adding(minutes: Double($0)) })
    #expect(timeline.reload == at(0, 0, dayOffset: 1))
  }

  /// The horizon is at least two hours and at most four, never past midnight, and a
  /// timeline never exceeds 96 entries.
  @Test func timelineHorizonBounds() {
    // 05:00: the next prayer is Sunrise (05:41); two hours wins.
    #expect(snapshot.timeline(from: at(5, 0)).reload == at(7, 0))
    // 07:00: Dhuhr 12:06 is past four hours; four hours wins.
    #expect(snapshot.timeline(from: at(7, 0)).reload == at(11, 0))
    for hour in 0..<24 {
      #expect(snapshot.timeline(from: at(hour, 7)).dates.count <= 96)
    }
  }

  // MARK: - Reload gating and locale

  /// Republishing identical content doesn't reload the widget: `generatedAt` is
  /// ignored (the proposal keeps this reload gating).
  @Test func reloadGatingIgnoresOnlyGeneratedAt() {
    var later = snapshot
    later.generatedAt = at(10, 0)
    #expect(snapshot.hasSameContent(as: later))
    later.silentMode = true
    #expect(!snapshot.hasSameContent(as: later))
  }

  /// The widget rebuilds the locale from its identifier and restores the numbering
  /// system the identifier drops.
  @Test(arguments: [
    ("ar", "arab"), ("ur", "arabext"), ("fa", "arabext"), ("bn", "beng"), ("fr", "latn"),
    ("en", "latn"),
  ])
  func resolvedLocaleKeepsLocalDigits(_ identifier: String, _ numbering: String) {
    var localized = snapshot
    localized.localeIdentifier = identifier
    #expect(localized.resolvedLocale.numberingSystem.identifier == numbering)
  }
}
