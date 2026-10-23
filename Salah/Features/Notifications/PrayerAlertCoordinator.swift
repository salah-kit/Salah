import Foundation
import OSLog
import SalahAlerts
import SalahCore
// Requests copy their content and remain immutable across the scheduler/center boundary.
// The wrapper never mutates either; its separate receipt state is protected by its lock.
@preconcurrency import UserNotifications

/// Salah's prayer alerts, on SalahAlerts.
///
/// One `AlertPlanner` schedule covers every enabled alert from five minutes ago (the
/// catch-up window) to two weeks ahead. The OS gets the budgeted `NotificationPlan`
/// through the app's one `NotificationScheduler`; the `InProcessAlertEngine`, which an
/// always-running menu-bar app can keep, follows the whole schedule and reports each
/// alert when it comes due, reminders the plan left out included. When alerts come
/// due, the scheduler posts the ones the system won't deliver itself, and the app plays
/// the preferred one's sound, with the du'a after an adhan.
///
/// What stays Salah's: the settings each prayer gets (Friday's Dhuhr takes the Jumu'ah
/// settings while the override is on), the wording, threads, category and interruption
/// levels, asking for permission, playing the sounds, and what a tapped notification does:
/// it stops what's playing, or opens Today when nothing is.
@MainActor
final class PrayerAlertCoordinator: NSObject, UNUserNotificationCenterDelegate {
  /// Every request identifier starts with the app's bundle identifier.
  nonisolated static let identifierPrefix = "io.github.salah-kit.Salah."
  /// The one namespace Salah's prayer alerts use.
  nonisolated static let namespace = "prayers"
  /// The start of every prayer alert's thread: each prayer day has its own thread,
  /// ``threadIdentifier(for:)``.
  nonisolated static let threadPrefix = "salah-prayers"
  /// The category every prayer alert has: no actions, and the title stays visible when
  /// previews are hidden.
  nonisolated static let categoryIdentifier = "salah-prayer"
  /// How far ahead the plan looks: SalahAlerts' default budget horizon.
  static let horizon: TimeInterval = 14 * 86_400
  /// How far back the engine's schedule starts, so an alert due just before a replan
  /// is still caught up.
  static let catchUpWindow: TimeInterval = 5 * 60
  /// How long after an alert's fire date the engine's wake-up reports it on a Mac that's
  /// awake: the engine arms it 0.15 seconds after the fire date, and `SystemAlertClock`
  /// wakes within 0.75 seconds of that. A later report catches up, after a sleep or a busy
  /// moment. A sleep that ends within this second looks like an on-time report.
  static let onTimeReportDelay: TimeInterval = 1
  private static let catchUpPolicy = CatchUpPolicy()

  private let preferences: Preferences
  private let center: any PrayerNotificationCenter
  private let audio: any PrayerAlertAudioPlaying
  private let openToday: @MainActor () -> Void
  private let clock: any AlertClock
  /// The clock's time for the scheduler, whose actor can't read the main-actor clock.
  private let schedulerTime: SchedulerTime
  private let scheduler: NotificationScheduler
  private let handoffCenter: NotificationHandoffCenter
  /// Tests can hold queued due work before it decides whether native delivery owns it.
  private let beforeDueDecision: (@Sendable () async -> Void)?
  private let planner = AlertPlanner()
  private var engine: InProcessAlertEngine!
  private var authorizationRequest: Task<UNAuthorizationStatus, Never>?

  /// The latest plan's installation. Readable so tests can await it.
  private(set) var installation: Task<NotificationApplyReport?, Never>?
  private var installationHandoff: Task<NotificationHandoff, Never>?
  private var installationGeneration: UInt64 = 0
  /// The latest posting of due alerts. Readable so tests can await it.
  private(set) var delivery: Task<Void, Never>?
  /// The latest alert schedule, the engine's and the plan's.
  private(set) var alertSchedule: AlertSchedule?
  /// The prayer schedule the latest plan came from, so a late report can replan from it.
  private var plannedSchedule: PrayerSchedule?
  /// Set while `update(schedule:)` or `catchUp(schedule:)` runs: an alert reported then is
  /// posted after the installation they start, which is planned from the current instant.
  private var replanning = false
  /// An on-time engine report may finish while its accepted native request is still
  /// pending. Keep that request's responsibility across later unchanged refreshes, while
  /// the exact enabled occurrence remains in the schedule's catch-up range.
  private var onTimeReports: Set<AlertOccurrenceID> = []
  /// Set by `withdraw()` when Salah quits: nothing is planned or posted again.
  private var isWithdrawn = false

