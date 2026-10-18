import Foundation
import SalahAlerts
import SalahCore
import Testing
import UserNotifications

/// Salah's alert wiring on SalahAlerts: what `PrayerAlertCoordinator` plans, the requests
/// and content it installs, when it asks for permission, what it posts and plays when
/// alerts come due, and how it catches up after sleep or a clock change.
///
/// Every test drives the real coordinator through its seams: scratch preferences, a fake
/// notification center, a recording audio player and a manual clock. Times are the
/// fixture's (Makkah, Tue 2 June 2026): Fajr 04:11, Sunrise 05:38, Dhuhr 12:19, Asr 15:35,
/// Maghrib 19:00, Isha 20:30. Friday is 5 June (`dayOffset: 3`).
@Suite("PrayerAlertCoordinator")
struct PrayerAlertCoordinatorTests {
  init() { TestEnvironment.configure() }

  // MARK: - Harness

  /// One coordinator over its own preferences, fake center, audio player and clock.
  final class Harness {
    let scratch = ScratchDefaults()
    let preferences: Preferences
    let clock: ManualAlertClock
    let center: FakeNotificationCenter
    let audio = RecordingAudioPlayer()
    let coordinator: PrayerAlertCoordinator

    /// Prayers missing from `settings` keep the app's defaults, or are switched off with
    /// `othersOff`. `prepare` runs before the coordinator exists.
    init(
      now: Date,
      settings: [PrayerKind: PrayerNotificationConfig] = [:],
      othersOff: Bool = false,
      language: AppLanguage = .english,
      status: UNAuthorizationStatus = .authorized,
      statusAfterRequest: UNAuthorizationStatus = .authorized,
      pending: [UNNotificationRequest] = [],
      prepare: (Preferences) -> Void = { _ in }
    ) {
      var resolved = settings
      if othersOff {
        for prayer in PrayerKind.allCases where resolved[prayer] == nil { resolved[prayer] = .off }
      }
      preferences = .scratch(scratch, settings: resolved)
      preferences.appLanguage = language
      prepare(preferences)
      clock = ManualAlertClock(now)
      center = FakeNotificationCenter(
        status: status, statusAfterRequest: statusAfterRequest, time: clock.instant,
        pending: pending)
      coordinator = PrayerAlertCoordinator(
        preferences: preferences, center: center, audio: audio, clock: clock)
    }

    /// `update(schedule:)` as the app calls it, then waits for the installation and any
    /// delivery it started.
    @discardableResult
    func update(_ schedule: PrayerSchedule = Fixture.schedule()) async -> NotificationApplyReport? {
      coordinator.update(schedule: schedule)
      return await settle()
    }

    /// Waits for the latest installation and delivery; returns the installation's report.
    @discardableResult
    func settle() async -> NotificationApplyReport? {
      let report = await coordinator.installation?.value ?? nil
      await coordinator.delivery?.value
      return report
    }

    /// Fires the engine's armed wake-up, as its timer would, and waits for the delivery.
    func fire() async {
      clock.fire()
      await settle()
    }

    /// Moves the clock without firing the wake-up (a sleep or a clock change), then does
    /// what the app does on wake: `catchUp(schedule:)`.
    func wake(at date: Date) async {
      clock.now = date
      coordinator.catchUp(schedule: Fixture.schedule())
      await settle()
    }

    /// The request identifiers pending in the fake center.
    var pendingIdentifiers: [String] { center.pending.map(\.identifier) }
  }

  /// The request identifier of a fixture alert.
  static func identifier(_ prayer: PrayerKind, _ kind: AlertKind, dayOffset: Int = 0) -> String {
    NotificationIdentity(
      namespace: "prayers", scheduleDay: Fixture.civilDay(offset: dayOffset), prayer: prayer,
      kind: kind
    ).requestIdentifier(prefix: "io.github.salah-kit.Salah.")
  }

  /// The instant a request's calendar trigger names.
  static func fireDate(of request: UNNotificationRequest) -> Date? {
    (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents.date
  }

  /// A request another app or feature left pending.
  static func foreignRequest(_ identifier: String) -> UNNotificationRequest {
    UNNotificationRequest(
      identifier: identifier, content: UNMutableNotificationContent(),
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3_600, repeats: false))
  }

  /// Whether two instants agree to a millisecond, past floating-point noise.
  static func isNear(_ date: Date, _ other: Date) -> Bool {
    abs(date.timeIntervalSince(other)) < 0.001
  }

  /// Text without its bidi isolates (U+2068, U+2069).
  static func withoutIsolates(_ text: String) -> String {
    text.replacing("\u{2068}", with: "").replacing("\u{2069}", with: "")
  }

  static let asr = Fixture.event(.asr)
  static let maghrib = Fixture.event(.maghrib)
  static let alafasy = BuiltInAdhanSound.alafasy.bundledURL
  static let makkah = BuiltInAdhanSound.makkah.bundledURL

  // MARK: - Planning and requests

