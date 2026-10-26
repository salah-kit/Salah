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
      normalizePriority: Bool = false,
      rejectCalendarAdds: Bool = false,
      beforeDueDecision: (@Sendable () async -> Void)? = nil,
      prepare: (Preferences) -> Void = { _ in }
    ) {
      var resolved = settings
      if othersOff {
        for prayer in PrayerKind.allCases where resolved[prayer] == nil { resolved[prayer] = .off }
      }
      preferences = .scratch(scratch, settings: resolved)
      preferences.appLanguage = language
      // An app past its first launch's welcome, as every test but the welcome's assumes.
      preferences.onboardingCompleted = true
      prepare(preferences)
      clock = ManualAlertClock(now)
      center = FakeNotificationCenter(
        status: status, statusAfterRequest: statusAfterRequest, time: clock.instant,
        pending: pending, normalizePriority: normalizePriority,
        rejectCalendarAdds: rejectCalendarAdds)
      let instant = clock.instant
      let todayOpened = Counter()
      self.todayOpened = todayOpened
      coordinator = PrayerAlertCoordinator(
        preferences: preferences, center: center, audio: audio,
        openToday: { todayOpened.count += 1 }, clock: clock,
        schedulerNow: { instant.value }, beforeDueDecision: beforeDueDecision)
    }

    private let todayOpened: Counter
    /// How many times a tap opened Today.
    var todayOpenCount: Int { todayOpened.count }

    final class Counter {
      var count = 0
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
    var removedPendingIdentifiers: Set<String> {
      Set(
        center.calls.flatMap { call -> [String] in
          if case .removePending(let identifiers) = call { return identifiers }
          return []
        })
    }
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

  /// Text as Figma writes it: without bidi isolates, and with the clock's narrow
  /// no-break space (U+202F) as a plain space.
  static func plain(_ text: String) -> String {
    withoutIsolates(text).replacing("\u{202F}", with: " ").replacing("\u{00A0}", with: " ")
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
      #expect(request.content.threadIdentifier == "salah-prayers-\(alert.id.scheduleDay)")
      #expect(request.content.categoryIdentifier == "salah-prayer")
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

  /// Quit Salah turns everything off: Salah's pending alerts go, another app's request
  /// stays, and nothing is planned, posted or played afterwards, even when an alert comes due.
  @Test func withdrawingForQuitRemovesThePendingAlertsAndPlansNoMore() async throws {
    let foreign = Self.foreignRequest("com.example.other")
    let harness = Harness(now: Fixture.date(13, 0), pending: [foreign])
    await harness.update()
    #expect(harness.pendingIdentifiers.count > 1)
    let armed = try #require(harness.clock.armed)

    await harness.coordinator.withdraw()
    #expect(harness.pendingIdentifiers == [foreign.identifier])

    harness.center.forgetCalls()
    await harness.update()
    harness.clock.now = armed
    harness.clock.fireLate()
    await harness.settle()
    #expect(harness.pendingIdentifiers == [foreign.identifier])
    #expect(harness.center.calls.isEmpty, "Nothing reaches the center after Quit Salah")
    #expect(harness.audio.plays.isEmpty)
  }

  /// The English content, as Figma's notification stack shows it: the prayer's name as the
  /// title; the place as the subtitle; the at-time body with Salah's clock text; the
  /// reminders' bodies with their minutes and, before the prayer, its time; Salah's
  /// interruption levels (only the prayer time is time-sensitive), relevance and
  /// `userInfo`; the prayer day's thread and Salah's category; and a notification sound
  /// only for the system sound.
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
    #expect(atTime.subtitle == "Makkah")
    #expect(Self.plain(atTime.body) == "It’s time for Asr (3:35 PM).")
    #expect(
      atTime.body == "It’s time for Asr (\(text.timeFormatter().string(from: Self.asr.time))).")
    #expect(atTime.threadIdentifier == "salah-prayers-2026-06-02")
    #expect(atTime.categoryIdentifier == "salah-prayer")
    #expect(atTime.interruptionLevel == .timeSensitive)
    #expect(atTime.relevanceScore == 1.0)
    #expect(atTime.userInfo["prayer"] as? String == "asr")
    #expect(atTime.userInfo["kind"] as? String == "prayerTime")
    #expect(atTime.userInfo["offsetMinutes"] as? Int == 0)
    // Asr's Alafasy adhan is played by the app, not by the notification.
    #expect(atTime.sound == nil)

    let before = try #require(center.pendingRequest(Self.identifier(.maghrib, .before))).content
    #expect(before.title == "Maghrib")
    #expect(before.subtitle == "Makkah")
    #expect(Self.plain(before.body) == "Maghrib in 10 minutes, at 7:00 PM.")
    #expect(before.interruptionLevel == .active)
    #expect(before.threadIdentifier == "salah-prayers-2026-06-02")
    #expect(before.categoryIdentifier == "salah-prayer")
    #expect(before.relevanceScore == 0.7)
    #expect(before.userInfo["kind"] as? String == "preReminder")
    #expect(before.userInfo["offsetMinutes"] as? Int == 10)
    #expect(before.sound == .default)

    let after = try #require(center.pendingRequest(Self.identifier(.maghrib, .after))).content
    #expect(after.title == "Maghrib")
    #expect(after.subtitle == "Makkah")
    #expect(after.body == "Maghrib began 5 minutes ago.")
    #expect(after.threadIdentifier == "salah-prayers-2026-06-02")
    #expect(after.categoryIdentifier == "salah-prayer")
    #expect(after.interruptionLevel == .active)
    #expect(after.relevanceScore == 0.5)
    #expect(after.userInfo["prayer"] as? String == "maghrib")
    #expect(after.userInfo["kind"] as? String == "postReminder")
    #expect(after.userInfo["offsetMinutes"] as? Int == 5)
    #expect(after.sound == .default)

    let system = try #require(center.pendingRequest(Self.identifier(.dhuhr, .atTime, dayOffset: 1)))
    #expect(system.content.sound == .default)
    #expect(system.content.threadIdentifier == "salah-prayers-2026-06-03")
    let silent = try #require(center.pendingRequest(Self.identifier(.isha, .atTime)))
    #expect(silent.content.sound == nil)
  }

  /// The content follows the app's language: Arabic, with its own digits and plural
  /// forms, as Figma's Arabic stack shows it, and French. Foundation's formatting in a
  /// right-to-left locale isolates each argument, so the Arabic bodies are compared
  /// without their isolates, and the isolation is checked on its own.
  @Test func buildsTheContentInTheAppsLanguage() async throws {
    let settings: [PrayerKind: PrayerNotificationConfig] = [
      .maghrib: .alert(before: 10, after: 5), .isha: .alert(before: 1, after: 2),
      .asr: .alert(before: 11),
    ]
    let arabic = Harness(now: Fixture.date(13, 0), settings: settings, language: .arabic)
    await arabic.update()
    func arabicBody(_ prayer: PrayerKind, _ kind: AlertKind) throws -> String {
      let request = try #require(arabic.center.pendingRequest(Self.identifier(prayer, kind)))
      return Self.plain(request.content.body)
    }
    let arabicAsr = try #require(arabic.center.pendingRequest(Self.identifier(.asr, .atTime)))
    #expect(arabicAsr.content.title == "العصر")
    // The default place is named in the app's language.
    #expect(arabicAsr.content.subtitle == "مكة المكرمة")
    #expect(try arabicBody(.asr, .atTime) == "حان وقت العصر (٣:٣٥ م).")
    #expect(arabicAsr.content.body.contains("\u{2068}العصر\u{2069}"))
    #expect(arabicAsr.content.threadIdentifier == "salah-prayers-2026-06-02")
    #expect(try arabicBody(.maghrib, .atTime) == "حان وقت المغرب (٧:٠٠ م).")
    let arabicBefore = try #require(
      arabic.center.pendingRequest(Self.identifier(.maghrib, .before)))
    #expect(arabicBefore.content.title == "المغرب")
    #expect(try arabicBody(.maghrib, .before) == "المغرب بعد ١٠ دقائق، الساعة ٧:٠٠ م.")
    #expect(try arabicBody(.maghrib, .after) == "دخل وقت المغرب منذ ٥ دقائق.")
    // Arabic's other plural forms: one, two and many.
    #expect(try arabicBody(.isha, .before) == "العشاء بعد دقيقة، الساعة ٨:٣٠ م.")
    #expect(try arabicBody(.isha, .after) == "دخل وقت العشاء منذ دقيقتين.")
    #expect(try arabicBody(.asr, .before) == "العصر بعد ١١ دقيقة، الساعة ٣:٣٥ م.")

    let english = Harness(now: Fixture.date(13, 0), settings: settings)
    await english.update()
    let englishOne = try #require(english.center.pendingRequest(Self.identifier(.isha, .before)))
    #expect(Self.plain(englishOne.content.body) == "Isha in 1 minute, at 8:30 PM.")
    let englishTwo = try #require(english.center.pendingRequest(Self.identifier(.isha, .after)))
    #expect(englishTwo.content.body == "Isha began 2 minutes ago.")

    let french = Harness(now: Fixture.date(13, 0), settings: settings, language: .french)
    await french.update()
    let frenchText = SalahText(locale: Locale(identifier: "fr"), timeZone: Fixture.timeZone)
    let frenchAsr = try #require(french.center.pendingRequest(Self.identifier(.asr, .atTime)))
    #expect(
      frenchAsr.content.body
        == "C’est l’heure : Asr (\(frenchText.timeFormatter().string(from: Self.asr.time))).")
    let frenchBefore = try #require(
      french.center.pendingRequest(Self.identifier(.maghrib, .before)))
    #expect(
      frenchBefore.content.body
        == "Maghrib dans 10 minutes, à \(frenchText.timeFormatter().string(from: Self.maghrib.time))."
    )
    let frenchOne = try #require(french.center.pendingRequest(Self.identifier(.isha, .before)))
    #expect(frenchOne.content.body.hasPrefix("Isha dans 1 minute, à "))
  }

  // MARK: - Threads, category and convergence

  /// Each prayer day has its own thread, named by the day the prayer belongs to in the
  /// location's time zone. Around midnight a prayer's alerts stay together: an Isha after
  /// midnight and its reminders join the day the Isha belongs to, and a Fajr reminder
  /// before midnight joins Fajr's day.
  @Test func eachPrayerDaysAlertsShareOneThreadAcrossMidnight() throws {
    let scratch = ScratchDefaults()
    let content = PrayerAlertContent(preferences: .scratch(scratch, settings: [:]))
    let tuesday = Fixture.civilDay()
    let wednesday = Fixture.civilDay(offset: 1)
    func alert(
      _ prayer: PrayerKind, _ kind: AlertKind, day: CivilDay, at time: Date, offset: Int = 0
    ) -> PlannedAlert {
      let event = PrayerEvent(scheduleDay: day, kind: prayer, time: time)
      return PlannedAlert(
        id: NotificationIdentity(
          namespace: "prayers", scheduleDay: day, prayer: prayer, kind: kind),
        event: event, fireDate: time.adding(minutes: Double(offset)), sound: .none)
    }
    // Tuesday's Isha at 00:15 on Wednesday, with reminders at 00:05 and 00:20.
    let isha = Fixture.date(0, 15, dayOffset: 1)
    for (kind, offset) in [(AlertKind.before, -10), (.atTime, 0), (.after, 5)] {
      let made = content.make(alert(.isha, kind, day: tuesday, at: isha, offset: offset))
      #expect(made.threadIdentifier == "salah-prayers-2026-06-02", "\(kind)")
    }
    // Wednesday's Fajr at 00:05, with its reminder at 23:50 on Tuesday.
    let fajr = Fixture.date(0, 5, dayOffset: 1)
    let reminder = content.make(alert(.fajr, .before, day: wednesday, at: fajr, offset: -15))
    #expect(reminder.threadIdentifier == "salah-prayers-2026-06-03")
    let adhan = content.make(alert(.fajr, .atTime, day: wednesday, at: fajr))
    #expect(adhan.threadIdentifier == "salah-prayers-2026-06-03")
  }

  /// The thread follows the location's day, not the Mac's: in New York, Tuesday's Isha
  /// falls on Wednesday in Riyadh, the tests' process time zone, and still joins
  /// Tuesday's thread. The subtitle names the place.
  @Test func theThreadFollowsTheLocationsDayNotTheMacs() async throws {
    let harness = Harness(
      now: Fixture.date(16, 0), settings: [.isha: .alert(before: 10)], othersOff: true,
      prepare: {
        $0.updateLocation(
          latitude: 40.7128, longitude: -74.0060, city: "New York", state: "NY",
          country: "US", countryName: "United States", timeZone: "America/New_York")
      })
    await harness.update(harness.preferences.mirroredSettings.schedule)
    let identifier = NotificationIdentity(
      namespace: "prayers", scheduleDay: Fixture.civilDay(), prayer: .isha, kind: .atTime
    ).requestIdentifier(prefix: PrayerAlertCoordinator.identifierPrefix)
    let request = try #require(harness.center.pendingRequest(identifier))
    let fireDate = try #require(Self.fireDate(of: request))
    #expect(CivilDay(containing: fireDate, in: Fixture.timeZone) == Fixture.civilDay(offset: 1))
    #expect(request.content.threadIdentifier == "salah-prayers-2026-06-02")
    #expect(request.content.subtitle == "New York")
    let before = try #require(
      harness.center.pendingRequest(
        identifier.replacing("/isha/atTime", with: "/isha/before")))
    #expect(before.content.threadIdentifier == "salah-prayers-2026-06-02")
  }

  /// Salah registers its one category on the center it holds: no actions, and the
  /// prayer's name stays visible when previews are hidden.
  @Test func registersSalahsCategory() throws {
    let harness = Harness(now: Fixture.date(13, 0))
    let category = try #require(harness.center.categories.first)
    #expect(harness.center.categories.count == 1)
    #expect(category.identifier == PrayerAlertCoordinator.categoryIdentifier)
    #expect(category.actions.isEmpty)
    #expect(category.intentIdentifiers.isEmpty)
    #expect(category.options == .hiddenPreviewsShowTitle)
  }

  /// Replanning unchanged settings, as every wake, tick and setting change does, leaves
  /// the requests alone: the per-day thread, the place and the category are the same
  /// each time, so nothing is removed or added again.
  @Test func replanningUnchangedSettingsChurnsNothing() async {
    let settings: [PrayerKind: PrayerNotificationConfig] = [
      .maghrib: .alert(before: 10, after: 5), .isha: .alert(before: 15),
    ]
    let harness = Harness(now: Fixture.date(13, 0), settings: settings)
    await harness.update()
    let installed = harness.pendingIdentifiers
    #expect(installed.count == 60)
    harness.center.forgetCalls()
    harness.clock.now = Fixture.date(13, 5)

    await harness.update()

    #expect(!harness.center.calls.contains { if case .add = $0 { true } else { false } })
    #expect(harness.removedPendingIdentifiers.isEmpty)
    #expect(harness.pendingIdentifiers == installed)
  }

  /// A Mac upgrading from a Salah that wrote the old content (one shared thread, no
  /// subtitle or category, the old wording, a time-sensitive before-reminder) converges
  /// in one replan: each request is replaced once, in place, and the next replan adds
  /// nothing.
  @Test func requestsFromAnEarlierVersionConvergeInOneReplan() async throws {
    let settings: [PrayerKind: PrayerNotificationConfig] = [.maghrib: .alert(before: 10, after: 5)]
    let current = Harness(now: Fixture.date(13, 0), settings: settings)
    await current.update()
    let fresh = current.center.pending
    let legacy = fresh.map { request -> UNNotificationRequest in
      let content = UNMutableNotificationContent()
      content.title = request.content.title
      content.body = "Pre-reminder for \(request.content.title) (10 min before)."
      content.threadIdentifier = "salah-prayers"
      content.userInfo = request.content.userInfo
      content.sound = request.content.sound
      content.interruptionLevel = .timeSensitive
      content.relevanceScore = request.content.relevanceScore
      return UNNotificationRequest(
        identifier: request.identifier, content: content, trigger: request.trigger)
    }

    let upgraded = Harness(now: Fixture.date(13, 0), settings: settings, pending: legacy)
    await upgraded.update()
    let adds = upgraded.center.calls.compactMap { call -> String? in
      if case .add(let identifier) = call { return identifier }
      return nil
    }
    #expect(adds.sorted() == fresh.map(\.identifier).sorted())
    #expect(upgraded.removedPendingIdentifiers.isEmpty)
    #expect(Set(upgraded.pendingIdentifiers) == Set(fresh.map(\.identifier)))
    for request in upgraded.center.pending {
      let expected = try #require(fresh.first { $0.identifier == request.identifier })
      #expect(request.content.threadIdentifier == expected.content.threadIdentifier)
      let identity = try #require(
        NotificationIdentity(
          requestIdentifier: request.identifier, prefix: PrayerAlertCoordinator.identifierPrefix))
      #expect(request.content.threadIdentifier == "salah-prayers-\(identity.scheduleDay)")
      #expect(request.content.subtitle == "Makkah")
      #expect(request.content.categoryIdentifier == "salah-prayer")
      #expect(request.content.body == expected.content.body)
      #expect(request.content.interruptionLevel == expected.content.interruptionLevel)
    }

    upgraded.center.forgetCalls()
    await upgraded.update()
    #expect(!upgraded.center.calls.contains { if case .add = $0 { true } else { false } })
    #expect(upgraded.removedPendingIdentifiers.isEmpty)
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

    // An on-time refresh leaves an accepted request to the system, including its silence.
    let identifier = Self.identifier(.asr, .atTime)
    for harness in [silent, loud] {
      harness.clock.now = Self.asr.time.adding(seconds: 0.3)
      await harness.update()
      #expect(!harness.removedPendingIdentifiers.contains(identifier))
      #expect(harness.pendingIdentifiers.contains(identifier))
    }
    #expect(silent.audio.plays.isEmpty)
    #expect(silent.center.posted.isEmpty)
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
    #expect(fridayAdhan.content.title == "Jumu’ah")
    let thursday = try #require(
      harness.center.pendingRequest(Self.identifier(.dhuhr, .atTime, dayOffset: 2)))
    #expect(thursday.content.title == "Dhuhr")

    harness.clock.now = friday.time.adding(minutes: -20, seconds: 1)
    harness.coordinator.resync()
    await harness.settle()
    let posted = try #require(harness.center.posted.first)
    #expect(posted.identifier == Self.identifier(.dhuhr, .before, dayOffset: 3))
    #expect(posted.content.title == "Jumu’ah")
    #expect(Self.plain(posted.content.body) == "Jumu’ah in 20 minutes, at 12:19 PM.")
    #expect(posted.content.threadIdentifier == "salah-prayers-2026-06-05")
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

  /// Before the first launch's welcome is over the coordinator never asks: the welcome
  /// asks on its own page.
  @Test func neverAsksBeforeTheWelcomeIsOver() async {
    let harness = Harness(
      now: Fixture.date(13, 0), status: .notDetermined, prepare: { $0.onboardingCompleted = false })
    await harness.update()
    #expect(!harness.center.calls.contains(.requestAuthorization))
  }

  /// After the welcome's Not Now the coordinator doesn't ask either; the Notifications
  /// pane asks when it's opened.
  @Test func neverAsksAfterTheWelcomesNotNow() async {
    let harness = Harness(
      now: Fixture.date(13, 0), status: .notDetermined,
      prepare: { $0.notificationPromptDeferred = true })
    await harness.update()
    #expect(!harness.center.calls.contains(.requestAuthorization))
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

  /// A reminder already due when planning starts isn't handed to the system: the app
  /// posts it, then leaves the future adhan to its native request. Each plays its own sound.
  @Test func postsWhatTheSystemWontDeliverAndPlaysTheAlertsSound() async throws {
    let harness = Harness(
      now: Self.asr.time.adding(minutes: -10, seconds: 0.15),
      settings: [.asr: .alert(sound: .makkah, before: 10, beforeSound: .alafasy)])
    await harness.update()
    let beforeID = Self.identifier(.asr, .before)
    let atTimeID = Self.identifier(.asr, .atTime)
    #expect(!harness.pendingIdentifiers.contains(beforeID))

    #expect(Self.isNear(harness.clock.now, Self.asr.time.adding(minutes: -10, seconds: 0.15)))
    let posted = try #require(harness.center.posted.first)
    #expect(harness.center.posted.count == 1)
    #expect(posted.identifier == beforeID)
    #expect(posted.trigger == nil)
    #expect(posted.content.threadIdentifier == "salah-prayers-2026-06-02")
    #expect(posted.content.categoryIdentifier == "salah-prayer")
    #expect(posted.content.title == "Asr")
    #expect(posted.content.subtitle == "Makkah")
    #expect(Self.plain(posted.content.body) == "Asr in 10 minutes, at 3:35 PM.")

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

  /// The system can consume a request before its delivered-notifications query sees it.
  /// Reposting the identifier in that interval replaces the notification in flight.
  /// Priority normalization leaves full verification unconfirmed, but not the handoff.
  @Test func anAcceptedAlertIsNotRepostedDuringSystemDelivery() async throws {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true,
      normalizePriority: true)
    let report = try #require(await harness.update())
    let identifier = Self.identifier(.asr, .atTime)
    let identity = try #require(
      NotificationIdentity(
        requestIdentifier: identifier, prefix: PrayerAlertCoordinator.identifierPrefix))
    let pending = try #require(harness.center.pendingRequest(identifier))
    #expect(report.confirmed.isEmpty)
    #expect(report.failures[identity] == .unconfirmed)
    #expect(pending.content.interruptionLevel == .active)
    #expect(pending.content.relevanceScore == 0)
    #expect(harness.pendingIdentifiers.contains(identifier))
    harness.center.dropPending(identifier)
    #expect(harness.center.delivered.isEmpty)
    harness.center.forgetCalls()

    await harness.fire()

    #expect(harness.center.posted.isEmpty)
    #expect(!harness.center.calls.contains(.add(identifier)))
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// Holds one successful add open while the native request starts delivery.
  actor ScheduledAddGate {
    private var arrival: CheckedContinuation<Void, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    func pause() async {
      await withCheckedContinuation {
        blocked = $0
        arrival?.resume()
        arrival = nil
      }
    }

    func waitUntilPaused() async {
      if blocked != nil { return }
      await withCheckedContinuation { arrival = $0 }
    }

    func release() {
      blocked?.resume()
      blocked = nil
    }
  }

  /// An accepted add can cross its deadline before either installation read-back sees it.
  /// The due handler waits for that installation without replacing the native delivery.
  @Test func anInstallationCrossingTheDeadlineKeepsItsAcceptedHandoff() async throws {
    let harness = Harness(
      now: Self.asr.time.adding(seconds: -2), settings: [.asr: .alert(sound: .makkah)],
      othersOff: true, normalizePriority: true)
    let identifier = Self.identifier(.asr, .atTime)
    let instant = harness.clock.instant
    let center = harness.center
    let due = Self.asr.time
    let gate = ScheduledAddGate()
    center.afterCalendarAdd = { added in
      guard added == identifier else { return }
      instant.value = due.addingTimeInterval(0.3)
      center.dropPending(identifier)
      await gate.pause()
    }
    defer { center.afterCalendarAdd = nil }
    let installation = Task { await harness.update() }
    await gate.waitUntilPaused()
    harness.clock.fireLate()
    await gate.release()
    let report = try #require(await installation.value)
    await harness.settle()

    #expect(report.verifiedAt == due.adding(seconds: 0.3))
    #expect(report.confirmed.isEmpty)
    #expect(!harness.pendingIdentifiers.contains(identifier))
    #expect(harness.center.delivered.isEmpty)
    #expect(harness.center.posted.isEmpty)
    #expect(harness.center.calls.filter { $0 == .add(identifier) }.count == 1)
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// A failed replacement leaves the prior native request alive, even if its priority
  /// was normalized and full content verification cannot confirm it.
  @Test func aFailedReplacementPreservesTheSurvivingNativeHandoff() async throws {
    let seed = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true,
      normalizePriority: true)
    await seed.update()
    let identifier = Self.identifier(.asr, .atTime)
    let existing = try #require(seed.center.pendingRequest(identifier))
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true,
      pending: [existing], rejectCalendarAdds: true)
    let report = try #require(await harness.update())
    #expect(report.confirmed.isEmpty)
    #expect(!report.failures.isEmpty)
    #expect(harness.pendingIdentifiers.contains(identifier))
    harness.center.dropPending(identifier)
    #expect(harness.center.delivered.isEmpty)

    await harness.fire()

    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// A failed first add has no earlier native request to protect, so it needs fallback.
  @Test func aRejectedFirstCalendarAddStillGetsImmediateDelivery() async throws {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true,
      rejectCalendarAdds: true)
    let report = try #require(await harness.update())
    let identifier = Self.identifier(.asr, .atTime)
    #expect(report.confirmed.isEmpty)
    #expect(!report.failures.isEmpty)
    #expect(harness.center.pending.isEmpty)

    await harness.fire()

    #expect(harness.center.posted.map(\.identifier) == [identifier])
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// An ordinary refresh can report the alert while native delivery is between queries.
  /// The preceding handoff remains valid for the same enabled, on-time occurrence.
  @Test func anOnTimeRefreshKeepsTheNativeDeliveryInFlight() async throws {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true,
      normalizePriority: true)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)
    harness.center.dropPending(identifier)
    #expect(harness.center.delivered.isEmpty)
    harness.center.forgetCalls()
    harness.clock.now = Self.asr.time.adding(seconds: 0.3)

    await harness.update()

    #expect(harness.center.posted.isEmpty)
    #expect(!harness.center.calls.contains(.add(identifier)))
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// An on-time refresh leaves the accepted request intact, even when the native center
  /// normalized its priority and the future-only plan no longer contains it.
  @Test func anOnTimeRefreshKeepsThePendingNativeRequest() async throws {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true,
      normalizePriority: true)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)
    #expect(harness.pendingIdentifiers.contains(identifier))
    harness.center.forgetCalls()
    harness.clock.now = Self.asr.time.adding(seconds: 0.3)

    await harness.update()

    #expect(!harness.removedPendingIdentifiers.contains(identifier))
    #expect(harness.pendingIdentifiers.contains(identifier))
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// An early report can complete before a refresh starts. If that refresh's async
  /// installation crosses the fire date, the scheduler drops the alert from its future
  /// plan, but the already reported occurrence still belongs to the native request.
  @Test(arguments: [false, true])
  func anEarlyReportKeepsItsRequestWhenARefreshCrossesTheDeadline(
    normalizePriority: Bool
  ) async throws {
    let harness = Harness(
      now: Self.asr.time.adding(seconds: -1), settings: [.asr: .alert(sound: .makkah)],
      othersOff: true, normalizePriority: normalizePriority)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)
    let original = try #require(harness.center.pendingRequest(identifier))
    let occurrence = try #require(
      harness.coordinator.alertSchedule?.alerts.first { $0.event == Self.asr }?.occurrenceID)
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
    harness.center.forgetCalls()

    harness.clock.now = Self.asr.time.adding(seconds: -0.5)
    harness.coordinator.update(schedule: Fixture.schedule())
    // No suspension before advancing: the plan is made before the deadline, while its
    // installation and scheduler batch run after it. The first due task already finished.
    harness.clock.now = Self.asr.time.adding(seconds: 0.3)
    let refreshed = try #require(await harness.settle())

    #expect(refreshed.verifiedAt == Self.asr.time.adding(seconds: 0.3))
    #expect(!refreshed.confirmed.contains(occurrence))
    #expect(harness.center.pendingRequest(identifier) === original)
    #expect(
      !harness.center.calls.contains {
        if case .removePending(let identifiers) = $0 { return identifiers.contains(identifier) }
        return false
      })
    #expect(!harness.center.calls.contains(.add(identifier)))
    #expect(harness.center.delivered.isEmpty)
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// A refresh can make the first early report itself, after it queues installation.
  /// Native retention must observe that report when the queued installation starts,
  /// rather than snapshotting an empty report set before the engine update runs.
  @Test(arguments: [false, true])
  func aFirstEarlyReportKeepsItsRequestWhenARefreshCrossesTheDeadline(
    normalizePriority: Bool
  ) async throws {
    let harness = Harness(
      now: Self.asr.time.adding(seconds: -60), settings: [.asr: .alert(sound: .makkah)],
      othersOff: true, normalizePriority: normalizePriority)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)
    let original = try #require(harness.center.pendingRequest(identifier))
    #expect(harness.audio.plays.isEmpty)
    #expect(harness.center.posted.isEmpty)
    harness.center.forgetCalls()

    harness.clock.now = Self.asr.time.adding(seconds: -1)
    harness.coordinator.update(schedule: Fixture.schedule())
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
    // The engine has now reported this occurrence for the first time. Its installation
    // has not started: advancing without suspension makes that batch cross the deadline.
    harness.clock.now = Self.asr.time.adding(seconds: 0.3)
    let refreshed = try #require(await harness.settle())

    #expect(refreshed.verifiedAt == Self.asr.time.adding(seconds: 0.3))
    #expect(harness.center.pendingRequest(identifier) === original)
    #expect(
      !harness.center.calls.contains {
        if case .removePending(let identifiers) = $0 { return identifiers.contains(identifier) }
        return false
      })
    #expect(!harness.center.calls.contains(.add(identifier)))
    #expect(harness.center.delivered.isEmpty)
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// A queued installation evaluates retention at its actual start, so a completed
  /// early report does not protect a stale native request beyond the catch-up grace.
  @Test(arguments: [false, true])
  func aCompletedEarlyReportsRetentionExpiresWhileInstallationWaits(
    normalizePriority: Bool
  ) async throws {
    let harness = Harness(
      now: Self.asr.time.adding(seconds: -1), settings: [.asr: .alert(sound: .makkah)],
      othersOff: true, normalizePriority: normalizePriority)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)
    #expect(harness.pendingIdentifiers.contains(identifier))
    #expect(harness.audio.plays.count == 1)
    harness.center.forgetCalls()

    harness.clock.now = Self.asr.time.adding(seconds: -0.5)
    harness.coordinator.update(schedule: Fixture.schedule())
    harness.clock.now = Self.asr.time.adding(seconds: 301)
    let refreshed = try #require(await harness.settle())

    #expect(refreshed.verifiedAt == Self.asr.time.adding(seconds: 301))
    #expect(!harness.pendingIdentifiers.contains(identifier))
    #expect(
      harness.center.calls.contains {
        if case .removePending(let identifiers) = $0 { return identifiers.contains(identifier) }
        return false
      })
    #expect(!harness.center.calls.contains(.add(identifier)))
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
  }

  /// The due task can finish before a refresh starts. The engine then remembers the
  /// occurrence and emits no second callback, so withdrawing its native request loses it.
  /// Later unchanged refreshes retain that responsibility while it is still in catch-up.
  @Test(arguments: [false, true], [0.3, 2.0, 120.0])
  func aRefreshAfterACompletedOnTimeReportKeepsItsNativeRequest(
    normalizePriority: Bool, refreshDelay: Double
  ) async throws {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true,
      normalizePriority: normalizePriority)
    let installed = try #require(await harness.update())
    let identifier = Self.identifier(.asr, .atTime)
    let original = try #require(harness.center.pendingRequest(identifier))
    let occurrence = try #require(
      harness.coordinator.alertSchedule?.alerts.first { $0.event == Self.asr }?.occurrenceID)
    #expect(installed.confirmed.contains(occurrence) == !normalizePriority)

    harness.clock.now = Self.asr.time.adding(seconds: 0.3)
    harness.clock.fireLate()
    await harness.settle()
    #expect(harness.center.pendingRequest(identifier) === original)
    #expect(harness.center.delivered.isEmpty)
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.count == 1)
    harness.center.forgetCalls()

    for delay in [refreshDelay, refreshDelay + 0.1] {
      harness.clock.now = Self.asr.time.adding(seconds: delay)
      let refreshed = try #require(await harness.update())
      // This overdue occurrence is not part of the scheduler's future coverage report.
      #expect(!refreshed.confirmed.contains(occurrence))
      #expect(harness.center.pendingRequest(identifier) === original)
      #expect(!harness.center.calls.contains(.add(identifier)))
      #expect(!harness.removedPendingIdentifiers.contains(identifier))
      #expect(harness.center.delivered.isEmpty)
      #expect(harness.center.posted.isEmpty)
      #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
    }
  }

  /// Retention belongs to the exact enabled occurrence, not its stable identifier or a
  /// previously completed due task. A disabled or retimed alert still withdraws it.
  @Test(arguments: [QueuedRefresh.disabled, .retimed])
  func aChangedRefreshAfterACompletedReportWithdrawsItsNativeRequest(
    _ refresh: QueuedRefresh
  ) async throws {
    let harness = Harness(
      now: Fixture.date(19, 0), settings: [.isha: .alert(sound: .makkah)], othersOff: true)
    await harness.update()
    let identifier = Self.identifier(.isha, .atTime)
    harness.clock.now = Fixture.time(.isha).adding(seconds: 0.3)
    harness.clock.fireLate()
    await harness.settle()
    #expect(harness.pendingIdentifiers.contains(identifier))
    #expect(harness.audio.plays.count == 1)
    let pendingBeforeRefresh = Set(harness.pendingIdentifiers)
    harness.center.forgetCalls()

    let schedule: PrayerSchedule
    if refresh == .disabled {
      harness.preferences.setConfig(.off, for: .isha)
      schedule = Fixture.schedule()
    } else {
      schedule = Fixture.schedule(ishaAdjustment: -6)
    }
    await harness.update(schedule)

    let expectedRemoval = refresh == .disabled ? pendingBeforeRefresh : [identifier]
    #expect(harness.removedPendingIdentifiers == expectedRemoval)
    #expect(harness.removedPendingIdentifiers.contains(identifier))
    #expect(!harness.pendingIdentifiers.contains(identifier))
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.count == 1)
  }

  nonisolated enum ChangedContent: String, Sendable, CustomTestStringConvertible {
    case language, sound, silentMode, authorization

    var testDescription: String { rawValue }
  }

  /// An unchanged identity and date cannot preserve content that the current settings
  /// changed, or preserve a pending request after authorization was revoked.
  @Test(arguments: [
    ChangedContent.language, .sound, .silentMode, .authorization,
  ])
  func aCompletedReportDoesNotRetainChangedNativeContent(_ change: ChangedContent) async {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .system)], othersOff: true,
      normalizePriority: true)
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)
    harness.clock.now = Self.asr.time.adding(seconds: 0.3)
    harness.clock.fireLate()
    await harness.settle()
    #expect(harness.pendingIdentifiers.contains(identifier))
    let pendingBeforeRefresh = Set(harness.pendingIdentifiers)
    harness.center.forgetCalls()
    switch change {
    case .language: harness.preferences.appLanguage = .arabic
    case .sound: harness.preferences.setConfig(.alert(sound: .makkah), for: .asr)
    case .silentMode: harness.preferences.silentMode = true
    case .authorization: harness.center.status = .denied
    }

    await harness.update()

    let expectedRemoval = change == .authorization ? pendingBeforeRefresh : [identifier]
    #expect(harness.removedPendingIdentifiers == expectedRemoval)
    #expect(harness.removedPendingIdentifiers.contains(identifier))
    #expect(!harness.pendingIdentifiers.contains(identifier))
    #expect(!harness.center.calls.contains(.add(identifier)))
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.isEmpty)
  }

  /// Native retention of a previously on-time report expires under the same policy as a
  /// first late report: at-time and reminder grace, and a before-reminder's prayer bound.
  @Test(arguments: [
    WakeCase(name: "at-time grace bound", kind: .atTime, lateness: 300, played: true),
    WakeCase(name: "past at-time grace", kind: .atTime, lateness: 301, played: false),
    WakeCase(name: "reminder grace bound", kind: .after, offset: 5, lateness: 120, played: true),
    WakeCase(name: "past reminder grace", kind: .after, offset: 5, lateness: 121, played: false),
    WakeCase(name: "before prayer", kind: .before, offset: 1, lateness: 59, played: true),
    WakeCase(name: "at prayer", kind: .before, offset: 1, lateness: 60, played: false),
  ])
  func anOnTimeReportsRetentionExpiresWithItsCatchUpPolicy(_ testCase: WakeCase) async {
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
    let identifier = Self.identifier(.asr, testCase.kind)
    harness.clock.now = fireDate.adding(seconds: 0.3)
    harness.clock.fireLate()
    await harness.settle()
    #expect(harness.pendingIdentifiers.contains(identifier))
    #expect(harness.audio.plays.count == 1)
    harness.center.forgetCalls()

    harness.clock.now = fireDate.adding(seconds: testCase.lateness)
    await harness.update()

    #expect(harness.pendingIdentifiers.contains(identifier) == testCase.played)
    #expect(harness.removedPendingIdentifiers.contains(identifier) == !testCase.played)
    #expect(!harness.center.calls.contains(.add(identifier)))
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.count == 1)
  }

  /// A queued notification decision can outlive the installation that first owned it.
  /// The barrier models its existing suspension behind previous delivery work; an unchanged
  /// refresh retains native ownership, while a changed one withdraws it before continuing.
  nonisolated enum QueuedRefresh: String, Sendable, CustomTestStringConvertible {
    case unchanged, disabled, retimed

    var testDescription: String { rawValue }
  }

  @Test(arguments: [QueuedRefresh.unchanged, .disabled, .retimed])
  func aRefreshReconcilesADeliveryAlreadyWaiting(_ refresh: QueuedRefresh) async {
    let gate = ScheduledAddGate()
    let due = Fixture.time(.isha)
    let harness = Harness(
      now: Fixture.date(19, 0), settings: [.isha: .alert(sound: .makkah)], othersOff: true,
      beforeDueDecision: { await gate.pause() })
    await harness.update()
    let identifier = Self.identifier(.isha, .atTime)
    #expect(harness.pendingIdentifiers.contains(identifier))
    harness.center.forgetCalls()
    harness.clock.now = due.adding(seconds: 0.3)
    harness.clock.fireLate()
    await gate.waitUntilPaused()
    let queued = harness.coordinator.delivery
    #expect(harness.pendingIdentifiers.contains(identifier))
    #expect(harness.audio.plays.map(\.request.context.event?.time) == [due])

    let schedule: PrayerSchedule
    switch refresh {
    case .unchanged:
      schedule = Fixture.schedule()
    case .disabled:
      harness.preferences.setConfig(.off, for: .isha)
      schedule = Fixture.schedule()
    case .retimed:
      // The replacement is beyond catch-up, so it cannot legitimately emit another due
      // alert or conceal resurrection of the old full occurrence in this regression.
      schedule = Fixture.schedule(ishaAdjustment: -6)
    }
    harness.coordinator.update(schedule: schedule)
    let installed = await harness.coordinator.installation?.value ?? nil
    #expect(installed?.verifiedAt == due.adding(seconds: 0.3))
    #expect(installed?.superseded == false)
    #expect(
      harness.center.calls.contains {
        if case .removePending(let identifiers) = $0 { return identifiers.contains(identifier) }
        return false
      } == (refresh != .unchanged))
    #expect(harness.pendingIdentifiers.contains(identifier) == (refresh == .unchanged))
    #expect(harness.center.delivered.isEmpty)
    #expect(harness.center.posted.isEmpty)

    await gate.release()
    await queued?.value
    await harness.settle()

    #expect(harness.center.posted.isEmpty)
    #expect(!harness.center.calls.contains(.add(identifier)))
    #expect(harness.clock.now == due.adding(seconds: 0.3))
    #expect(harness.audio.plays.map(\.request.resource.url) == [Self.makkah])
    #expect(harness.audio.plays.map(\.request.context.event?.time) == [due])
  }

  nonisolated enum QueuedContentChange: String, Sendable, CustomTestStringConvertible {
    case language, sound, silentMode, languageAndSilentMode

    var testDescription: String { rawValue }
  }

  /// The occurrence remains enabled, but a refresh withdraws its obsolete native
  /// content while due work is queued. Fallback must use the latest wording and sound,
  /// not either the content snapshot or PlannedAlert captured before that wait.
  @Test(arguments: [
    QueuedContentChange.language, .sound, .silentMode, .languageAndSilentMode,
  ])
  func aQueuedReportUsesCurrentNotificationContent(_ change: QueuedContentChange) async throws {
    let gate = ScheduledAddGate()
    defer { Task { await gate.release() } }
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .system)], othersOff: true,
      normalizePriority: true, beforeDueDecision: { await gate.pause() })
    await harness.update()
    let identifier = Self.identifier(.asr, .atTime)
    let original = try #require(harness.center.pendingRequest(identifier))
    #expect(original.content.title == "Asr")
    #expect(original.content.sound == .default)
    harness.clock.now = Self.asr.time.adding(seconds: 0.3)
    harness.clock.fireLate()
    await gate.waitUntilPaused()
    let queued = try #require(harness.coordinator.delivery)
    harness.center.forgetCalls()

    switch change {
    case .language: harness.preferences.appLanguage = .arabic
    case .sound: harness.preferences.setConfig(.alert(sound: .makkah), for: .asr)
    case .silentMode: harness.preferences.silentMode = true
    case .languageAndSilentMode:
      harness.preferences.appLanguage = .arabic
      harness.preferences.silentMode = true
    }
    harness.coordinator.update(schedule: Fixture.schedule())
    let installed = try #require(await harness.coordinator.installation?.value)
    #expect(installed.verifiedAt == Self.asr.time.adding(seconds: 0.3))
    #expect(harness.removedPendingIdentifiers == [identifier])
    #expect(!harness.pendingIdentifiers.contains(identifier))
    #expect(harness.center.posted.isEmpty)
    let current = try #require(
      harness.coordinator.alertSchedule?.alerts.first { $0.event == Self.asr })
    #expect(current.fireDate == Self.asr.time)
    let expected = PrayerAlertContent(preferences: harness.preferences).make(current)

    await gate.release()
    await queued.value
    await harness.settle()

    let posted = try #require(harness.center.posted.first)
    #expect(harness.center.posted.count == 1)
    #expect(posted.identifier == identifier)
    #expect(posted.trigger == nil)
    #expect(posted.content.title == expected.title)
    #expect(posted.content.body == expected.body)
    #expect(posted.content.sound == (change == .language ? .default : nil))
    #expect(posted.content.threadIdentifier == expected.threadIdentifier)
    #expect(posted.content.threadIdentifier == "salah-prayers-2026-06-02")
    #expect(NSDictionary(dictionary: posted.content.userInfo).isEqual(to: expected.userInfo))
    if change == .language || change == .languageAndSilentMode {
      #expect(posted.content.title == "العصر")
      #expect(posted.content.body != original.content.body)
    } else {
      #expect(posted.content.body == original.content.body)
    }
    #expect(harness.center.calls.filter { $0 == .add(identifier) }.count == 1)
    #expect(harness.audio.plays.isEmpty)
  }

  /// Disabling an alert during an on-time refresh must not preserve its playback or
  /// future native requests just because an earlier installation accepted it.
  @Test func anOnTimeRefreshRespectsADisabledAlert() async {
    let harness = Harness(
      now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .makkah)], othersOff: true,
      normalizePriority: true)
    await harness.update()
    harness.clock.now = Self.asr.time.adding(seconds: 0.3)
    harness.preferences.setConfig(.off, for: .asr)

    await harness.update()

    #expect(harness.center.pending.isEmpty)
    #expect(harness.center.posted.isEmpty)
    #expect(harness.audio.plays.isEmpty)
  }

  /// A changed fire date is a new occurrence even though the notification ID is stable.
  @Test func aRetimedOccurrenceDoesNotInheritAnEarlierHandoff() async throws {
    let harness = Harness(
      now: Fixture.date(19, 0), settings: [.isha: .alert(sound: .makkah)], othersOff: true,
      normalizePriority: true)
    await harness.update()
    let identifier = Self.identifier(.isha, .atTime)
    let old = try #require(harness.center.pendingRequest(identifier))
    #expect(Self.fireDate(of: old) == Fixture.time(.isha))
    let newTime = Fixture.time(.isha).adding(minutes: -5)
    harness.clock.now = newTime.adding(seconds: 0.3)

    await harness.update(Fixture.schedule(ishaAdjustment: -5))

    #expect(harness.center.posted.map(\.identifier) == [identifier])
    #expect(harness.audio.plays.count == 1)
    #expect(harness.audio.plays.first?.request.context.event?.time == newTime)
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

  /// A soft tone at prayer time isn't an adhan, so no du'a follows it.
  @Test func playsNoDuaAfterATone() async throws {
    let harness = Harness(now: Fixture.date(15, 0), settings: [.asr: .alert(sound: .softTone)])
    await harness.update()
    await harness.fire()
    let tone = try #require(harness.audio.plays.first)
    #expect(tone.request.resource.url?.lastPathComponent == "Tone-Soft.m4a")
    #expect(tone.followUp == nil)
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

    // Both were handed to the system, even though the reminder has left pending.
    #expect(harness.center.posted.isEmpty)
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

  /// Tapping a prayer alert while nothing plays opens Today, and stops nothing; the
  /// notification leaves Notification Center.
  @Test func tappingAnAlertWhileNothingPlaysOpensToday() async {
    let harness = Harness(now: Fixture.date(13, 0))
    harness.audio.isPlaying = false
    let identifier = Self.identifier(.maghrib, .atTime)

    await harness.coordinator.didTapAlert(identifier)

    #expect(harness.todayOpenCount == 1)
    #expect(harness.audio.stopCount == 0)
    #expect(harness.center.calls.contains(.removeDelivered([identifier])))
  }

  /// Tapping a prayer alert while its adhan plays stops it, and doesn't open the window.
  @Test func tappingAnAlertWhileItsAdhanPlaysStopsIt() async {
    let harness = Harness(now: Fixture.date(13, 0))
    harness.audio.isPlaying = true
    let identifier = Self.identifier(.maghrib, .atTime)

    await harness.coordinator.didTapAlert(identifier)

    #expect(harness.audio.stopCount == 1)
    #expect(harness.todayOpenCount == 0)
    #expect(harness.center.calls.contains(.removeDelivered([identifier])))
  }

  /// After Quit Salah, a tap neither opens the window nor reaches the center.
  @Test func tappingAnAlertAfterQuitSalahDoesNothing() async {
    let harness = Harness(now: Fixture.date(13, 0))
    await harness.coordinator.withdraw()
    harness.center.forgetCalls()

    await harness.coordinator.didTapAlert(Self.identifier(.maghrib, .atTime))

    #expect(harness.todayOpenCount == 0)
    #expect(harness.audio.stopCount == 0)
    #expect(harness.center.calls.isEmpty)
  }

  /// The app's player counts as playing for every sound it plays, and not while idle.
  @Test func theAppsPlayerPlaysWhileItsStateIsPlaying() {
    let player = AudioPlaybackController()
    #expect(!player.isPlaying)
    player.state = .playing(
      AudioPlaybackContext(source: .prayerAlert, slot: .alert, event: Self.asr))
    #expect(player.isPlaying)
    player.state = .playing(AudioPlaybackContext(source: .dua, slot: .alert, event: Self.asr))
    #expect(player.isPlaying)
    player.state = .idle
    #expect(!player.isPlaying)
  }

  /// The bodies are looked up in the app's locale when Salah ships its language, digits
  /// included, and in English otherwise, so an unshipped system language doesn't give
  /// the English fallback its plural rules ("1 minutes").
  @Test func bodiesFallBackToEnglishForALanguageSalahDoesntShip() {
    let arabic = AppLanguage.arabic.locale
    #expect(PrayerAlertContent.bodyLocale(for: arabic) == arabic)
    let canadianFrench = Locale(identifier: "fr-CA")
    #expect(PrayerAlertContent.bodyLocale(for: canadianFrench) == canadianFrench)
    #expect(PrayerAlertContent.bodyLocale(for: Locale(identifier: "zh-Hans-CN")).identifier == "en")
    #expect(PrayerAlertContent.bodyLocale(for: Locale(identifier: "ja")).identifier == "en")
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