  /// The defaults are the app's wiring; tests inject the preferences, a fake
  /// notification center, a recording audio player, what opening Today does and a
  /// manual clock.
  init(
    preferences: Preferences = .shared,
    center: any PrayerNotificationCenter = UNUserNotificationCenter.current(),
    audio: any PrayerAlertAudioPlaying,
    openToday: @escaping @MainActor () -> Void = { AppWindowCoordinator.shared.open(.today) },
    clock: any AlertClock = SystemAlertClock(),
    schedulerNow: (@Sendable () -> Date)? = nil,
    beforeDueDecision: (@Sendable () async -> Void)? = nil
  ) {
    self.preferences = preferences
    self.center = center
    self.audio = audio
    self.openToday = openToday
    self.clock = clock
    self.beforeDueDecision = beforeDueDecision
    // The scheduler drops alerts that fired before its batch starts and dates its report by
    // its own clock, so it follows the injected clock too, not the wall clock.
    let schedulerTime = SchedulerTime()
    self.schedulerTime = schedulerTime
    let handoffCenter = NotificationHandoffCenter(center: center)
    self.handoffCenter = handoffCenter
    // No scheduler-wide thread: the content sets each prayer day's own.
    scheduler = NotificationScheduler(
      identifierPrefix: Self.identifierPrefix, namespace: Self.namespace,
      threadIdentifier: nil, center: handoffCenter,
      now: schedulerNow ?? { schedulerTime.now })
    super.init()
    engine = InProcessAlertEngine(catchUp: Self.catchUpPolicy, clock: clock) { [weak self] due in
      self?.handleDue(due)
    }
    center.delegate = self
    center.setNotificationCategories([Self.category])
  }

  /// The prayer alerts' category: no actions, and with previews hidden the banner still
  /// shows the prayer's name.
  nonisolated static var category: UNNotificationCategory {
    UNNotificationCategory(
      identifier: categoryIdentifier, actions: [], intentIdentifiers: [],
      options: .hiddenPreviewsShowTitle)
  }

  /// The thread of a prayer day's alerts, such as `salah-prayers-2026-06-02`: the day the
  /// prayer belongs to in the location's time zone, so a prayer's reminder, adhan and
  /// after-reminder stay together even when one of them falls on the other side of
  /// midnight.
  nonisolated static func threadIdentifier(for day: CivilDay) -> String {
    "\(threadPrefix)-\(day)"
  }

  // MARK: - Planning

  /// Plans every alert of `schedule` from the clock's current instant: the engine gets
  /// the whole schedule, the system the budgeted plan. Call it on launch and whenever
  /// the schedule, the alert settings or the language change, and after a wake or a
  /// clock change. The coordinator also replans from the latest schedule itself when the
  /// engine reports an alert late, which it can do before the app sees a wake.
  func update(schedule: PrayerSchedule) {
    guard !isWithdrawn else { return }
    let wasReplanning = replanning
    replanning = true
    defer { replanning = wasReplanning }
    plannedSchedule = schedule
    let now = clock.now
    schedulerTime.follow(now)
    let alerts: AlertSchedule
    do {
      alerts = try planner.schedule(
        schedule, namespace: Self.namespace, from: now.addingTimeInterval(-Self.catchUpWindow),
        to: now.addingTimeInterval(Self.horizon), settings: alertSettings(for:))
    } catch {
      // Salah's offsets are clamped to 1...120 minutes, inside the planner's two-hour
      // bound, and its namespace is valid, so this doesn't happen; plan nothing rather
      // than guess.
      AppLog.notifications.error(
        "Couldn't plan alerts: \(String(describing: error), privacy: .public)")
      return
    }
    alertSchedule = alerts
    AppLog.notifications.notice(
      "planned alerts=\(alerts.alerts.count, privacy: .public) gaps=\(alerts.gaps.count, privacy: .public)"
    )
    let exclusions = engine.notificationExclusions(at: now)
    onTimeReports.formIntersection(
      alerts.alerts.filter { Self.isWithinCatchUpRange($0, at: now) }.map(\.occurrenceID))
    onTimeReports.subtract(exclusions)
    // The installation first: alerts the engine reports due at once are posted after it.
    install(
      planner.notificationPlan(
        alerts, from: now, excluding: exclusions),
      retaining: alerts.alerts.filter {
        !exclusions.contains($0.occurrenceID)
          && (now.timeIntervalSince($0.fireDate) <= Self.onTimeReportDelay
            || onTimeReports.contains($0.occurrenceID))
      }
    )
    engine.update(alerts)
  }

