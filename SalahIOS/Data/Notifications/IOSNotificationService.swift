import Foundation
import Observation
import SalahAlerts
import SalahCore
@preconcurrency import UserNotifications

/// Authorization and native presentation stay in the app, outside the prayer planner.
nonisolated protocol IOSNotificationCenter: AlertNotificationCenter {
  var delegate: (any UNUserNotificationCenterDelegate)? { get set }
  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
  func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
}

extension UNUserNotificationCenter: IOSNotificationCenter {}

@MainActor @Observable
final class IOSNotificationService: NSObject, UNUserNotificationCenterDelegate {
  nonisolated static let prefix = "io.github.salah-kit.Salah.ios."
  nonisolated static let namespace = "prayers"
  private(set) var status: IOSPermissionStatus = .notDetermined
  private(set) var report: NotificationApplyReport?
  private(set) var plan: NotificationPlan?
  private(set) var errorMessage: String?
  private(set) var isRefreshing = false
  var onAuthorizationChanged: ((IOSPermissionStatus) -> Void)?
  var onOpenURL: ((URL) -> Void)?

  @ObservationIgnored private let center: any IOSNotificationCenter
  @ObservationIgnored private let scheduler: NotificationScheduler
  @ObservationIgnored private let files: IOSAudioFiles
  @ObservationIgnored private var generation: UInt = 0
  @ObservationIgnored private let usesSystemCenter: Bool
  @ObservationIgnored private var muteSounds = false
  // The root service and app intents share one update pump, so the most recent plan wins.
  private static let systemScheduler = NotificationScheduler(
    identifierPrefix: prefix, namespace: namespace, center: UNUserNotificationCenter.current())
  private static var systemGeneration: UInt = 0
  private static var systemMuteSounds = false

  init(
    center: any IOSNotificationCenter = UNUserNotificationCenter.current(),
    files: IOSAudioFiles = IOSAudioFiles(), installDelegate: Bool = true,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.center = center
    self.files = files
    usesSystemCenter = center is UNUserNotificationCenter
    scheduler =
      usesSystemCenter
      ? Self.systemScheduler
      : NotificationScheduler(
        identifierPrefix: Self.prefix, namespace: Self.namespace, center: center, now: now)
    super.init()
    if installDelegate { center.delegate = self }
    center.setNotificationCategories([
      UNNotificationCategory(identifier: "salah.prayer", actions: [], intentIdentifiers: [])
    ])
    do { try files.prepareSounds() } catch {
      errorMessage = "Sound files could not be prepared. Try reopening Salah."
    }
  }

  @discardableResult
  func requestAuthorization() async -> IOSPermissionStatus {
    do {
      _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      errorMessage = nil
    } catch {
      errorMessage = "Notification permission could not be updated. Try again in Settings."
    }
    await refreshAuthorization()
    return status
  }

  func refreshAuthorization() async {
    let value = Self.permission(await center.authorizationStatus())
    status = value
    onAuthorizationChanged?(value)
  }

  /// Replans on launch, foreground, preferences, location, time-zone and background refresh.
  /// Read-back coverage proves installation, never presentation or audible delivery.
  ///
  /// A newer refresh supersedes this one. Cancellation doesn't stop it: it has already
  /// superseded older refreshes, so stopping would leave no plan installed.
  func refresh(
    schedule: PrayerSchedule?, preferences: IOSPreferences, now: Date = Date()
  ) async {
    generation &+= 1
    let mine = generation
    muteSounds = preferences.muteSounds
    if usesSystemCenter {
      Self.systemGeneration &+= 1
      Self.systemMuteSounds = preferences.muteSounds
    }
    let systemMine = Self.systemGeneration
    isRefreshing = true
    defer { if generation == mine { isRefreshing = false } }
    await refreshAuthorization()
    guard isCurrent(mine, system: systemMine) else { return }
    // Without a location there's nothing to plan. Before setup nothing is installed, and when the
    // stored settings can't be read, the installed alerts are still the user's, so they stay.
    guard let schedule else { return }
    do {
      // Reserve room for other app notifications without ever exceeding the 64 total.
      let pending = try await center.pendingNotificationRequests()
      guard isCurrent(mine, system: systemMine) else { return }
      let others = pending.filter { !Self.owns($0.identifier) }.count
      let budget = max(0, min(60, 64 - others))
      let planner = AlertPlanner()
      let end = now.addingTimeInterval(14 * 86_400)
      let alertSchedule = try planner.schedule(
        schedule, namespace: Self.namespace, from: now, to: end,
        maximumReminderOffset: .seconds(120 * 60)
      ) { subject in
        IOSNotificationPolicy.settings(for: subject, preferences: preferences, files: files)
      }
      let plan = planner.notificationPlan(
        alertSchedule, from: now, budget: AlertBudget(maxPending: budget))
      let content = IOSPrayerNotificationContent(preferences: preferences)
      guard isCurrent(mine, system: systemMine) else { return }
      let report = try await scheduler.apply(plan) { content.make($0) }
      guard isCurrent(mine, system: systemMine) else { return }
      self.plan = plan
      self.report = report
      if !report.failures.isEmpty && status == .authorized {
        errorMessage = "Some alerts could not be scheduled. Open Salah again to retry."
      } else {
        errorMessage = nil
      }
    } catch {
      guard isCurrent(mine, system: systemMine) else { return }
      errorMessage = "Alerts could not be scheduled. Open Salah again to retry."
    }
  }