  /// At 13:00 with Maghrib's reminders on, the coordinator installs exactly the default
  /// budget's 60 requests: every alert of the next two days (both days' Maghrib reminders
  /// among them), then later at-time alerts. Each has its stable identifier, Salah's
  /// thread and a non-repeating Gregorian UTC calendar trigger at its fire instant, and
  /// the read-back confirms them all.
  ///
  /// Regression: the scheduler used the wall clock while the plan used the injected one,
  /// so at the fixture's instant (in the wall clock's past) it added nothing.
  @Test func installsTheBudgetedPlanUnderStableIdentifiers() async throws {
    let now = Fixture.date(13, 0)
    let harness = Harness(now: now, settings: [.maghrib: .alert(before: 10, after: 5)])
    let report = try #require(await harness.update())
    let schedule = try #require(harness.coordinator.alertSchedule)
    let alerts = Dictionary(
      uniqueKeysWithValues: schedule.alerts.map {
        ($0.id.requestIdentifier(prefix: PrayerAlertCoordinator.identifierPrefix), $0)
      })

    let pending = harness.center.pending
    #expect(pending.count == 60)
    let utc = TimeZone(identifier: "UTC")
    for request in pending {
      let alert = try #require(alerts[request.identifier])
      #expect(
        NotificationIdentity(
          requestIdentifier: request.identifier, prefix: "io.github.salah-kit.Salah.")
          == alert.id)
      #expect(alert.id.namespace == "prayers")
      #expect(request.content.threadIdentifier == "salah-prayers")
      let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
      #expect(!trigger.repeats)
      #expect(trigger.dateComponents.calendar?.identifier == .gregorian)
      #expect(trigger.dateComponents.timeZone == utc)
      #expect(trigger.dateComponents.date == alert.fireDate)
      #expect(alert.fireDate > now)
    }
    #expect(
      pending.contains {
        $0.identifier == "io.github.salah-kit.Salah.prayers/2026-06-02/asr/atTime"
      })
    let identifiers = Set(pending.map(\.identifier))
    for day in 0...1 {
      #expect(identifiers.contains(Self.identifier(.maghrib, .before, dayOffset: day)))
      #expect(identifiers.contains(Self.identifier(.maghrib, .after, dayOffset: day)))
    }
    // The third day's reminders fall after the near-term window: the engine keeps them.
    #expect(!identifiers.contains(Self.identifier(.maghrib, .before, dayOffset: 2)))
    #expect(alerts[Self.identifier(.maghrib, .before, dayOffset: 2)] != nil)
    #expect(!pending.contains { $0.identifier.contains("/sunrise/") })

    #expect(
      Set(report.confirmed.map(\.notification))
        == Set(pending.compactMap { alerts[$0.identifier]?.id }))
    #expect(report.failures.isEmpty)
    #expect(!report.superseded)
    let covered = try #require(report.confirmedCoveredUntil)
    #expect(covered > now)
  }

  /// The English content: the prayer's name as the title; the at-time body with Salah's
  /// clock text; the reminders' bodies with their offsets; Salah's interruption levels,
  /// relevance and `userInfo`; and a notification sound only for the system sound.
  @Test func buildsSalahsContentInEnglish() async throws {
    let harness = Harness(
      now: Fixture.date(13, 0),
      settings: [
        .dhuhr: .alert(sound: .system),
        .maghrib: .alert(before: 10, beforeSound: .system, after: 5, afterSound: .system),
        .isha: .alert(sound: .none),
      ])
    await harness.update()
    let center = harness.center
    let text = SalahText(locale: Locale(identifier: "en"), timeZone: Fixture.timeZone)

    let atTime = try #require(center.pendingRequest(Self.identifier(.asr, .atTime))).content
    #expect(atTime.title == "Asr")
    #expect(atTime.body == "It's time for Asr (\(text.time(Self.asr.time)))")
    #expect(text.time(Self.asr.time).contains("3:35"))
    #expect(atTime.interruptionLevel == .timeSensitive)
    #expect(atTime.relevanceScore == 1.0)
    #expect(atTime.userInfo["prayer"] as? String == "asr")
    #expect(atTime.userInfo["kind"] as? String == "prayerTime")
    #expect(atTime.userInfo["offsetMinutes"] as? Int == 0)
    // Asr's Alafasy adhan is played by the app, not by the notification.
    #expect(atTime.sound == nil)

    let before = try #require(center.pendingRequest(Self.identifier(.maghrib, .before))).content
    #expect(before.title == "Maghrib")
    #expect(before.body == "Pre-reminder for Maghrib (\u{2068}10\u{2069} min before).")
    #expect(before.interruptionLevel == .timeSensitive)
    #expect(before.relevanceScore == 0.7)
    #expect(before.userInfo["kind"] as? String == "preReminder")
    #expect(before.userInfo["offsetMinutes"] as? Int == 10)
    #expect(before.sound == .default)

    let after = try #require(center.pendingRequest(Self.identifier(.maghrib, .after))).content
    #expect(after.title == "Maghrib")
    #expect(after.body == "Post-reminder for Maghrib (\u{2068}5\u{2069} min after).")
    #expect(after.interruptionLevel == .active)
    #expect(after.relevanceScore == 0.5)
    #expect(after.userInfo["prayer"] as? String == "maghrib")
    #expect(after.userInfo["kind"] as? String == "postReminder")
    #expect(after.userInfo["offsetMinutes"] as? Int == 5)
    #expect(after.sound == .default)

    let system = try #require(center.pendingRequest(Self.identifier(.dhuhr, .atTime, dayOffset: 1)))
    #expect(system.content.sound == .default)
    let silent = try #require(center.pendingRequest(Self.identifier(.isha, .atTime)))
    #expect(silent.content.sound == nil)
  }

  /// The content follows the app's language: Arabic, with its own digits, and French.
  /// Foundation's formatting in a right-to-left locale isolates each argument once more,
  /// so the Arabic bodies are compared without their isolates, and the digits' isolation
  /// is checked on its own.
  @Test func buildsTheContentInTheAppsLanguage() async throws {
    let settings: [PrayerKind: PrayerNotificationConfig] = [.maghrib: .alert(before: 10)]
    let arabic = Harness(now: Fixture.date(13, 0), settings: settings, language: .arabic)
    await arabic.update()
    let arabicText = SalahText(locale: AppLanguage.arabic.locale, timeZone: Fixture.timeZone)
    let arabicAsr = try #require(arabic.center.pendingRequest(Self.identifier(.asr, .atTime)))
    #expect(arabicAsr.content.title == "العصر")
    #expect(
      Self.withoutIsolates(arabicAsr.content.body)
        == "حان وقت العصر (\(Self.withoutIsolates(arabicText.time(Self.asr.time))))")
    #expect(arabicAsr.content.body.contains(arabicText.time(Self.asr.time)))
    #expect(arabicText.time(Self.asr.time).contains("٣:٣٥"))
    let arabicBefore = try #require(
      arabic.center.pendingRequest(Self.identifier(.maghrib, .before)))
    #expect(arabicBefore.content.title == "المغرب")
    #expect(Self.withoutIsolates(arabicBefore.content.body) == "تذكير قبل المغرب بـ١٠ دقيقة.")
    #expect(arabicBefore.content.body.contains("\u{2068}١٠\u{2069}"))

    let french = Harness(now: Fixture.date(13, 0), settings: settings, language: .french)
    await french.update()
    let frenchText = SalahText(locale: Locale(identifier: "fr"), timeZone: Fixture.timeZone)
    let frenchAsr = try #require(french.center.pendingRequest(Self.identifier(.asr, .atTime)))
    #expect(frenchAsr.content.body == "C'est l'heure de Asr (\(frenchText.time(Self.asr.time)))")
    let frenchBefore = try #require(
      french.center.pendingRequest(Self.identifier(.maghrib, .before)))
    #expect(frenchBefore.content.body == "Rappel avant Maghrib (\u{2068}10\u{2069} min avant).")
  }

  // MARK: - Silent mode

  /// Silent mode keeps every alert, drops every sound from the plan and the requests, and
  /// plays nothing when an alert comes due; the same settings without it do play.
  @Test func silentModeKeepsTheAlertsAndDropsTheirSounds() async throws {
    let settings: [PrayerKind: PrayerNotificationConfig] = [
      .asr: .alert(sound: .makkah),
      .maghrib: .alert(before: 10, beforeSound: .system, after: 5, afterSound: .makkah),
    ]
    let silent = Harness(
      now: Fixture.date(15, 0), settings: settings, prepare: { $0.silentMode = true })
    let loud = Harness(now: Fixture.date(15, 0), settings: settings)
    await silent.update()
    await loud.update()

    let silentAlerts = try #require(silent.coordinator.alertSchedule).alerts
    let loudAlerts = try #require(loud.coordinator.alertSchedule).alerts
    #expect(!silentAlerts.isEmpty)
    #expect(silentAlerts.map(\.occurrenceID) == loudAlerts.map(\.occurrenceID))
    #expect(silentAlerts.allSatisfy { $0.sound == AlertSound.none })
    #expect(silent.pendingIdentifiers == loud.pendingIdentifiers)
    #expect(silent.center.pending.allSatisfy { $0.content.sound == nil })
    #expect(loud.center.pending.contains { $0.content.sound == .default })

    // Asr comes due with its request gone, so the coordinator posts it itself.
    for harness in [silent, loud] {
      harness.center.dropPending(Self.identifier(.asr, .atTime))
      await harness.fire()
    }
    #expect(silent.audio.plays.isEmpty)
    #expect(silent.center.posted.map(\.identifier) == [Self.identifier(.asr, .atTime)])
    #expect(silent.center.posted.allSatisfy { $0.content.sound == nil })
    #expect(loud.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  // MARK: - Jumu'ah

  /// With the Jumu'ah override on, Fridays' Dhuhr takes the Jumu'ah settings (a 20-minute
  /// before-reminder) and the Jumu'ah name; other days' Dhuhr keeps its own settings. The
  /// Friday reminder, past the near-term window, is posted when it comes due.
  @Test func fridaysDhuhrTakesTheJumuahSettingsWhileTheOverrideIsOn() async throws {
    let friday = Fixture.event(.dhuhr, dayOffset: 3)
    #expect(friday.observance == .jumuah)
    #expect(Fixture.event(.dhuhr, dayOffset: 2).observance == .ordinary)

    let harness = Harness(
      now: Fixture.date(13, 0),
      prepare: {
        $0.jumuahOverrideEnabled = true
        $0.setJumuahConfig(.alert(before: 20))
      })
    await harness.update()
    let schedule = try #require(harness.coordinator.alertSchedule)
    let reminders = schedule.alerts.filter { $0.id.prayer == .dhuhr && $0.kind == .before }
    // Fridays only: this one and the next, inside the two-week horizon.
    #expect(reminders.map(\.id.scheduleDay) == [3, 10].map { Fixture.civilDay(offset: $0) })
    #expect(reminders.first?.fireDate == friday.time.adding(minutes: -20))

    let fridayAdhan = try #require(
      harness.center.pendingRequest(Self.identifier(.dhuhr, .atTime, dayOffset: 3)))
    #expect(fridayAdhan.content.title == "Jumuah")
    let thursday = try #require(
      harness.center.pendingRequest(Self.identifier(.dhuhr, .atTime, dayOffset: 2)))
    #expect(thursday.content.title == "Dhuhr")

    harness.clock.now = friday.time.adding(minutes: -20, seconds: 1)
    harness.coordinator.resync()
    await harness.settle()
    let posted = try #require(harness.center.posted.first)
    #expect(posted.identifier == Self.identifier(.dhuhr, .before, dayOffset: 3))
    #expect(posted.content.title == "Jumuah")
    #expect(posted.content.body == "Pre-reminder for Jumuah (\u{2068}20\u{2069} min before).")
  }

  /// With the override off, Friday's Dhuhr uses Dhuhr's own settings, even with Jumu'ah
  /// settings stored.
  @Test func fridaysDhuhrUsesDhuhrsSettingsWhileTheOverrideIsOff() async throws {
    let harness = Harness(
      now: Fixture.date(13, 0), settings: [.dhuhr: .alert(after: 5)],
      prepare: { $0.setJumuahConfig(.alert(before: 20)) })
    await harness.update()
    let schedule = try #require(harness.coordinator.alertSchedule)
    let dhuhr = schedule.alerts.filter { $0.id.prayer == .dhuhr }
    #expect(!dhuhr.contains { $0.kind == .before })
    let fridayKinds = dhuhr.filter { $0.id.scheduleDay == Fixture.civilDay(offset: 3) }.map(\.kind)
    #expect(fridayKinds == [.atTime, .after])
  }

  // MARK: - Authorization

  /// Undetermined permission with alerts to schedule: the coordinator asks once, even for
  /// two updates in a row, and then adds the requests.
  @Test func asksForPermissionOnceBeforeScheduling() async throws {
    let harness = Harness(now: Fixture.date(13, 0), status: .notDetermined)
    harness.coordinator.update(schedule: Fixture.schedule())
    harness.coordinator.update(schedule: Fixture.schedule())
    await harness.settle()

    let calls = harness.center.calls
    #expect(calls.filter { $0 == .requestAuthorization }.count == 1)
    let request = try #require(calls.firstIndex(of: .requestAuthorization))
    let firstAdd = try #require(
      calls.firstIndex {
        if case .add = $0 { return true }
        return false
      })
    #expect(request < firstAdd)
    #expect(!harness.center.pending.isEmpty)
  }

  /// A user who declines gets no requests.
  @Test func addsNothingWhenThePermissionIsDeclined() async {
    let harness = Harness(
      now: Fixture.date(13, 0), status: .notDetermined, statusAfterRequest: .denied)
    await harness.update()
    #expect(harness.center.calls.filter { $0 == .requestAuthorization }.count == 1)
    #expect(harness.center.pending.isEmpty)
  }

  /// With every alert off there is nothing to schedule, so the coordinator never asks.
  @Test func neverAsksWhenEveryAlertIsOff() async {
    let harness = Harness(now: Fixture.date(13, 0), othersOff: true, status: .notDetermined)
    await harness.update()
    #expect(!harness.center.calls.contains(.requestAuthorization))
    #expect(harness.center.pending.isEmpty)
    #expect(harness.coordinator.alertSchedule?.alerts.isEmpty == true)
  }

  /// Denied permission: no adds, no prompt, and Salah's own pending requests are removed;
  /// other apps' and other namespaces' requests stay.
  @Test func deniedPermissionRemovesOnlySalahsPendingRequests() async {
    let owned = Self.identifier(.isha, .atTime, dayOffset: 1)
    let foreign = [
      "com.example.other.reminder", "io.github.salah-kit.Salah.other/2026-06-02/asr/atTime",
    ]
    let harness = Harness(
      now: Fixture.date(13, 0), status: .denied,
      pending: ([owned] + foreign).map(Self.foreignRequest))
    await harness.update()

    #expect(harness.pendingIdentifiers == foreign)
    #expect(!harness.center.calls.contains(.requestAuthorization))
    #expect(
      !harness.center.calls.contains { if case .add = $0 { return true } else { return false } })
    #expect(harness.center.calls.contains(.removePending([owned])))
  }

  /// Authorized: an obsolete Salah request is replaced, other apps' requests are never
  /// removed.
  @Test func replanningNeverRemovesOtherAppsRequests() async {
    let obsolete = "io.github.salah-kit.Salah.prayers/2026-05-30/isha/atTime"
    let foreign = [
      "com.example.other.reminder", "io.github.salah-kit.Salah.other/2026-06-02/asr/atTime",
    ]
    let harness = Harness(
      now: Fixture.date(13, 0), pending: ([obsolete] + foreign).map(Self.foreignRequest))
    await harness.update()

    let identifiers = harness.pendingIdentifiers
    #expect(!identifiers.contains(obsolete))
    #expect(Array(identifiers.prefix(2)) == foreign)
    #expect(identifiers.contains(Self.identifier(.asr, .atTime)))
    let removed = harness.center.calls.compactMap { call -> [String]? in
      if case .removePending(let identifiers) = call { return identifiers }
      return nil
    }
    #expect(removed == [[obsolete]])
  }

  // MARK: - Due alerts

  /// At a fire time the coordinator posts a due alert whose request isn't pending, and
  /// skips one the system still holds. It plays each alert's own sound: the before-
  /// reminder's without a du'a, the adhan's with the du'a after it.
  @Test func postsWhatTheSystemWontDeliverAndPlaysTheAlertsSound() async throws {
    let harness = Harness(
      now: Fixture.date(13, 0),
      settings: [.asr: .alert(sound: .makkah, before: 10, beforeSound: .alafasy)])
    await harness.update()
    let beforeID = Self.identifier(.asr, .before)
    let atTimeID = Self.identifier(.asr, .atTime)
    #expect(harness.pendingIdentifiers.contains(beforeID))
    harness.center.dropPending(beforeID)

    await harness.fire()
    #expect(Self.isNear(harness.clock.now, Self.asr.time.adding(minutes: -10, seconds: 0.15)))
    let posted = try #require(harness.center.posted.first)
    #expect(harness.center.posted.count == 1)
    #expect(posted.identifier == beforeID)
    #expect(posted.trigger == nil)
    #expect(posted.content.threadIdentifier == "salah-prayers")
    #expect(posted.content.title == "Asr")
    #expect(posted.content.body == "Pre-reminder for Asr (\u{2068}10\u{2069} min before).")

    let reminder = try #require(harness.audio.plays.first)
    #expect(reminder.request.resource.url == Self.alafasy)
    #expect(reminder.request.volume == 0.5)
    #expect(
      reminder.request.context
        == AudioPlaybackContext(
          source: .prayerAlert, slot: .preReminder, event: Self.asr, prayerAlertOffsetMinutes: 10))
    #expect(reminder.followUp == nil)

    await harness.fire()
    #expect(Self.isNear(harness.clock.now, Self.asr.time.adding(seconds: 0.15)))
    // The at-time request is still pending: the system delivers it, not the coordinator.
    #expect(harness.center.posted.map(\.identifier) == [beforeID])
    #expect(harness.pendingIdentifiers.contains(atTimeID))
    #expect(harness.audio.plays.count == 2)
    let adhan = try #require(harness.audio.plays.last)
    #expect(adhan.request.resource.url == Self.makkah)
    #expect(
      adhan.request.context
        == AudioPlaybackContext(source: .prayerAlert, slot: .alert, event: Self.asr))
    let dua = try #require(adhan.followUp)
    #expect(dua.resource.url?.lastPathComponent == "Dua.m4a")
    #expect(dua.context == AudioPlaybackContext(source: .dua, slot: .alert, event: Self.asr))
  }

  /// An alert that comes due as a fresh plan lands, inside the engine's early leeway, is
  /// installed and not posted as well: the posting waits for the installation, which
  /// leaves the request pending.
  ///
  /// Regression: the posting ran first, found nothing pending and posted the alert, then
  /// the installation added its request too, so the banner showed twice.
  @Test func anAlertDueAsThePlanLandsIsNotPostedTwice() async throws {
    let harness = Harness(
      now: Self.asr.time.addingTimeInterval(-1), settings: [.asr: .alert(sound: .makkah)],
      othersOff: true)
    await harness.update()
    #expect(harness.pendingIdentifiers.contains(Self.identifier(.asr, .atTime)))
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// A test launch's detached center (`-salah.debug.withoutSystemNotifications`) takes
  /// nothing and reports notifications denied: the plan confirms nothing, nothing is
  /// pending, and the alert still comes due and plays in the app.
  @Test func theDetachedCenterKeepsAlertsInTheApp() async throws {
    let scratch = ScratchDefaults()
    let preferences = Preferences.scratch(scratch, settings: [.asr: .alert(sound: .makkah)])
    let clock = ManualAlertClock(Fixture.date(15, 0))
    let audio = RecordingAudioPlayer()
    let center = DetachedNotificationCenter()
    let coordinator = PrayerAlertCoordinator(
      preferences: preferences, center: center, audio: audio, clock: clock)
    coordinator.update(schedule: Fixture.schedule())
    let report = try #require(await coordinator.installation?.value)
    #expect(report.confirmed.isEmpty)
    #expect(try await center.pendingNotificationRequests().isEmpty)
    #expect(center.delegate === coordinator)

    clock.fire()
    await coordinator.delivery?.value
    #expect(audio.plays.first?.request.resource.url == Self.makkah)
    #expect(await center.deliveredNotificationRecords().isEmpty)
  }

  /// The launch option picks the detached center, and only the option does.
  @Test func theLaunchOptionPicksTheDetachedCenter() {
    let scratch = ScratchDefaults()
    #expect(DebugOptions.notificationCenter(defaults: scratch.defaults) == nil)
    scratch.defaults.set(true, forKey: DebugOptions.withoutSystemNotificationsKey)
    #expect(
      DebugOptions.notificationCenter(defaults: scratch.defaults) is DetachedNotificationCenter)
  }

  /// With the du'a off, an adhan plays alone.
  @Test func playsNoDuaWhenItIsOff() async throws {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)],
      prepare: { $0.duaEnabled = false })
    await harness.update()
    await harness.fire()
    let adhan = try #require(harness.audio.plays.first)
    #expect(adhan.request.resource.url == Self.makkah)
    #expect(adhan.followUp == nil)
  }

  /// Among alerts due together the latest fire date wins: after a sleep that covers
  /// Maghrib's adhan and its 2-minute after-reminder, only the reminder's sound plays, with
  /// no du'a.
  @Test func playsTheLatestOfAlertsDueTogether() async throws {
    let harness = Harness(
      now: Fixture.date(18, 0),
      settings: [.maghrib: .alert(sound: .alafasy, after: 2, afterSound: .makkah)])
    await harness.update()
    harness.clock.now = Self.maghrib.time.adding(minutes: 3)
    harness.coordinator.resync()
    await harness.settle()

    #expect(harness.audio.plays.count == 1)
    let play = try #require(harness.audio.plays.first)
    #expect(play.request.resource.url == Self.makkah)
    #expect(play.request.context.slot == .postReminder)
    #expect(play.request.context.prayerAlertOffsetMinutes == 2)
    #expect(play.followUp == nil)
  }

  /// At one instant an at-time alert beats a before-reminder: Isha's 90-minute reminder
  /// fires with Maghrib's adhan, and the adhan plays, with its du'a.
  @Test func atTimeAdhanBeatsABeforeReminderAtTheSameInstant() async throws {
    let isha = Fixture.event(.isha)
    try #require(isha.time.adding(minutes: -90) == Self.maghrib.time)
    let harness = Harness(
      now: Fixture.date(18, 0),
      settings: [
        .maghrib: .alert(sound: .alafasy),
        .isha: .alert(sound: .alafasy, before: 90, beforeSound: .makkah),
      ])
    await harness.update()
    harness.center.dropPending(Self.identifier(.isha, .before))
    await harness.fire()

    // Both came due together: the reminder, not pending, is posted.
    #expect(harness.center.posted.map(\.identifier) == [Self.identifier(.isha, .before)])
    #expect(harness.audio.plays.count == 1)
    let play = try #require(harness.audio.plays.first)
    #expect(play.request.resource.url == Self.alafasy)
    #expect(
      play.request.context
        == AudioPlaybackContext(source: .prayerAlert, slot: .alert, event: Self.maghrib))
    #expect(play.followUp != nil)
  }

  /// The system's sound and no sound are never played by the app.
  @Test func playsNothingForTheSystemSoundOrNoSound() async {
    let harness = Harness(
      now: Fixture.date(15, 0),
      settings: [.asr: .alert(sound: .system), .maghrib: .alert(sound: .none)], othersOff: true)
    await harness.update()
    await harness.fire()
    #expect(Self.isNear(harness.clock.now, Self.asr.time.adding(seconds: 0.15)))
    await harness.fire()
    #expect(Self.isNear(harness.clock.now, Self.maghrib.time.adding(seconds: 0.15)))
    #expect(harness.audio.plays.isEmpty)
  }

  /// An occurrence already handled isn't played again by a resync or a replan.
  @Test func playsAnOccurrenceOnce() async {
    let harness = Harness(now: Fixture.date(15, 0))
    await harness.update()
    await harness.fire()
    #expect(harness.audio.plays.count == 1)
    harness.coordinator.resync()
    await harness.settle()
    await harness.update()
    #expect(harness.audio.plays.count == 1)
    #expect(harness.center.posted.isEmpty)
  }

  // MARK: - Sleep, wake and clock changes

  /// Plain data, because Swift Testing builds arguments outside the main actor.
  nonisolated struct WakeCase: Sendable, CustomTestStringConvertible {
    var name: String
    var kind: AlertKind
    /// The reminder's offset in minutes; ignored for the at-time alert.
    var offset: Int = 0
    /// Seconds after the fire date that the Mac wakes.
    var lateness: Double
    var played: Bool

    var testDescription: String { name }
  }

  /// After a wake (or a clock change), the app's `catchUp(schedule:)` catches up an
  /// alert within its grace, once: five minutes for an at-time alert, two for a reminder,
  /// and a before-reminder never once its prayer has begun. Only Asr's alert under test
  /// is on. The system hasn't delivered the overdue request yet: the replan removes it,
  /// and the coordinator posts the alert it catches up, once.
  ///
  /// Regression: the app caught up (`resync()`) before it replanned, so the posting
  /// skipped the alert as still pending, then the replan removed the request, and no
  /// banner showed at all.
  @Test(arguments: [
    WakeCase(name: "adhan 3 min late", kind: .atTime, lateness: 180, played: true),
    WakeCase(name: "adhan 5 min late", kind: .atTime, lateness: 300, played: true),
    WakeCase(name: "adhan 6 min late", kind: .atTime, lateness: 360, played: false),
    WakeCase(
      name: "after-reminder 2 min late", kind: .after, offset: 5, lateness: 120, played: true),
    WakeCase(
      name: "after-reminder 3 min late", kind: .after, offset: 5, lateness: 180, played: false),
    WakeCase(
      name: "before-reminder 59 s late, prayer not begun", kind: .before, offset: 1, lateness: 59,
      played: true),
    WakeCase(
      name: "before-reminder 90 s late, prayer begun", kind: .before, offset: 1, lateness: 90,
      played: false),
  ])
  func catchesUpAfterAWake(_ testCase: WakeCase) async {
    let config: PrayerNotificationConfig
    let fireDate: Date
    switch testCase.kind {
    case .atTime:
      config = .alert(sound: .makkah)
      fireDate = Self.asr.time
    case .before:
      config = .alert(false, before: testCase.offset, beforeSound: .makkah)
      fireDate = Self.asr.time.adding(minutes: Double(-testCase.offset))
    case .after:
      config = .alert(false, after: testCase.offset, afterSound: .makkah)
      fireDate = Self.asr.time.adding(minutes: Double(testCase.offset))
    }
    let harness = Harness(now: Fixture.date(15, 0), settings: [.asr: config], othersOff: true)
    await harness.update()
    #expect(harness.coordinator.alertSchedule?.alerts.first?.fireDate == fireDate)

    let identifier = Self.identifier(.asr, testCase.kind)
    #expect(harness.pendingIdentifiers.contains(identifier))

    await harness.wake(at: fireDate.adding(seconds: testCase.lateness))
    #expect(harness.audio.plays.count == (testCase.played ? 1 : 0))
    #expect(harness.center.posted.map(\.identifier) == (testCase.played ? [identifier] : []))
    #expect(!harness.pendingIdentifiers.contains(identifier))
    // A second wake at once plays and posts nothing more.
    await harness.wake(at: fireDate.adding(seconds: testCase.lateness + 1))
    #expect(harness.audio.plays.count == (testCase.played ? 1 : 0))
    #expect(harness.center.posted.count == (testCase.played ? 1 : 0))
  }

  /// The engine's wake-up waits on a clock that counts time asleep, so at the end of a
  /// sleep it can report an overdue alert before the app sees the wake notification. The
  /// alert still gets one banner and one adhan when that report comes before the wake's
  /// `catchUp(schedule:)`, and its request is gone. (`catchesUpAfterAWake` covers the
  /// wake coming first.)
  ///
  /// Regression: the posting waited only for the installation from before the sleep, found
  /// the request still pending and skipped it, and the wake's replan then removed the
  /// request, whose time had passed. The adhan played, but no banner showed.
  @Test(arguments: [120.0, 1.5])
  func aWakeUpBeforeTheWakeNotificationStillPostsTheBanner(lateness: Double) async {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)
    #expect(harness.pendingIdentifiers.contains(identifier))

    harness.clock.now = Self.asr.time.adding(seconds: lateness)
    harness.clock.fireLate()
    // Let the posting's task start before the wake arrives, as it does on a real Mac.
    for _ in 0..<10 { await Task.yield() }
    await harness.wake(at: harness.clock.now)
    await harness.settle()

    #expect(harness.center.posted.map(\.identifier) == [identifier])
    #expect(!harness.pendingIdentifiers.contains(identifier))
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// A late report with no wake after it, as the minute timer's `resync()` makes after the
  /// alert's timer was held up, replans and posts the banner itself.
  @Test func aLateReportWithoutAWakePostsTheBanner() async {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)

    harness.clock.now = Self.asr.time.adding(seconds: 120)
    harness.coordinator.resync()
    await harness.settle()

    #expect(harness.center.posted.map(\.identifier) == [identifier])
    #expect(!harness.pendingIdentifiers.contains(identifier))
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// A report within `onTimeReportDelay` of the fire date is on time: no replan, and the
  /// request stays pending for the system to deliver, so the app posts nothing.
  @Test func anOnTimeReportLeavesTheRequestToTheSystem() async {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)

    harness.clock.now = Self.asr.time.adding(seconds: 0.9)
    harness.clock.fireLate()
    await harness.settle()

    #expect(harness.center.posted.isEmpty)
    #expect(harness.pendingIdentifiers.contains(identifier))
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// A clock set back past an alert that already fired doesn't request it again, so the
  /// system doesn't deliver it twice; the next day's alert stays planned.
  ///
  /// Regression: the plan came from the schedule alone, so the fired alert, in the future
  /// again, was requested anew.
  @Test func aClockSetBackDoesntRequestAFiredAlertAgain() async {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true)
    await harness.update()
    let today = Self.identifier(.asr, .atTime)
    await harness.fire()
    #expect(harness.audio.plays.count == 1)
    // The system delivered it.
    harness.center.dropPending(today)

    await harness.wake(at: Self.asr.time.adding(minutes: -20))
    #expect(!harness.pendingIdentifiers.contains(today))
    #expect(harness.pendingIdentifiers.contains(Self.identifier(.asr, .atTime, dayOffset: 1)))
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.count == 1)
  }

  // MARK: - Reminders beyond the plan

  /// With every kind on for every prayer, the plan leaves out reminders beyond its two-day
  /// window; the engine still reports one when it comes due, and the coordinator posts it
  /// and plays its sound.
  @Test func remindersThePlanLeavesOutStillComeDue() async throws {
    let everything = PrayerNotificationConfig.alert(
      sound: .alafasy, before: 10, beforeSound: .makkah, after: 5, afterSound: .system)
    let settings = Dictionary(uniqueKeysWithValues: PrayerKind.allCases.map { ($0, everything) })
    let harness = Harness(now: Fixture.date(13, 0), settings: settings)
    let report = try #require(await harness.update())

    let reminder = try #require(
      harness.coordinator.alertSchedule?.alerts.first {
        $0.id.requestIdentifier(prefix: PrayerAlertCoordinator.identifierPrefix)
          == Self.identifier(.asr, .before, dayOffset: 3)
      })
    #expect(harness.center.pending.count == 60)
    #expect(!harness.pendingIdentifiers.contains(Self.identifier(.asr, .before, dayOffset: 3)))
    #expect(!report.confirmed.contains(reminder.occurrenceID))

    harness.clock.now = reminder.fireDate.adding(seconds: 1)
    harness.coordinator.resync()
    await harness.settle()
    let posted = try #require(harness.center.posted.first)
    #expect(harness.center.posted.count == 1)
    #expect(posted.identifier == Self.identifier(.asr, .before, dayOffset: 3))
    #expect(posted.trigger == nil)
    let play = try #require(harness.audio.plays.first)
    #expect(harness.audio.plays.count == 1)
    #expect(play.request.resource.url == Self.makkah)
    #expect(play.request.context.slot == .preReminder)
    #expect(play.request.context.event == Fixture.event(.asr, dayOffset: 3))
  }

  // MARK: - Changed times

  /// When Isha's time changes, its request keeps its identifier with the new trigger: it's
  /// added again, replacing the old one, without being removed first.
  @Test func changedTimesKeepTheirIdentifiers() async throws {
    let harness = Harness(now: Fixture.date(13, 0))
    await harness.update()
    let isha = Self.identifier(.isha, .atTime)
    let identifiers = harness.pendingIdentifiers
    let old = try #require(harness.center.pendingRequest(isha))
    #expect(Self.fireDate(of: old) == Fixture.time(.isha))

    harness.center.forgetCalls()
    await harness.update(Fixture.schedule(ishaAdjustment: 5))
    let new = try #require(harness.center.pendingRequest(isha))
    #expect(Self.fireDate(of: new) == Fixture.time(.isha).adding(minutes: 5))
    #expect(Set(harness.pendingIdentifiers) == Set(identifiers))
    let calls = harness.center.calls
    #expect(calls.contains(.add(isha)))
    #expect(
      !calls.contains {
        if case .removePending(let removed) = $0 { return removed.contains(isha) }
        return false
      })
    // Asr didn't change, so its request wasn't touched.
    #expect(!calls.contains(.add(Self.identifier(.asr, .atTime))))
  }

  // MARK: - The delegate

  /// The coordinator makes itself the delegate of the center it holds.
  @Test func becomesTheCentersDelegate() {
    let harness = Harness(now: Fixture.date(13, 0))
    #expect(harness.center.delegate === harness.coordinator)
  }

  /// Only Salah's prayer alerts count as its own: a tap on another notification is
  /// ignored. (`UNNotification` and `UNNotificationResponse` can't be built in a test,
  /// so the delegate methods themselves aren't driven here.)
  @Test func recognizesOnlyItsOwnPrayerAlerts() {
    #expect(PrayerAlertCoordinator.isPrayerAlert(Self.identifier(.asr, .atTime)))
    #expect(PrayerAlertCoordinator.isPrayerAlert(Self.identifier(.fajr, .after, dayOffset: 5)))
    #expect(
      !PrayerAlertCoordinator.isPrayerAlert("io.github.salah-kit.Salah.other/2026-06-02/asr/atTime")
    )
    #expect(!PrayerAlertCoordinator.isPrayerAlert("com.example.prayers/2026-06-02/asr/atTime"))
    #expect(
      !PrayerAlertCoordinator.isPrayerAlert("io.github.salah-kit.Salah.prayers/2026-06-02/asr"))
    #expect(!PrayerAlertCoordinator.isPrayerAlert("salah.prayer.asr.prayerTime.1780400100"))
    #expect(!PrayerAlertCoordinator.isPrayerAlert(""))
  }

  // MARK: - The fake center

  /// The fake holds its delegate weakly, as the real center does.
  @Test func fakeCenterHoldsItsDelegateWeakly() {
    let center = FakeNotificationCenter()
    var delegate: DelegateProbe? = DelegateProbe()
    center.delegate = delegate
    #expect(center.delegate != nil)
    delegate = nil
    #expect(center.delegate == nil)
  }

  /// Adding a request whose identifier is pending replaces it; a request without a
  /// trigger is delivered at once, dated at the shared instant, and never pending.
  @Test func fakeCenterReplacesAndDeliversAsTheRealOneDoes() async throws {
    let time = TestInstant(Fixture.date(13, 0))
    let center = FakeNotificationCenter(time: time)
    let first = UNMutableNotificationContent()
    first.title = "first"
    let second = UNMutableNotificationContent()
    second.title = "second"
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
    try await center.add(UNNotificationRequest(identifier: "a", content: first, trigger: trigger))
    try await center.add(UNNotificationRequest(identifier: "a", content: second, trigger: trigger))
    #expect(center.pending.map(\.content.title) == ["second"])

    try await center.add(UNNotificationRequest(identifier: "b", content: first, trigger: nil))
    #expect(center.pending.map(\.identifier) == ["a"])
    #expect(center.posted.map(\.identifier) == ["b"])
    #expect(center.delivered == [DeliveredNotificationRecord(identifier: "b", date: time.value)])
  }

  /// A delegate that does nothing, for the fake center's weak reference.
  nonisolated final class DelegateProbe: NSObject, UNUserNotificationCenterDelegate {}
}