  /// After a wake, a clock change or the app becoming active: replans from the clock's
  /// instant, then reports what's due. A first late report withdraws its overdue request
  /// before fallback; an on-time report's unchanged native handoff stays with the system.
  func catchUp(schedule: PrayerSchedule, afterClockChange: Bool = false) {
    // A clock-change event can land after an early report but before its fire date.
    // Retain exclusions before checking for newly due alerts; those keep pending requests.
    // The engine carries this state across later settings, wake and activation replans.
    if afterClockChange { engine.excludeHandledOccurrencesFromNotifications() }
    let wasReplanning = replanning
    replanning = true
    defer { replanning = wasReplanning }
    update(schedule: schedule)
    resync()
  }

  /// Reports what's due now and re-arms the engine's wake-up.
  func resync() {
    engine.resync()
  }

  /// Quit Salah turns everything off: after the installation in flight, removes every
  /// request Salah left pending, and plans and posts nothing more, so nothing alerts until
  /// Salah opens again. Notifications already delivered stay in Notification Center.
  func withdraw() async {
    isWithdrawn = true
    _ = await installation?.value
    await delivery?.value
    let pending = (try? await center.pendingNotificationRequests()) ?? []
    let identifiers = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
    if !identifiers.isEmpty {
      await center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    // The system's removal returns before the notification service has it; reading the
    // pending requests back waits until it does, before the process ends.
    let remaining = ((try? await center.pendingNotificationRequests()) ?? [])
      .filter { $0.identifier.hasPrefix(Self.identifierPrefix) }.count
    AppLog.notifications.notice(
      "withdrew requests=\(identifiers.count, privacy: .public) remaining=\(remaining, privacy: .public)"
    )
  }

  /// The alert settings of a prayer: Friday's Dhuhr takes the Jumu'ah settings while the
  /// override is on. Silent mode keeps every alert and drops its sound.
  func alertSettings(for subject: AlertSubject) -> AlertSettings? {
    let config =
      subject.observance == .jumuah && preferences.jumuahOverrideEnabled
      ? preferences.jumuahConfig : preferences.config(for: subject.prayer)
    guard config.alertEnabled || config.preReminderEnabled || config.postReminderEnabled else {
      return nil
    }
    func sound(_ sound: AdhanSound) -> AlertSound {
      preferences.silentMode ? .none : sound.alertSound
    }
    return AlertSettings(
      atTime: config.alertEnabled,
      before: config.preReminderEnabled ? .seconds(config.preReminderOffset * 60) : nil,
      after: config.postReminderEnabled ? .seconds(config.postReminderOffset * 60) : nil,
      sound: sound(config.alertSound), beforeSound: sound(config.preReminderSound),
      afterSound: sound(config.postReminderSound))
  }

  private static func isWithinCatchUpRange(_ alert: PlannedAlert, at now: Date) -> Bool {
    let grace = alert.kind == .atTime ? catchUpPolicy.atTimeGrace : catchUpPolicy.reminderGrace
    return Duration.seconds(now.timeIntervalSince(alert.fireDate)) <= max(.zero, grace)
      && (alert.kind != .before || now < alert.event.time)
  }

  private func install(_ plan: NotificationPlan, retaining retainable: [PlannedAlert]) {
    installationGeneration &+= 1
    let content = PrayerAlertContent(preferences: preferences)
    let wantsAlerts = !plan.alerts.isEmpty
    let previous = installationHandoff
    let handoffCenter = handoffCenter
    let handoff = Task { [weak self, scheduler, handoffCenter] in
      let preceding = await previous?.value
      guard let self else { return NotificationHandoff(report: nil, occurrences: []) }
      if wantsAlerts {
        await self.requestAuthorizationIfUndetermined()
      }
      // update() queues this task before the engine can make its first early report.
      // Observe reports after that update and any wait, without retaining unreported
      // future requests that the budget dropped or reports whose grace has expired.
      let retentionNow = self.clock.now
      let exclusions = self.engine.notificationExclusions(at: retentionNow)
      let retained = retainable.filter {
        Self.isWithinCatchUpRange($0, at: retentionNow)
          && !exclusions.contains($0.occurrenceID)
          && ($0.fireDate <= plan.effectiveRange.start
            || self.onTimeReports.contains($0.occurrenceID))
      }
      // A refresh may land before or after the on-time report's task finishes. Keep
      // native ownership for an unchanged request; a first late report starts afresh.
      let carried = preceding?.occurrences.intersection(retainable.map(\.occurrenceID)) ?? []
      let scope = handoffCenter.begin(
        plan, carrying: carried, retaining: retained, content: content)
      do {
        let report = try await scheduler.apply(plan, content: content.make)
        var occurrences = handoffCenter.finish(scope)
        if report.superseded || report.failures.values.contains(.notAuthorized) {
          occurrences = []
        } else {
          occurrences.formUnion(report.confirmed)
        }
        AppLog.notifications.notice(
          "installed requests=\(plan.alerts.count, privacy: .public) confirmed=\(report.confirmed.count, privacy: .public) superseded=\(report.superseded, privacy: .public)"
        )
        for (identity, failure) in report.failures {
          if case .addFailed(let reason) = failure {
            AppLog.notifications.error(
              "Failed to schedule \(identity.requestIdentifier(prefix: Self.identifierPrefix), privacy: .public): \(reason, privacy: .public)"
            )
          }
        }
        return NotificationHandoff(report: report, occurrences: occurrences)
      } catch {
        _ = handoffCenter.finish(scope)
        AppLog.notifications.error(
          "Refused plan: \(String(describing: error), privacy: .public)")
        return NotificationHandoff(report: nil, occurrences: [])
      }
    }
    installationHandoff = handoff
    installation = Task { await handoff.value.report }
  }

  /// Asks once for permission when there is something to schedule and the user hasn't
  /// answered yet. Salah asks; SalahAlerts never does.
  private func requestAuthorizationIfUndetermined() async {
    #if DEBUG
      // The real-app tests must never bring up a consent prompt.
      if preferences.defaults.bool(forKey: DebugOptions.withoutSystemPromptsKey) { return }
    #endif
    guard await center.authorizationStatus() == .notDetermined else { return }
    if let authorizationRequest {
      _ = await authorizationRequest.value
      return
    }
    let task = Task { [center] in
      do {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
      } catch {
        AppLog.notifications.error(
          "Failed to request notification authorization: \(error.localizedDescription, privacy: .public)"
        )
      }
      return await center.authorizationStatus()
    }
    authorizationRequest = task
    _ = await task.value
    authorizationRequest = nil
  }

  // MARK: - Due alerts

  /// Posts the due alerts the system won't deliver itself, and plays the preferred
  /// app-played sound among them.
  private func handleDue(_ due: [PlannedAlert]) {
    guard !isWithdrawn else { return }
    let now = clock.now
    onTimeReports.formUnion(
      due.filter { now.timeIntervalSince($0.fireDate) <= Self.onTimeReportDelay }
        .map(\.occurrenceID))
    for alert in due {
      AppLog.notifications.notice(
        "due \(alert.id.requestIdentifier(prefix: ""), privacy: .public) late=\(Int(now.timeIntervalSince(alert.fireDate)), privacy: .public)s"
      )
    }
    // The engine's wake-up waits on a clock that counts time asleep, so at the end of a
    // sleep it can report an overdue alert before the app sees the wake. Posting after the
    // installation from before the sleep would skip the alert as still pending, and the
    // wake's replan would then remove its request. Replanning first, as the wake will,
    // puts the posting behind an installation planned from now: it removes the overdue
    // request, and the posting posts the alert, or skips it if the system delivered it.
    if !replanning, let plannedSchedule,
      due.contains(where: { now.timeIntervalSince($0.fireDate) > Self.onTimeReportDelay })
    {
      AppLog.notifications.notice("replanning before a late report")
      update(schedule: plannedSchedule)
    }
    let previous = delivery
    let beforeDueDecision = beforeDueDecision
    delivery = Task { [weak self, scheduler] in
      _ = await previous?.value
      await beforeDueDecision?()
      guard let self else { return }
      // A refresh can withdraw the native request while previous delivery work or an
      // installation is suspended. Observe the latest installation, including one that
      // replaces it during the await, before deciding who still owns this occurrence.
      var handoff: NotificationHandoff?
      while true {
        let generation = self.installationGeneration
        handoff = await self.installationHandoff?.value
        if generation == self.installationGeneration { break }
      }
      let current = self.alertSchedule?.alerts ?? []
      // A fired request can leave pending before it appears in delivered. Reposting its
      // identifier in that interval replaces the notification the system is processing.
      // A disabled or retimed occurrence must not return as fallback after a withdrawal.
      let unplanned = due.compactMap { reported -> PlannedAlert? in
        guard handoff?.occurrences.contains(reported.occurrenceID) != true else { return nil }
        return current.first { $0.occurrenceID == reported.occurrenceID }
      }
      if !unplanned.isEmpty {
        // Both wording and sound can change while this decision waits. Resolve the
        // latest exact occurrence and content together, immediately before submission.
        let content = PrayerAlertContent(preferences: self.preferences)
        _ = try? await scheduler.deliver(unplanned, content: content.make)
      }
    }
    let played = due.filter { $0.sound.isPlayedByApp }
    if let alert = InProcessAlertEngine.preferredAlert(among: played) {
      play(alert)
    }
  }

  private func play(_ alert: PlannedAlert) {
    let slot = PrayerNotificationSoundSlot(alert.kind)
    let sound = config(for: alert).sound(for: slot)
    guard
      let resource = sound.audioPlaybackResource(refreshCustomFile: { [weak self] refreshed in
        self?.updateCustomSound(refreshed, replacing: sound, for: alert)
      })
    else { return }

    let offset = alert.kind == .atTime ? nil : alert.offsetMinutes
    audio.play(
      AudioPlaybackRequest(
        resource: resource, volume: alertVolume,
        context: AudioPlaybackContext(
          source: .prayerAlert, slot: slot, event: alert.event, prayerAlertOffsetMinutes: offset)),
      followUp: duaRequest(after: alert, offset: offset))
  }

  /// The settings an alert's sound comes from, read when it plays.
  private func config(for alert: PlannedAlert) -> PrayerNotificationConfig {
    alert.event.observance == .jumuah && preferences.jumuahOverrideEnabled
      ? preferences.jumuahConfig : preferences.config(for: alert.event.kind)
  }

  /// Keeps a custom sound's refreshed bookmark, unless the setting changed meanwhile.
  private func updateCustomSound(
    _ file: CustomAdhanFile, replacing sound: AdhanSound, for alert: PlannedAlert
  ) {
    let slot = PrayerNotificationSoundSlot(alert.kind)
    var config = config(for: alert)
    guard config.sound(for: slot) == sound else { return }
    config.setSound(.custom(file), for: slot)
    if alert.event.observance == .jumuah, preferences.jumuahOverrideEnabled {
      preferences.setJumuahConfig(config)
    } else {
      preferences.setConfig(config, for: alert.event.kind)
    }
  }

  /// The du'a after an adhan, when it's on (Salah's policy: never after a reminder).
  private func duaRequest(after alert: PlannedAlert, offset: Int?) -> AudioPlaybackRequest? {
    guard alert.kind == .atTime, !preferences.silentMode, preferences.duaEnabled,
      let url = AppResources.bundle.url(forResource: "Dua", withExtension: "m4a")
    else { return nil }
    return AudioPlaybackRequest(
      url: url, volume: alertVolume,
      context: AudioPlaybackContext(
        source: .dua, slot: .alert, event: alert.event, prayerAlertOffsetMinutes: offset))
  }

  private var alertVolume: Float {
    Float(max(0, min(preferences.alertVolume, 100))) / 100.0
  }

  // MARK: - UNUserNotificationCenterDelegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    // A menu-bar app is always in the foreground: show every banner. A prayer alert
    // arriving is also a moment to catch up on what's due.
    if Self.isPrayerAlert(notification.request.identifier) {
      Task { @MainActor in self.resync() }
    }
    completionHandler([.banner, .list, .sound])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let identifier = response.notification.request.identifier
    guard Self.isPrayerAlert(identifier),
      response.actionIdentifier == UNNotificationDefaultActionIdentifier
    else {
      completionHandler()
      return
    }
    Task { @MainActor in await self.didTapAlert(identifier) }
    completionHandler()
  }

