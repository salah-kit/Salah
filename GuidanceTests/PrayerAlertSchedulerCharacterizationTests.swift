import Adhan
import Foundation
import Testing
import UserNotifications

/// Characterizes `PrayerAlertScheduler` as imported at `4bc00e9`, before SalahAlerts
/// replaces it (proposal §3.1, §7.5). Tests named `characterizes…` pin behavior the
/// proposal corrects; C2 turns them into regressions for the corrected contracts.
/// The rest is behavior the port retains.
///
/// Every test drives the real scheduler through its seams: scratch preferences, a
/// fake notification center, a recording audio player and a manual clock. Times are
/// the fixture's (Makkah, Tue 2 June 2026): Fajr 04:11, Sunrise 05:38, Dhuhr 12:19,
/// Asr 15:35, Maghrib 19:00, Isha 20:30.
@Suite("PrayerAlertScheduler characterization")
struct PrayerAlertSchedulerCharacterizationTests {
  init() { TestEnvironment.configure() }

  // MARK: - Harness

  final class Harness {
    let scratch = ScratchDefaults()
    let preferences: Preferences
    let center = FakeNotificationCenter()
    let audio = RecordingAudioPlayer()
    let clock: ManualClock
    let scheduler: PrayerAlertScheduler

    /// Prayers missing from `settings` are switched off, so each test sees only the
    /// alerts it names. `defaultSettings` keeps the app's defaults instead.
    init(
      now: Date,
      settings: [Prayer: PrayerNotificationConfig] = [:],
      defaultSettings: Bool = false,
      prepare: (Preferences, FakeNotificationCenter) -> Void = { _, _ in }
    ) {
      var resolved = settings
      if !defaultSettings {
        for prayer in Prayer.allCases where resolved[prayer] == nil { resolved[prayer] = .off }
      }
      preferences = .scratch(scratch, settings: resolved)
      clock = ManualClock(now)
      prepare(preferences, center)
      scheduler = PrayerAlertScheduler(
        audioPlaybackController: audio, preferences: preferences, center: center,
        clock: clock.alertClock)
    }

    /// Lets the launch housekeeping the initializer starts finish.
    func launch() async {
      await settle(center)
    }

    /// `scheduleNotifications` as `PrayerManager` calls it, then waits for the
    /// pending-request update and the catch-up delivery to finish.
    func schedule(_ days: [PrayerTimes] = Fixture.threeDayWindow) async {
      await launch()
      center.forgetCalls()
      scheduler.scheduleNotifications(for: days, formattedTime: Fixture.formattedTime)
      await scheduler.notificationUpdateTask?.value
      await settle(center)
    }
  }

  static func identifier(_ prayer: String, _ kind: String, _ fireDate: Date) -> String {
    "guidance.prayer.\(prayer).\(kind).\(Int(fireDate.timeIntervalSince1970))"
  }

  static let today = Fixture.prayerTimes()
  static let tomorrow = Fixture.prayerTimes(dayOffset: 1)

  // MARK: - The three-day window and the 60-request cap

  /// Defect (F2): `PrayerManager` hands the scheduler only yesterday, today and
  /// tomorrow in the prayer calendar (`PrayerManager.swift:249-313`, by calendar day,
  /// not 24-hour steps), so alerts run out about two days after the app last ran.
  /// SalahAlerts plans a horizon (14 days by default) within a request budget.
  @Test func characterizesTheAlertWindowIsYesterdayTodayAndTomorrow() throws {
    // 01:30 in Riyadh is still 1 June in UTC: the window follows the prayer zone.
    let now = Fixture.date(1, 30)
    let window = try #require(
      PrayerManager.alertWindowDays(around: now, calendar: Fixture.calendar))
    #expect(window.yesterday.1 == Fixture.dayComponents(offset: -1))
    #expect(window.today.1 == Fixture.dayComponents(offset: 0))
    #expect(window.tomorrow.1 == Fixture.dayComponents(offset: 1))
    #expect(window.today.0 == Fixture.date(0, 0))
    #expect(window.yesterday.0 == Fixture.date(0, 0, dayOffset: -1))
    #expect(window.tomorrow.0 == Fixture.date(0, 0, dayOffset: 1))

