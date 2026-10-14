import Foundation
import OSLog
import SalahAlerts
import SalahCore
import UserNotifications

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
/// settings while the override is on), the wording and interruption levels, asking for
/// permission, playing the sounds, and stopping them from a tapped notification.
@MainActor
final class PrayerAlertCoordinator: NSObject, UNUserNotificationCenterDelegate {
  /// Every request identifier starts with the app's bundle identifier.
  nonisolated static let identifierPrefix = "io.github.salah-kit.Salah."
  /// The one namespace Salah's prayer alerts use.
  nonisolated static let namespace = "prayers"
  /// The notification thread every prayer alert joins.
  nonisolated static let threadIdentifier = "salah-prayers"
  /// How far ahead the plan looks: SalahAlerts' default budget horizon.
  static let horizon: TimeInterval = 14 * 86_400
  /// How far back the engine's schedule starts, so an alert due just before a replan
  /// is still caught up.
  static let catchUpWindow: TimeInterval = 5 * 60
  /// How long the coordinator remembers an alert it saw come due.
  static let handledRetention: TimeInterval = 86_400

  private let preferences: Preferences
  private let center: any PrayerNotificationCenter
  private let audio: any PrayerAlertAudioPlaying
  private let clock: any AlertClock
  /// The clock's time for the scheduler, whose actor can't read the main-actor clock.
  private let schedulerTime: SchedulerTime
  private let scheduler: NotificationScheduler
  private let planner = AlertPlanner()
  private var engine: InProcessAlertEngine!
  private var authorizationRequest: Task<UNAuthorizationStatus, Never>?
  /// The alerts reported due, with the clock's time then. A clock set back past one
  /// puts it in the future again; the plan leaves it out, so the system doesn't deliver
  /// it twice (SalahKit#16).
  private var handled: [AlertOccurrenceID: Date] = [:]

  /// The latest plan's installation. Readable so tests can await it.
  private(set) var installation: Task<NotificationApplyReport?, Never>?
  /// The latest posting of due alerts. Readable so tests can await it.
  private(set) var delivery: Task<Void, Never>?
  /// The latest alert schedule, the engine's and the plan's.
  private(set) var alertSchedule: AlertSchedule?

  /// The defaults are the app's wiring; tests inject the preferences, a fake
  /// notification center, a recording audio player and a manual clock.
  init(
    preferences: Preferences = .shared,
    center: any PrayerNotificationCenter = UNUserNotificationCenter.current(),
    audio: any PrayerAlertAudioPlaying,
    clock: any AlertClock = SystemAlertClock()
  ) {
    self.preferences = preferences
    self.center = center
    self.audio = audio
    self.clock = clock
    // The scheduler drops alerts that fired before its batch starts and dates its report by
    // its own clock, so it follows the injected clock too, not the wall clock.
    let schedulerTime = SchedulerTime()
    self.schedulerTime = schedulerTime
    scheduler = NotificationScheduler(
      identifierPrefix: Self.identifierPrefix, namespace: Self.namespace,
      threadIdentifier: Self.threadIdentifier, center: center,
      now: { schedulerTime.now })
    super.init()
    engine = InProcessAlertEngine(clock: clock) { [weak self] due in
      self?.handleDue(due)
    }
    center.delegate = self
  }

  // MARK: - Planning

  /// Plans every alert of `schedule` from the clock's current instant: the engine gets
  /// the whole schedule, the system the budgeted plan. Call it on launch and whenever
  /// the schedule, the alert settings or the language change, and after a wake or a
  /// clock change.
  func update(schedule: PrayerSchedule) {
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
    handled = handled.filter { $0.value > now.addingTimeInterval(-Self.handledRetention) }
    var requested = alerts
    requested.alerts.removeAll { alert in handled[alert.occurrenceID].map { now < $0 } ?? false }
    // The installation first: alerts the engine reports due at once are posted after it.
    install(planner.notificationPlan(requested, from: now))
    engine.update(alerts)
  }

  /// After a wake, a clock change or the app becoming active: replans from the clock's
  /// instant, then reports what's due. The replan drops an overdue request first, so an
  /// alert caught up is posted rather than skipped as still pending and then removed.
  func catchUp(schedule: PrayerSchedule) {
    update(schedule: schedule)
    resync()
  }