  /// A tap on a prayer alert's banner stops what's playing, so one click hushes a long
  /// adhan, or opens Today when nothing is. Either way the notification leaves
  /// Notification Center.
  func didTapAlert(_ identifier: String) async {
    if audio.isPlaying {
      audio.stop()
    } else {
      openToday()
    }
    await center.removeDeliveredNotifications(withIdentifiers: [identifier])
  }

  /// Whether a request identifier is one of Salah's prayer alerts.
  nonisolated static func isPrayerAlert(_ identifier: String) -> Bool {
    NotificationIdentity(requestIdentifier: identifier, prefix: identifierPrefix)?.namespace
      == namespace
  }
}

nonisolated private struct NotificationHandoff: Sendable {
  var report: NotificationApplyReport?
  var occurrences: Set<AlertOccurrenceID>
}

/// Records the native handoff separately from full content verification: macOS may
/// rewrite interruption priority after accepting a request. Each receipt belongs to one
/// installation and stores the original full occurrence, never just its stable identifier.
nonisolated private final class NotificationHandoffCenter: AlertNotificationCenter,
  @unchecked Sendable
{
  // @unchecked: every receipt field is protected by lock; the underlying center is Sendable.
  private let center: any PrayerNotificationCenter
  private let lock = NSLock()
  private var scope: UUID?
  private var expected: [String: PlannedAlert] = [:]
  private var handedOff: Set<AlertOccurrenceID> = []
  private var revoked: Set<AlertOccurrenceID> = []
  private var retainableRequests: [String: RetainedRequest] = [:]
  private var retainedPending: Set<String> = []
  private var retentionAuthorized = false

  /// Content is copied and immutable, like the requests crossing the scheduler boundary.
  private struct RetainedRequest {
    var occurrence: AlertOccurrenceID
    var content: UNNotificationContent
  }

  init(center: any PrayerNotificationCenter) {
    self.center = center
  }

  func begin(
    _ plan: NotificationPlan, carrying occurrences: Set<AlertOccurrenceID>,
    retaining alerts: [PlannedAlert], content: PrayerAlertContent
  ) -> UUID {
    lock.withLock {
      let token = UUID()
      scope = token
      expected = [:]
      handedOff = occurrences
      revoked = []
      retainableRequests = [:]
      retainedPending = []
      retentionAuthorized = false
      for alert in plan.alerts {
        expected[alert.id.requestIdentifier(prefix: PrayerAlertCoordinator.identifierPrefix)] =
          alert
      }
      for alert in alerts where occurrences.contains(alert.occurrenceID) {
        let identifier = alert.id.requestIdentifier(prefix: PrayerAlertCoordinator.identifierPrefix)
        let body = content.make(alert)
        retainableRequests[identifier] = RetainedRequest(
          occurrence: alert.occurrenceID,
          content: UNNotificationRequest(identifier: identifier, content: body, trigger: nil)
            .content)
      }
      return token
    }
  }

  func finish(_ token: UUID) -> Set<AlertOccurrenceID> {
    lock.withLock {
      guard scope == token else { return [] }
      defer {
        scope = nil
        expected = [:]
        handedOff = []
        revoked = []
        retainableRequests = [:]
        retainedPending = []
        retentionAuthorized = false
      }
      return handedOff
    }
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    let token = lock.withLock { scope }
    let status = await center.authorizationStatus()
    lock.withLock {
      if let token, token == scope {
        retentionAuthorized = status == .authorized || status == .provisional
      }
    }
    return status
  }

  func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
    let token = lock.withLock { scope }
    let requests = try await center.pendingNotificationRequests()
    for request in requests {
      let identifier = request.identifier
      let fireDate = Self.calendarFireDate(of: request)
      record(identifier: identifier, fireDate: fireDate, in: token)
      lock.withLock {
        if let token, token == scope, let retained = retainableRequests[identifier],
          Self.matches(request, fireDate: fireDate, retained: retained)
        {
          retainedPending.insert(identifier)
        }
      }
    }
    return requests
  }

  func add(_ request: UNNotificationRequest) async throws {
    let identifier = request.identifier
    let fireDate = Self.calendarFireDate(of: request)
    let receipt = lock.withLock {
      let token = scope
      return (
        token: token,
        occurrence: occurrence(identifier: identifier, fireDate: fireDate, in: token)
      )
    }
    // A failed replacement does not remove an existing native request or its receipt.
    try await center.add(request)
    lock.withLock {
      guard let token = receipt.token, token == scope, let occurrence = receipt.occurrence else {
        return
      }
      revoked.remove(occurrence)
      handedOff.insert(occurrence)
    }
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
    let withdrawn = lock.withLock {
      // Applying the future-only plan must not cancel a matching on-time request the
      // system still owns, even after its engine callback has already completed.
      let withdrawn = identifiers.filter { !retentionAuthorized || !retainedPending.contains($0) }
      let removed = handedOff.filter {
        withdrawn.contains(
          $0.notification.requestIdentifier(prefix: PrayerAlertCoordinator.identifierPrefix))
      }
      handedOff.subtract(removed)
      revoked.formUnion(removed)
      for identifier in withdrawn {
        if let alert = expected[identifier] {
          handedOff.remove(alert.occurrenceID)
          revoked.insert(alert.occurrenceID)
        }
      }
      return withdrawn
    }
    if !withdrawn.isEmpty {
      await center.removePendingNotificationRequests(withIdentifiers: withdrawn)
    }
  }

  /// The same comparison as the scheduler's content contract, except the two priority
  /// fields macOS may normalize after acceptance. That exception preserves a native
  /// handoff; it never adds an occurrence to the scheduler's confirmed coverage.
  private static func matches(
    _ request: UNNotificationRequest, fireDate: Date?, retained: RetainedRequest
  ) -> Bool {
    let seconds = (retained.occurrence.fireDate.timeIntervalSinceReferenceDate - 0.001).rounded(.up)
    guard fireDate == Date(timeIntervalSinceReferenceDate: seconds) else { return false }
    let a = request.content
    let b = retained.content
    let priorityMatches =
      (a.interruptionLevel == b.interruptionLevel && a.relevanceScore == b.relevanceScore)
      || (a.interruptionLevel == .active && a.relevanceScore == 0)
    return priorityMatches && a.title == b.title && a.subtitle == b.subtitle && a.body == b.body
      && a.sound == b.sound && a.badge == b.badge && a.threadIdentifier == b.threadIdentifier
      && a.categoryIdentifier == b.categoryIdentifier && a.attachments.isEmpty
      && NSDictionary(dictionary: a.userInfo).isEqual(to: b.userInfo)
      && a.targetContentIdentifier == b.targetContentIdentifier
      && a.filterCriteria == b.filterCriteria
  }

  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] {
    await center.deliveredNotificationRecords()
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
    await center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  private func record(identifier: String, fireDate: Date?, in token: UUID?) {
    lock.withLock {
      if let occurrence = occurrence(identifier: identifier, fireDate: fireDate, in: token) {
        if !revoked.contains(occurrence) { handedOff.insert(occurrence) }
      }
    }
  }

  private func occurrence(identifier: String, fireDate: Date?, in token: UUID?)
    -> AlertOccurrenceID?
  {
    // Called only while lock is held.
    guard let token, token == scope, let alert = expected[identifier] else { return nil }
    // SalahAlerts 0.4's documented request rounding preserves a whole second within 1ms.
    let seconds = (alert.fireDate.timeIntervalSinceReferenceDate - 0.001).rounded(.up)
    guard fireDate == Date(timeIntervalSinceReferenceDate: seconds) else { return nil }
    return alert.occurrenceID
  }

  /// Decodes only value data before a request can cross the native center's boundary.
  private static func calendarFireDate(of request: UNNotificationRequest) -> Date? {
    guard let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats,
      var calendar = trigger.dateComponents.calendar, let zone = trigger.dateComponents.timeZone
    else { return nil }
    calendar.timeZone = zone
    var components = trigger.dateComponents
    components.calendar = nil
    components.timeZone = nil
    return calendar.date(from: components)
  }
}