    // On New York's spring-forward day the next day starts 23 hours later.
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York")!
    let springForward = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
    let dst = try #require(PrayerManager.alertWindowDays(around: springForward, calendar: newYork))
    #expect(dst.yesterday.1 == DateComponents(year: 2026, month: 3, day: 7))
    #expect(dst.tomorrow.1 == DateComponents(year: 2026, month: 3, day: 9))
    #expect(dst.tomorrow.0.timeIntervalSince(dst.today.0) == 23 * 3600)
  }

  /// Every enabled alert still ahead in the window becomes one calendar request, in
  /// fire-date order. Yesterday's and today's passed alerts are not requested.
  @Test func schedulesEveryEnabledAlertStillAheadInTheWindow() async {
    let harness = Harness(now: Fixture.date(13, 0), defaultSettings: true)
    await harness.schedule()

    let expected = [
      Self.identifier("asr", "prayerTime", Self.today.asr),
      Self.identifier("maghrib", "prayerTime", Self.today.maghrib),
      Self.identifier("isha", "prayerTime", Self.today.isha),
      Self.identifier("fajr", "prayerTime", Self.tomorrow.fajr),
      Self.identifier("dhuhr", "prayerTime", Self.tomorrow.dhuhr),
      Self.identifier("asr", "prayerTime", Self.tomorrow.asr),
      Self.identifier("maghrib", "prayerTime", Self.tomorrow.maghrib),
      Self.identifier("isha", "prayerTime", Self.tomorrow.isha),
    ]
    #expect(harness.center.scheduled.map(\.identifier) == expected)
    #expect(harness.center.immediate.isEmpty)
    #expect(harness.audio.plays.isEmpty)
  }

  /// Defect (F2; §7.5 "The budget and coverage"): the scheduler keeps the first 60
  /// requests by fire date, whatever their kind. With every kind on for six prayers
  /// over five days, the fourth day's reminders crowd out its later adhans, and the
  /// fifth day is dropped. SalahAlerts reserves the near-term window, then fills
  /// with later at-time alerts.
  @Test func characterizesFirstSixtyRequestsByFireDateWithoutKindPriority() async {
    let everything = PrayerNotificationConfig.alert(before: 10, after: 5)
    let settings = Dictionary(uniqueKeysWithValues: Prayer.allCases.map { ($0, everything) })
    let harness = Harness(now: Fixture.date(0, 0), settings: settings)
    let days = (0..<5).map { Fixture.prayerTimes(dayOffset: $0) }
    await harness.schedule(days)

    var candidates: [(id: String, time: Date)] = []
    for times in days {
      for prayer in Prayer.allCases {
        let time = times.time(for: prayer)
        candidates.append(
          (
            Self.identifier(prayer.settingsKey, "preReminder", time.adding(minutes: -10)),
            time.adding(minutes: -10)
          ))
        candidates.append((Self.identifier(prayer.settingsKey, "prayerTime", time), time))
        candidates.append(
          (
            Self.identifier(prayer.settingsKey, "postReminder", time.adding(minutes: 5)),
            time.adding(minutes: 5)
          ))
      }
    }
    let byTime = candidates.sorted { $0.time < $1.time }.map(\.id)
    #expect(byTime.count == 90)
    #expect(harness.center.scheduled.map(\.identifier) == Array(byTime.prefix(60)))

    // The 60th request is the fourth day's Sunrise post-reminder; that day's Dhuhr
    // adhan, ten minutes later than its pre-reminder, is not requested.
    let fourthDay = days[3]
    #expect(
      harness.center.scheduled.last?.identifier
        == Self.identifier("sunrise", "postReminder", fourthDay.sunrise.adding(minutes: 5)))
    #expect(
      !harness.center.scheduled.contains {
        $0.identifier == Self.identifier("dhuhr", "prayerTime", fourthDay.dhuhr)
      })
  }

  /// Defect (F2), with the window above: the cap can't bind in the app, since six
  /// prayers times three kinds times three days is at most 54 requests.
  @Test func characterizesTheThreeDayWindowNeverReachesTheCap() async {
    let everything = PrayerNotificationConfig.alert(before: 10, after: 5)
    let settings = Dictionary(uniqueKeysWithValues: Prayer.allCases.map { ($0, everything) })
    let harness = Harness(now: Fixture.date(0, 0, dayOffset: -1), settings: settings)
    await harness.schedule()
    #expect(harness.center.scheduled.count == 54)
  }

  // MARK: - Catch-up windows

  /// Plain data, because Swift Testing builds arguments outside the main actor.
  nonisolated struct CatchUpCase: Sendable, CustomTestStringConvertible {
    enum Kind: String, Sendable { case prayerTime, preReminder, postReminder }
    var name: String
    var kind: Kind
    /// The reminder offset in minutes; ignored for the adhan.
    var offset: Int = 0
    /// Seconds after the fire date that the scheduler runs; negative is early.
    var lateness: Double
    var caughtUp: Bool

    var testDescription: String { name }
  }

  /// Catch-up after launch, wake or a late recalculation (`PrayerAlertScheduler.swift:133-146`):
  /// at-time alerts within five minutes, reminders within two, and a before-reminder
  /// never once its prayer has started. Anything within 1.5 s ahead counts as due.
  /// Caught-up alerts are delivered at once and their sound plays.
  @Test(arguments: [
    CatchUpCase(name: "adhan due 1 s ahead", kind: .prayerTime, lateness: -1, caughtUp: true),
    CatchUpCase(name: "adhan on time", kind: .prayerTime, lateness: 0, caughtUp: true),
    CatchUpCase(name: "adhan 299 s late", kind: .prayerTime, lateness: 299, caughtUp: true),
    CatchUpCase(name: "adhan 300 s late", kind: .prayerTime, lateness: 300, caughtUp: true),
    CatchUpCase(name: "adhan 301 s late", kind: .prayerTime, lateness: 301, caughtUp: false),
    CatchUpCase(
      name: "after-reminder 120 s late", kind: .postReminder, offset: 5, lateness: 120,
      caughtUp: true),
    CatchUpCase(
      name: "after-reminder 121 s late", kind: .postReminder, offset: 5, lateness: 121,
      caughtUp: false),
    CatchUpCase(
      name: "before-reminder 120 s late", kind: .preReminder, offset: 10, lateness: 120,
      caughtUp: true),
    CatchUpCase(
      name: "before-reminder 121 s late", kind: .preReminder, offset: 10, lateness: 121,
      caughtUp: false),
    CatchUpCase(
      name: "before-reminder 59 s late, prayer not started", kind: .preReminder, offset: 1,
      lateness: 59, caughtUp: true),
    CatchUpCase(
      name: "before-reminder 90 s late, prayer started", kind: .preReminder, offset: 1,
      lateness: 90, caughtUp: false),
  ])
  func catchUpWindows(_ testCase: CatchUpCase) async {
    // Only the alert under test is on, with the Makkah adhan as its sound.
    let config: PrayerNotificationConfig
    let fireDate: Date
    switch testCase.kind {
    case .prayerTime:
      config = .alert(sound: .makkah)
      fireDate = Self.today.dhuhr
    case .preReminder:
      config = .alert(false, before: testCase.offset, beforeSound: .makkah)
      fireDate = Self.today.dhuhr.adding(minutes: -Double(testCase.offset))
    case .postReminder:
      config = .alert(false, after: testCase.offset, afterSound: .makkah)
      fireDate = Self.today.dhuhr.adding(minutes: Double(testCase.offset))
    }
    let harness = Harness(
      now: fireDate.adding(seconds: testCase.lateness), settings: [.dhuhr: config])
    await harness.schedule()

    let id = Self.identifier("dhuhr", testCase.kind.rawValue, fireDate)
    let delivered = harness.center.immediate.map(\.identifier).contains(id)
    #expect(delivered == testCase.caughtUp)
    #expect(harness.audio.plays.count == (testCase.caughtUp ? 1 : 0))
    if testCase.caughtUp {
      #expect(harness.audio.plays.first?.request.context.prayerTime == Self.today.dhuhr)
      #expect(Self.soundFile(harness.audio.plays.first) == "Adhan-Makkah.mp3")
    }
    // A passed or due alert never gets a calendar request.
    #expect(!harness.center.scheduled.contains { $0.identifier == id })
  }

  // MARK: - Requests: identifiers, content, triggers

  /// Defect (§7.5 "Identity and updates"): the identifier is prefix, prayer, kind and
  /// the fire date's Unix time (`:666-668`). Moving a reminder changes its
  /// identifier, so the old request is removed and a new one added. SalahAlerts
  /// keys a request by namespace, owning day, prayer and kind instead.
  @Test func characterizesIdentifiersCarryTheFireTimestamp() async {
    let harness = Harness(now: Fixture.date(6, 0), settings: [.dhuhr: .alert(before: 10, after: 5)])
    await harness.schedule([Self.today])

    let preTen = Self.identifier("dhuhr", "preReminder", Self.today.dhuhr.adding(minutes: -10))
    #expect(
      harness.center.scheduled.map(\.identifier) == [
        preTen,
        Self.identifier("dhuhr", "prayerTime", Self.today.dhuhr),
        Self.identifier("dhuhr", "postReminder", Self.today.dhuhr.adding(minutes: 5)),
      ])
    #expect(preTen == "guidance.prayer.dhuhr.preReminder.1780391340")

    harness.preferences.setConfig(.alert(before: 15, after: 5), for: .dhuhr)
    await harness.schedule([Self.today])
    let preFifteen = Self.identifier("dhuhr", "preReminder", Self.today.dhuhr.adding(minutes: -15))
    #expect(harness.center.calls.contains(.removePending([preTen])))
    #expect(harness.center.pending.map(\.identifier).contains(preFifteen))
    #expect(!harness.center.pending.map(\.identifier).contains(preTen))
  }

  /// At-time and before alerts are time-sensitive, after alerts active
  /// (`:638-643`); relevance 1.0 / 0.7 / 0.5; one thread; the prayer name as title.
  /// Only `.system` sounds ride on the notification: the app plays its own audio.
  @Test func requestContentPerKind() async throws {
    let harness = Harness(
      now: Fixture.date(6, 0),
      settings: [
        .dhuhr: .alert(
          sound: .alafasy, before: 10, beforeSound: .system, after: 5, afterSound: .none)
      ])
    await harness.schedule([Self.today])

    let requests = harness.center.scheduled
    try #require(requests.count == 3)
    let (pre, atTime, post) = (requests[0].content, requests[1].content, requests[2].content)

    #expect(pre.interruptionLevel == .timeSensitive)
    #expect(atTime.interruptionLevel == .timeSensitive)
    #expect(post.interruptionLevel == .active)
    #expect([pre.relevanceScore, atTime.relevanceScore, post.relevanceScore] == [0.7, 1.0, 0.5])
    #expect(Set([pre, atTime, post].map(\.threadIdentifier)) == ["guidance-prayers"])
    #expect([pre, atTime, post].allSatisfy { $0.title == "Dhuhr" })

    #expect(atTime.body == "It's time for Dhuhr (\(Fixture.formattedTime(Self.today.dhuhr)))")
    #expect(pre.body == "Pre-reminder for Dhuhr (\u{2068}10\u{2069} min before).")
    #expect(post.body == "Post-reminder for Dhuhr (\u{2068}5\u{2069} min after).")

    #expect(pre.userInfo["prayer"] as? String == "dhuhr")
    #expect(pre.userInfo["kind"] as? String == "preReminder")
    #expect(pre.userInfo["offsetMinutes"] as? Int == 10)
    #expect(atTime.userInfo["kind"] as? String == "prayerTime")
    #expect(atTime.userInfo["offsetMinutes"] as? Int == 0)
    #expect(post.userInfo["offsetMinutes"] as? Int == 5)

    #expect(pre.sound != nil)  // .system
    #expect(atTime.sound == nil)  // built-in adhan: played by the app
    #expect(post.sound == nil)  // .none
  }

  /// Silent mode drops the notification sound too: the sound is decided when the
  /// request is built, which is why `silentMode` reschedules.
  @Test func silentModeSchedulesSilentRequests() async {
    let harness = Harness(now: Fixture.date(6, 0), settings: [.dhuhr: .alert(sound: .system)]) {
      preferences, _ in preferences.silentMode = true
    }
    await harness.schedule([Self.today])
    #expect(harness.center.scheduled.count == 1)
    #expect(harness.center.scheduled.first?.content.sound == nil)
  }

  /// Calendar triggers use a Gregorian calendar in UTC and never repeat
  /// (`:492-504`), so a time-zone change doesn't move a pending request.
  @Test func triggersAreNonRepeatingUTCCalendarDates() async throws {
    let harness = Harness(now: Fixture.date(6, 0), settings: [.dhuhr: .alert()])
    await harness.schedule([Self.today])

    let request = try #require(harness.center.scheduled.first)
    let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
    let utc = TimeZone(secondsFromGMT: 0)!
    #expect(!trigger.repeats)
    #expect(trigger.dateComponents.timeZone == utc)
    #expect(trigger.dateComponents.calendar?.identifier == .gregorian)
    #expect(trigger.dateComponents.calendar?.timeZone == utc)
    // Dhuhr 12:19 in Riyadh is 09:19 UTC.
    #expect(trigger.dateComponents.year == 2026)
    #expect(trigger.dateComponents.month == 6)
    #expect(trigger.dateComponents.day == 2)
    #expect(trigger.dateComponents.hour == 9)
    #expect(trigger.dateComponents.minute == 19)
    #expect(trigger.dateComponents.second == 0)
  }

  // MARK: - Housekeeping and request replacement

  static func delivered(_ id: String, _ date: Date, title: String = "", body: String = "")
    -> PrayerAlertDeliveredNotification
  {
    PrayerAlertDeliveredNotification(identifier: id, date: date, title: title, body: body)
  }

  /// At launch the scheduler removes its own delivered notifications older than two
  /// days, and nothing else (`:378-416`).
  @Test func launchHousekeepingRemovesOnlyOldOwnDeliveredNotifications() async {
    let now = Fixture.date(13, 0)
    let cutoff = now.adding(seconds: -2 * 86_400)
    let old = "guidance.prayer.fajr.prayerTime.1"
    let atCutoff = "guidance.prayer.dhuhr.prayerTime.2"
    let recent = "guidance.prayer.asr.prayerTime.3"
    let foreign = "com.example.other"
    let harness = Harness(now: now) { _, center in
      center.delivered = [
        Self.delivered(old, cutoff.adding(seconds: -1)),
        Self.delivered(atCutoff, cutoff),
        Self.delivered(recent, now.adding(minutes: -60)),
        Self.delivered(foreign, cutoff.adding(seconds: -3600)),
      ]
    }
    await harness.launch()
    #expect(harness.center.calls == [.deliveredNotifications, .removeDelivered([old])])
    #expect(harness.center.delivered.map(\.identifier) == [atCutoff, recent, foreign])
  }

  /// Each reschedule also removes own delivered notifications that no longer match
  /// an alert in the window: unknown identifiers and changed title or body. Other
  /// apps' notifications stay.
  @Test func rescheduleRemovesOwnDeliveredNotificationsThatNoLongerMatch() async {
    let now = Fixture.date(13, 0)
    let fajr = Self.identifier("fajr", "prayerTime", Self.today.fajr)
    let fajrBody = "It's time for Fajr (\(Fixture.formattedTime(Self.today.fajr)))"
    let changed = Self.identifier("dhuhr", "prayerTime", Self.today.dhuhr)
    let unknown = "guidance.prayer.fajr.prayerTime.1"
    let foreign = "com.example.other"
    let harness = Harness(now: now, settings: [.fajr: .alert(), .dhuhr: .alert()]) { _, center in
      center.delivered = [
        Self.delivered(fajr, Self.today.fajr, title: "Fajr", body: fajrBody),
        Self.delivered(changed, Self.today.dhuhr, title: "Dhuhr", body: "old wording"),
        Self.delivered(unknown, now.adding(minutes: -30)),
        Self.delivered(foreign, now.adding(minutes: -30)),
      ]
    }
    await harness.schedule()
    #expect(harness.center.delivered.map(\.identifier) == [fajr, foreign])
  }

  /// Defect (§7.5 "Identity and updates", A-30): pending requests that are no longer
  /// wanted are removed before any new request is added (`:330-349`). With timestamp
  /// identifiers a moved alert is one of them, so its old request goes before the new
  /// one exists. SalahAlerts replaces a changed request by adding it under its stable
  /// identifier, without removing it first; it promises no atomic or gap-free batch,
  /// and obsolete cleanup is reconciled. Requests still wanted aren't removed first,
  /// and other apps' requests are left alone.
  @Test func characterizesStaleRequestsAreRemovedBeforeAnyAdd() async throws {
    let stale = "guidance.prayer.asr.prayerTime.1"
    let wanted = Self.identifier("maghrib", "prayerTime", Self.today.maghrib)
    let foreign = "com.example.other"
    func request(_ id: String) -> UNNotificationRequest {
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
      return UNNotificationRequest(
        identifier: id, content: UNMutableNotificationContent(), trigger: trigger)
    }
    let harness = Harness(
      now: Fixture.date(13, 0), settings: [.maghrib: .alert(), .isha: .alert()]
    ) { _, center in
      center.pending = [request(stale), request(wanted), request(foreign)]
    }
    await harness.schedule([Self.today])

    let calls = harness.center.calls
    let removal = try #require(calls.firstIndex(of: .removePending([stale])))
    let firstAdd = try #require(calls.firstIndex { if case .add = $0 { true } else { false } })
    #expect(removal < firstAdd)
    #expect(
      Set(harness.center.pending.map(\.identifier)) == [
        wanted, foreign, Self.identifier("isha", "prayerTime", Self.today.isha),
      ])
  }

  /// An empty schedule (no prayer times) removes every own pending request and
  /// every own delivered notification.
  @Test func emptyScheduleClearsOwnRequestsAndDeliveries() async {
    let own = "guidance.prayer.isha.prayerTime.1"
    let harness = Harness(now: Fixture.date(13, 0)) { _, center in
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
      center.pending = [
        UNNotificationRequest(
          identifier: own, content: UNMutableNotificationContent(), trigger: trigger),
        UNNotificationRequest(
          identifier: "com.example.other", content: UNMutableNotificationContent(), trigger: trigger
        ),
      ]
      center.delivered = [
        Self.delivered(own, Fixture.date(12, 0)),
        Self.delivered("com.example.other", Fixture.date(12, 0)),
      ]
    }
    await harness.schedule([])
    #expect(harness.center.pending.map(\.identifier) == ["com.example.other"])
    #expect(harness.center.delivered.map(\.identifier) == ["com.example.other"])
  }

  // MARK: - Authorization

  /// Denied notifications: own pending requests are removed and nothing is added.
  @Test func deniedAuthorizationRemovesOwnRequestsAndAddsNone() async {
    let own = "guidance.prayer.isha.prayerTime.1"
    let harness = Harness(now: Fixture.date(13, 0), settings: [.isha: .alert()]) { _, center in
      center.status = .denied
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
      center.pending = [
        UNNotificationRequest(
          identifier: own, content: UNMutableNotificationContent(), trigger: trigger)
      ]
    }
    await harness.schedule()
    #expect(harness.center.added.isEmpty)
    #expect(harness.center.pending.isEmpty)
    #expect(!harness.center.calls.contains(.requestAuthorization))
  }

  /// Undetermined authorization is requested once there is something to schedule,
  /// and never when every alert is off.
  @Test func authorizationIsRequestedOnlyWithSomethingToSchedule() async {
    let asking = Harness(now: Fixture.date(13, 0), settings: [.isha: .alert()]) { _, center in
      center.status = .notDetermined
    }
    await asking.schedule()
    #expect(asking.center.calls.filter { $0 == .requestAuthorization }.count == 1)
    #expect(asking.center.scheduled.count == 2)  // today's and tomorrow's Isha

    let quiet = Harness(now: Fixture.date(13, 0)) { _, center in center.status = .notDetermined }
    await quiet.schedule()
    #expect(!quiet.center.calls.contains(.requestAuthorization))
    #expect(quiet.center.added.isEmpty)
  }

  // MARK: - Audio

  static func soundFile(_ play: RecordingAudioPlayer.Play?) -> String? {
    guard case .url(let url)? = play?.request.resource else { return nil }
    return url.lastPathComponent
  }

  /// Audio precedence (`:549-558`): of the alerts due together, the latest fire date
  /// plays; at the same instant the adhan beats a before-reminder, which beats an
  /// after-reminder. Only one sound plays, at the configured volume.
  @Test func latestDueAlertPlays() async {
    // Dhuhr's adhan (12:19) and its after-reminder (12:20) are both due at 12:20:01.
    let harness = Harness(
      now: Self.today.dhuhr.adding(minutes: 1, seconds: 1),
      settings: [.dhuhr: .alert(sound: .alafasy, after: 1, afterSound: .makkah)])
    await harness.schedule()
    #expect(harness.audio.plays.count == 1)
    #expect(Self.soundFile(harness.audio.plays.first) == "Adhan-Makkah.mp3")
    #expect(harness.audio.plays.first?.request.context.slot == .postReminder)
    #expect(harness.audio.plays.first?.request.volume == 0.5)
    // Both are still delivered as notifications.
    #expect(
      Set(harness.center.immediate.map(\.identifier)) == [
        Self.identifier("dhuhr", "prayerTime", Self.today.dhuhr),
        Self.identifier("dhuhr", "postReminder", Self.today.dhuhr.adding(minutes: 1)),
      ])
  }

  @Test func adhanBeatsABeforeReminderAtTheSameInstant() async {
    // Isha (20:30) minus 90 minutes is Maghrib (19:00).
    let harness = Harness(
      now: Self.today.maghrib.adding(seconds: 0.5),
      settings: [
        .maghrib: .alert(sound: .makkah),
        .isha: .alert(false, before: 90, beforeSound: .istanbul),
      ])
    await harness.schedule()
    #expect(harness.audio.plays.count == 1)
    #expect(Self.soundFile(harness.audio.plays.first) == "Adhan-Makkah.mp3")
    #expect(harness.audio.plays.first?.request.context.prayer == .maghrib)
  }

  @Test func beforeReminderBeatsAnAfterReminderAtTheSameInstant() async {
    // Maghrib + 45 and Isha − 45 are both 19:45.
    let harness = Harness(
      now: Self.today.maghrib.adding(minutes: 45),
      settings: [
        .maghrib: .alert(false, after: 45, afterSound: .yusuf),
        .isha: .alert(false, before: 45, beforeSound: .istanbul),
      ])
    await harness.schedule()
    #expect(harness.audio.plays.count == 1)
    #expect(Self.soundFile(harness.audio.plays.first) == "Adhan-Istanbul.mp3")
    #expect(harness.audio.plays.first?.request.context.slot == .preReminder)
  }

  /// The du'a follows only an adhan, only while it's enabled.
  @Test func duaFollowsOnlyTheAdhan() async {
    let adhan = Harness(now: Self.today.maghrib, settings: [.maghrib: .alert(sound: .makkah)])
    await adhan.schedule()
    guard case .url(let dua)? = adhan.audio.plays.first?.followUp?.resource else {
      Issue.record("expected a du'a follow-up")
      return
    }
    #expect(dua.lastPathComponent == "Dua.m4a")
    #expect(adhan.audio.plays.first?.followUp?.context.source == .dua)

    let reminder = Harness(
      now: Self.today.maghrib.adding(minutes: 5),
      settings: [.maghrib: .alert(false, after: 5, afterSound: .makkah)])
    await reminder.schedule()
    #expect(reminder.audio.plays.count == 1)
    #expect(reminder.audio.plays.first?.followUp == nil)

    let noDua = Harness(now: Self.today.maghrib, settings: [.maghrib: .alert(sound: .makkah)]) {
      preferences, _ in preferences.duaEnabled = false
    }
    await noDua.schedule()
    #expect(noDua.audio.plays.count == 1)
    #expect(Self.soundFile(noDua.audio.plays.first) == "Adhan-Makkah.mp3")
    #expect(noDua.audio.plays.first?.followUp == nil)
  }

  /// System and silent sounds never start app audio, and silent mode mutes all.
  @Test func systemSoundsAndSilentModePlayNoAppAudio() async {
    let system = Harness(now: Self.today.maghrib, settings: [.maghrib: .alert(sound: .system)])
    await system.schedule()
    #expect(system.audio.plays.isEmpty)
    #expect(system.center.immediate.count == 1)

    let silent = Harness(now: Self.today.maghrib, settings: [.maghrib: .alert(sound: .makkah)]) {
      preferences, _ in preferences.silentMode = true
    }
    await silent.schedule()
    #expect(silent.audio.plays.isEmpty)
    #expect(silent.center.immediate.count == 1)
  }

  /// A handled alert isn't played or delivered again by a later reschedule or
  /// check (the engine's deduplication, §7.5 retained behavior).
  @Test func aHandledAlertIsNotRepeated() async {
    let harness = Harness(now: Self.today.dhuhr.adding(seconds: 10), settings: [.dhuhr: .alert()])
    await harness.schedule()
    #expect(harness.audio.plays.count == 1)
    #expect(harness.center.immediate.count == 1)

    await harness.schedule()
    harness.clock.now = Self.today.dhuhr.adding(minutes: 3)
    harness.scheduler.checkPendingAlerts()
    await settle(harness.center)
    #expect(harness.audio.plays.count == 1)
    #expect(harness.center.immediate.isEmpty)  // forgetCalls() cleared the first one
  }

  /// The in-process alert timer is armed 0.15 s after the next pending alert, with
  /// 0.75 s tolerance.
  @Test func armsTheAlertTimerJustAfterTheNextAlert() async throws {
    let harness = Harness(now: Fixture.date(6, 0), settings: [.dhuhr: .alert()])
    await harness.schedule()
    let timer = try #require(harness.clock.timers.last)
    #expect(timer.fireDate == Self.today.dhuhr.adding(seconds: 0.15))
    #expect(timer.tolerance == 0.75)
  }
}