  /// Reports what's due now and re-arms the engine's wake-up.
  func resync() {
    engine.resync()
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

  private func install(_ plan: NotificationPlan) {
    let content = PrayerAlertContent(preferences: preferences)
    let wantsAlerts = !plan.alerts.isEmpty
    let previous = installation
    installation = Task { [weak self, scheduler] in
      _ = await previous?.value
      guard let self else { return nil }
      if wantsAlerts {
        await self.requestAuthorizationIfUndetermined()
      }
      do {
        let report = try await scheduler.apply(plan, content: content.make)
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
        return report
      } catch {
        AppLog.notifications.error(
          "Refused plan: \(String(describing: error), privacy: .public)")
        return nil
      }
    }
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
    for alert in due {
      handled[alert.occurrenceID] = clock.now
      AppLog.notifications.notice(
        "due \(alert.id.requestIdentifier(prefix: ""), privacy: .public) late=\(Int(self.clock.now.timeIntervalSince(alert.fireDate)), privacy: .public)s"
      )
    }
    let content = PrayerAlertContent(preferences: preferences)
    let previous = delivery
    let installing = installation
    delivery = Task { [scheduler] in
      // After the installation in progress: an alert due a moment early is then pending,
      // or delivered, and the scheduler skips it rather than post it twice.
      _ = await installing?.value
      _ = await previous?.value
      _ = try? await scheduler.deliver(due, content: content.make)
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
    guard Self.isPrayerAlert(identifier) else {
      completionHandler()
      return
    }
    // Tapping a prayer alert's banner stops the adhan that's playing, so one click
    // hushes a long adhan.
    Task { @MainActor in
      self.audio.stop()
      await self.center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    completionHandler()
  }

  /// Whether a request identifier is one of Salah's prayer alerts.
  nonisolated static func isPrayerAlert(_ identifier: String) -> Bool {
    NotificationIdentity(requestIdentifier: identifier, prefix: identifierPrefix)?.namespace
      == namespace
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
  let atTimeFormat: String
  let beforeFormat: String
  let afterFormat: String

  @MainActor
  init(preferences: Preferences) {
    let locale = preferences.appLanguage.locale
    names = PrayerNames(locale: locale)
    text = SalahText(
      locale: locale, timeZone: TimeZone(identifier: preferences.storedTimeZone) ?? .current)
    atTimeFormat = localizedString("notification.atTime", locale: locale)
    beforeFormat = localizedString("notification.preReminder.offset", locale: locale)
    afterFormat = localizedString("notification.postReminder.offset", locale: locale)
  }

  /// The content of one alert: the prayer's name as the title, the time or the
  /// reminder's offset in the body, and Salah's interruption level and relevance. A
  /// sound the app plays itself gives the notification no sound.
  func make(_ alert: PlannedAlert) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    let name = names.name(of: alert.event)
    let locale = text.locale
    let offset = alert.offsetMinutes
    content.title = name
    switch alert.kind {
    case .atTime:
      content.body = String(format: atTimeFormat, locale: locale, name, text.time(alert.event.time))
    case .before:
      content.body = String(
        format: beforeFormat, locale: locale, name, text.digits(offset).bidiIsolated)
    case .after:
      content.body = String(
        format: afterFormat, locale: locale, name, text.digits(offset).bidiIsolated)
    }
    content.userInfo = [
      "prayer": alert.event.kind.rawValue,
      "kind": alert.kind.legacyName,
      "offsetMinutes": alert.kind == .atTime ? 0 : offset,
    ]
    // The before-reminder shares the prayer time's time-sensitive level so it can
    // break through Focus before the prayer. The after-reminder stays standard since
    // the prayer window is already closing by then.
    switch alert.kind {
    case .atTime:
      content.interruptionLevel = .timeSensitive
      content.relevanceScore = 1.0
    case .before:
      content.interruptionLevel = .timeSensitive
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
}

// MARK: - Seams and mappings

/// The part of `UNUserNotificationCenter` the coordinator uses beyond what the scheduler
/// does: the delegate and asking for permission. Test seam: tests pass a fake.
nonisolated protocol PrayerNotificationCenter: AlertNotificationCenter {
  var delegate: (any UNUserNotificationCenterDelegate)? { get set }
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: PrayerNotificationCenter {}

/// The part of `AudioPlaybackController` the coordinator uses. Test seam: tests record
/// the requests instead of playing them.
protocol PrayerAlertAudioPlaying: AnyObject {
  func play(_ request: AudioPlaybackRequest, followUp: AudioPlaybackRequest?)
  func stop()
}

extension AudioPlaybackController: PrayerAlertAudioPlaying {}

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