// MARK: - The scheduler's time

/// The coordinator's clock as the scheduler's actor reads it: the system's time moved by
/// the clock's offset from it, recorded at each plan. With the system clock the offset is
/// about zero; with a test's manual clock, the scheduler sees the test's instant.
nonisolated private final class SchedulerTime: @unchecked Sendable {
  // @unchecked: `offset` is only read and written while holding `lock`.
  private let lock = NSLock()
  private var offset: TimeInterval = 0

  /// Records the clock's current instant.
  func follow(_ instant: Date) {
    let offset = instant.timeIntervalSinceNow
    lock.withLock { self.offset = offset }
  }

  /// The clock's time now.
  var now: Date {
    Date().addingTimeInterval(lock.withLock { offset })
  }
}

// MARK: - Content

/// The notification content of Salah's prayer alerts, built from values the coordinator
/// reads on the main actor, so the scheduler's actor can call it.
nonisolated struct PrayerAlertContent: Sendable {
  let names: PrayerNames
  let text: SalahText
  /// The place the times are for, as the dropdown names it; empty without one.
  let place: String
  let bundle: LocalizedStringResource.BundleDescription

  @MainActor
  init(preferences: Preferences) {
    let locale = preferences.appLanguage.locale
    names = PrayerNames(locale: locale)
    text = SalahText(
      locale: locale, timeZone: TimeZone(identifier: preferences.storedTimeZone) ?? .current)
    place = preferences.prayerLocation.name ?? ""
    bundle = AppResources.localizationBundle
  }

  /// The content of one alert: the prayer's name as the title, the place as the
  /// subtitle, the body for its kind, the prayer day's thread, Salah's category, and
  /// Salah's interruption level and relevance. A sound the app plays itself gives the
  /// notification no sound.
  func make(_ alert: PlannedAlert) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    let name = names.name(of: alert.event)
    let offset = alert.offsetMinutes
    content.title = name
    content.subtitle = place
    content.body = body(of: alert, name: name, offset: offset)
    content.threadIdentifier = PrayerAlertCoordinator.threadIdentifier(
      for: alert.event.scheduleDay)
    content.categoryIdentifier = PrayerAlertCoordinator.categoryIdentifier
    content.userInfo = [
      "prayer": alert.event.kind.rawValue,
      "kind": alert.kind.legacyName,
      "offsetMinutes": alert.kind == .atTime ? 0 : offset,
    ]
    // Only the prayer time is time-sensitive, so it can break through Focus. The
    // reminders before and after it are standard notifications.
    switch alert.kind {
    case .atTime:
      content.interruptionLevel = .timeSensitive
      content.relevanceScore = 1.0
    case .before:
      content.interruptionLevel = .active
      content.relevanceScore = 0.7
    case .after:
      content.interruptionLevel = .active
      content.relevanceScore = 0.5
    }
    if alert.sound == .system {
      content.sound = .default
    }
    return content
  }

  /// "It’s time for Maghrib (7:00 PM).", "Maghrib in 10 minutes, at 7:00 PM." or "Maghrib
  /// began 5 minutes ago.". The minutes go in as a number, so each language picks its
  /// plural form and writes the number in its own digits. In a right-to-left language,
  /// Foundation isolates each argument.
  private func body(of alert: PlannedAlert, name: String, offset: Int) -> String {
    let locale = text.locale
    let time = text.timeFormatter().string(from: alert.event.time)
    let resource: LocalizedStringResource
    switch alert.kind {
    case .atTime:
      resource = LocalizedStringResource(
        "notification.atTime", defaultValue: "It’s time for \(name) (\(time)).", locale: locale,
        bundle: bundle)
    case .before:
      resource = LocalizedStringResource(
        "notification.before", defaultValue: "\(name) in \(offset) minutes, at \(time).",
        locale: locale, bundle: bundle)
    case .after:
      resource = LocalizedStringResource(
        "notification.after", defaultValue: "\(name) began \(offset) minutes ago.",
        locale: locale, bundle: bundle)
    }
    return String(localized: resource)
  }
}