  /// Used by the app-process Control Center intent, including when no scene is active.
  static func refreshFromPreferences(_ preferences: IOSPreferences) async {
    let service = IOSNotificationService(installDelegate: false)
    await service.refresh(schedule: preferences.mirror?.schedule, preferences: preferences)
  }

  /// The last day the current report fully covers. Without notification access nothing is
  /// scheduled, whatever coverage the report computed.
  func lastFullyScheduledDay(in timeZone: TimeZone) -> CivilDay? {
    guard status == .authorized, let report else { return nil }
    return Self.lastFullyScheduledDay(report, in: timeZone)
  }

  /// The last day in `timeZone` whose every alert the read-back confirmed, from the day of the
  /// read-back on. Coverage ends at the first missing alert, so that alert's own day isn't
  /// complete.
  nonisolated static func lastFullyScheduledDay(
    _ report: NotificationApplyReport, in timeZone: TimeZone
  ) -> CivilDay? {
    guard let coverage = report.confirmedCoveredUntil else { return nil }
    let day = CivilDay(containing: coverage, in: timeZone).adding(days: -1)
    return day < CivilDay(containing: report.verifiedAt, in: timeZone) ? nil : day
  }

  private func isCurrent(_ mine: UInt, system: UInt) -> Bool {
    generation == mine && (!usesSystemCenter || Self.systemGeneration == system)
  }

  nonisolated static func owns(_ identifier: String) -> Bool {
    NotificationIdentity(requestIdentifier: identifier, prefix: prefix)?.namespace == namespace
  }

  nonisolated static func permission(_ status: UNAuthorizationStatus) -> IOSPermissionStatus {
    switch status {
    case .authorized, .provisional, .ephemeral: .authorized
    case .denied: .denied
    case .notDetermined: .notDetermined
    @unknown default: .restricted
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    // iOS plays the prepared short notification clip. This never starts full adhan playback.
    await foregroundPresentationOptions()
  }

  func foregroundPresentationOptions() -> UNNotificationPresentationOptions {
    // Mute also applies if an audible request reaches the foreground during a replan.
    (usesSystemCenter ? Self.systemMuteSounds : muteSounds)
      ? [.banner, .list] : [.banner, .list, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard Self.owns(response.notification.request.identifier),
      response.actionIdentifier == UNNotificationDefaultActionIdentifier
    else {
      completionHandler()
      return
    }
    Task { @MainActor [weak self] in
      if let url = URL(string: "salah://today") { self?.onOpenURL?(url) }
    }
    completionHandler()
  }
}

nonisolated enum IOSNotificationPolicy {
  static func settings(
    for subject: AlertSubject, preferences: IOSPreferences, files: IOSAudioFiles
  ) -> AlertSettings {
    let value = preferences.alerts(for: subject.prayer, observance: subject.observance).normalized()
    return AlertSettings(
      atTime: value.atTime,
      before: value.beforeEnabled ? .seconds(value.beforeMinutes * 60) : nil,
      after: value.afterEnabled ? .seconds(value.afterMinutes * 60) : nil,
      sound: files.notificationSound(for: value.sound, muted: preferences.muteSounds),
      beforeSound: files.notificationSound(for: value.beforeSound, muted: preferences.muteSounds),
      afterSound: files.notificationSound(for: value.afterSound, muted: preferences.muteSounds))
  }
}

nonisolated struct IOSPrayerNotificationContent: Sendable {
  let locale: Locale
  let locationName: String
  let timeZone: TimeZone

  init(preferences: IOSPreferences) {
    locale = preferences.language.locale
    locationName = preferences.location?.name ?? ""
    timeZone = preferences.location?.timeZone ?? .current
  }

  func make(_ alert: PlannedAlert) -> UNMutableNotificationContent {
    let names = PrayerNames(locale: locale)
    let name = names.name(of: alert.event)
    let time = DateFormatter()
    time.locale = locale
    time.timeZone = timeZone
    time.dateStyle = .none
    time.timeStyle = .short
    let minutes = Int(abs(alert.fireDate.timeIntervalSince(alert.event.time) / 60).rounded())
    let content = UNMutableNotificationContent()
    content.title = name
    content.subtitle = locationName
    switch alert.kind {
    case .atTime:
      content.body = IOSL10n.format(
        "It’s time for %@ (%@).", arabic: "حان وقت %@ (%@).", locale: locale,
        arguments: name, time.string(from: alert.event.time))
    case .before:
      content.body = IOSL10n.format(
        "%@ in %lld minutes, at %@.", arabic: "%@ بعد %lld دقائق، في %@.", locale: locale,
        arguments: name, minutes, time.string(from: alert.event.time))
    case .after:
      content.body = IOSL10n.format(
        "%@ began %lld minutes ago.", arabic: "بدأ وقت %@ منذ %lld دقائق.", locale: locale,
        arguments: name, minutes)
    }
    content.sound = alert.sound.notificationSound
    content.categoryIdentifier = "salah.prayer"
    content.threadIdentifier = "salah.prayers.\(alert.event.scheduleDay)"
    content.userInfo = [
      "prayer": alert.event.kind.rawValue, "kind": alert.kind.rawValue,
      "owningDay": alert.event.scheduleDay.description, "offsetMinutes": minutes,
    ]
    content.interruptionLevel = alert.kind == .atTime ? .timeSensitive : .active
    content.relevanceScore = alert.kind == .atTime ? 1 : 0.5
    return content
  }
}
