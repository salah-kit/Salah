import Foundation
import SalahAlerts
import SalahCore

/// The adhan while Salah is open, on SalahAlerts.
///
/// tvOS notifications carry no text or sound, so the TV has no notification plan. The
/// `InProcessAlertEngine` follows every enabled at-time alert from five minutes ago (the
/// catch-up window) to two days ahead, and reports each once when it comes due; the app
/// plays the prayer's sound and shows it. Reminders before and after a prayer aren't
/// planned on Apple TV.
///
/// The engine remembers what it reported only in memory, so the coordinator keeps the fire
/// date of the last adhan it settled in the defaults: a relaunch inside the catch-up window
/// doesn't play that adhan again.
@MainActor
final class TVAdhanCoordinator {
  static let namespace = "tv-adhan"
  static let catchUpWindow: TimeInterval = 5 * 60
  static let horizon: TimeInterval = 2 * 86_400
  /// How early the engine already counts an alert as due.
  static let earlyLeeway: TimeInterval = 1.5
  /// The defaults key of the fire date up to which past adhans are settled: reported, or
  /// passed over by a settings change.
  static let settledKey = "salah.tv.adhan.settledThrough"

  /// Called with the prayer whose adhan is due, once per occurrence.
  var onDue: ((PrayerEvent) -> Void)?

  private let planner = AlertPlanner()
  private let clock: any AlertClock
  private let defaults: UserDefaults
  private var engine: InProcessAlertEngine!
  /// The latest plan's alerts. Readable so tests can check what is planned.
  private(set) var schedule: AlertSchedule?

  init(clock: any AlertClock = SystemAlertClock(), defaults: UserDefaults) {
    self.clock = clock
    self.defaults = defaults
    engine = InProcessAlertEngine(clock: clock) { [weak self] due in self?.handle(due) }
  }

  /// Plans from the clock's instant. Call it on launch and activation, when the preferences
  /// or the day change, and after a clock change.
  ///
  /// `catchingUp` plays an adhan that began in the last five minutes: on activation, a new
  /// day and a clock change. A settings change passes `false`, so a prayer it turns on after
  /// the prayer began stays quiet; alerts the previous plan had are kept, so one due right
  /// now still plays.
  func update(schedule prayers: PrayerSchedule?, preferences: IOSPreferences, catchingUp: Bool) {
    let now = clock.now
    let start = now.addingTimeInterval(-Self.catchUpWindow)
    let end = now.addingTimeInterval(Self.horizon)
    guard let prayers, !preferences.muteSounds else {
      planNothing(at: now)
      return
    }
    let planned: AlertSchedule
    do {
      planned = try planner.schedule(
        prayers, namespace: Self.namespace, from: start, to: end,
        settings: { Self.settings(for: $0, preferences: preferences) })
    } catch {
      // The namespace is valid and no reminders are planned, so this doesn't happen; plan
      // nothing rather than guess.
      planNothing(at: now)
      return
    }
    // Due now or already past, so the settled date applies.
    let dueBy = now.addingTimeInterval(Self.earlyLeeway)
    // Already begun, beyond the engine's early leeway.
    let begun = now.addingTimeInterval(-Self.earlyLeeway)
    let settled = settledThrough
    let previous = Set((schedule?.alerts ?? []).map(\.occurrenceID))
    var passedOver: Date?
    var kept = planned
    kept.alerts = planned.alerts.filter { alert in
      if let settled, alert.fireDate <= settled, alert.fireDate <= dueBy { return false }
      if !catchingUp, alert.fireDate < begun, !previous.contains(alert.occurrenceID) {
        passedOver = max(passedOver ?? alert.fireDate, alert.fireDate)
        return false
      }
      return true
    }
    // A prayer passed over stays quiet when Salah comes back or relaunches.
    if let passedOver { settle(through: passedOver) }
    plan(kept)
  }

  /// Plans nothing, so no adhan is reported while Salah is hidden. `update` arms it again.
  func suspend() { planNothing(at: clock.now) }

  /// Reports what is due now and re-arms the wake-up: on activation and after a clock change.
  func resync() { engine.resync() }

  /// A prayer's at-time alert, while its sound isn't None. Friday's Dhuhr takes the
  /// Jumu'ah settings while the override is on.
  nonisolated static func settings(for subject: AlertSubject, preferences: IOSPreferences)
    -> AlertSettings?
  {
    guard preferences.tvSound(for: subject.prayer, observance: subject.observance) != .none
    else { return nil }
    return AlertSettings(atTime: true, sound: .system)
  }

  private func plan(_ alerts: AlertSchedule) {
    schedule = alerts
    engine.update(alerts)
  }

  private func planNothing(at now: Date) {
    plan(
      AlertSchedule(
        namespace: Self.namespace, alerts: [],
        requestedRange: DateInterval(
          start: now.addingTimeInterval(-Self.catchUpWindow),
          end: now.addingTimeInterval(Self.horizon)),
        gaps: []))
  }

  /// The fire date up to which past adhans are settled, kept across launches.
  private var settledThrough: Date? { defaults.object(forKey: Self.settledKey) as? Date }

  private func settle(through date: Date) {
    if let settledThrough, settledThrough >= date { return }
    defaults.set(date, forKey: Self.settledKey)
  }

  private func handle(_ due: [PlannedAlert]) {
    guard let alert = InProcessAlertEngine.preferredAlert(among: due.filter { $0.kind == .atTime })
    else { return }
    // The preferred alert is the latest due; settle before playing, so a replan while it
    // plays already knows it.
    settle(through: alert.fireDate)
    onDue?(alert.event)
  }
}

/// The engine's time from the app's clock, so a Debug journey that starts the clock at a
/// chosen instant hears the adhan at that clock's prayer time.
@MainActor
final class TVAlertClock: AlertClock {
  private let clock: TVClock
  private var task: Task<Void, Never>?

  init(clock: TVClock) { self.clock = clock }

  var now: Date { clock.now() }

  func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void) {
    task?.cancel()
    task = nil
    guard let date, !clock.frozen else { return }
    let delay = max(0, date.timeIntervalSince(clock.now()))
    task = Task { @MainActor in
      do {
        try await Task.sleep(
          for: .milliseconds(Int64((delay * 1_000).rounded(.up))), tolerance: .milliseconds(750))
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      action()
    }
  }
}