// MARK: - Seams and mappings

/// The part of `UNUserNotificationCenter` the coordinator uses beyond what the scheduler
/// does: the delegate, the categories and asking for permission. Test seam: tests pass a
/// fake.
nonisolated protocol PrayerNotificationCenter: AlertNotificationCenter {
  var delegate: (any UNUserNotificationCenterDelegate)? { get set }
  func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: PrayerNotificationCenter {}

/// The part of `AudioPlaybackController` the coordinator uses. Test seam: tests record
/// the requests instead of playing them.
protocol PrayerAlertAudioPlaying: AnyObject {
  /// Whether something plays: an adhan, a reminder's sound or the du'a.
  var isPlaying: Bool { get }
  func play(_ request: AudioPlaybackRequest, followUp: AudioPlaybackRequest?)
  func stop()
}

extension AudioPlaybackController: PrayerAlertAudioPlaying {
  var isPlaying: Bool { state != .idle }
}

extension AdhanSound {
  /// The alert sound SalahAlerts plans with: the system sound or none as they are, and a
  /// sound the app plays itself named by its kind and file.
  var alertSound: AlertSound {
    switch self {
    case .system: .system
    case .none: .none
    case .builtIn(let sound): .named("builtIn/\(sound.rawValue)")
    case .custom(let file): .named("custom/\(file.fileName)")
    }
  }
}

extension PlannedAlert {
  /// A reminder's offset from its prayer, in whole minutes; 0 for an at-time alert.
  nonisolated var offsetMinutes: Int {
    Int((fireDate.timeIntervalSince(event.time) / 60).magnitude.rounded())
  }
}

extension AlertSound {
  /// Whether the app plays the sound itself, rather than the system or nobody.
  nonisolated var isPlayedByApp: Bool {
    if case .named = self { return true }
    return false
  }
}

extension AlertKind {
  /// The kind's name in a notification's `userInfo`, as Salah has always written it.
  nonisolated var legacyName: String {
    switch self {
    case .atTime: "prayerTime"
    case .before: "preReminder"
    case .after: "postReminder"
    }
  }
}

extension PrayerNotificationSoundSlot {
  init(_ kind: AlertKind) {
    switch kind {
    case .atTime: self = .alert
    case .before: self = .preReminder
    case .after: self = .postReminder
    }
  }
}
