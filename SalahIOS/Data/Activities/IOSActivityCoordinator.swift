@preconcurrency import ActivityKit
import Foundation
import SalahCore
import SalahWidgets

nonisolated struct IOSActivityPublication: Sendable {
  var state: SalahActivityAttributes.ContentState
  var isApproaching: Bool
}

/// The activity lifecycle boundary is replaceable without requesting system activities in tests.
@MainActor struct IOSActivityLifecycle {
  var activities: () -> [Activity<SalahActivityAttributes>]
  var end: ([Activity<SalahActivityAttributes>]) async -> Void

  static var system: Self {
    Self(
      activities: { Activity<SalahActivityAttributes>.activities },
      end: { activities in
        for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
      })
  }
}

/// The prayers whose activity the person dismissed. They stay in the app's own defaults until
/// each one's activity window closes, so a relaunch within the window doesn't recreate one.
@MainActor struct IOSActivityDismissals {
  static let key = "Salah.iOS.dismissedActivities.v1"
  private let defaults: UserDefaults
  private var deadlines: [String: Date]

  init(defaults: UserDefaults) {
    self.defaults = defaults
    deadlines = defaults.dictionary(forKey: Self.key) as? [String: Date] ?? [:]
  }

  /// How long a dismissal holds: until the prayer's count-up ends, or, for a playback that ends
  /// before the prayer's approach begins, until the playback ends.
  nonisolated static func deadline(for state: SalahActivityAttributes.ContentState) -> Date {
    let approach = state.prayerTime.addingTimeInterval(-15 * 60)
    if state.mode == .playing, state.validUntil < approach { return state.validUntil }
    return max(state.validUntil, state.prayerTime.addingTimeInterval(15 * 60))
  }

  func contains(_ eventID: String, at date: Date) -> Bool {
    deadlines[eventID].map { date < $0 } ?? false
  }

  /// Keeps `eventID` until `deadline`, and forgets the dismissals whose window has closed.
  mutating func insert(_ eventID: String, until deadline: Date, now: Date) {
    deadlines = deadlines.filter { now < $0.value }
    deadlines[eventID] = max(deadline, deadlines[eventID] ?? deadline)
    defaults.set(deadlines, forKey: Self.key)
  }

  mutating func remove(_ eventID: String) {
    guard deadlines.removeValue(forKey: eventID) != nil else { return }
    defaults.set(deadlines, forKey: Self.key)
  }
}

/// Starts only a relevant foreground prayer activity and maintains its bounded state.
/// Background suspension is expected: staleDate makes the extension show recovery rather
/// than promising updates the process cannot deliver.
@MainActor
final class IOSActivityCoordinator {
  private var activity: Activity<SalahActivityAttributes>?
  private(set) var dismissals: IOSActivityDismissals
  private var lastPublished: SalahActivityAttributes.ContentState?
  private var revision: UInt64 = 0
  private let now: @Sendable () -> Date
  private let loadPlaybackSession: @MainActor () -> IOSPlaybackSession?
  private let lifecycle: IOSActivityLifecycle
  private(set) var lastError: String?

  init(
    now: @escaping @Sendable () -> Date = { Date() },
    loadPlaybackSession: @escaping @MainActor () -> IOSPlaybackSession? = {
      SharedValue<IOSPlaybackSession>.iosPlayback.load()
    },
    lifecycle: IOSActivityLifecycle = .system,
    defaults: UserDefaults = .standard
  ) {
    self.now = now
    self.loadPlaybackSession = loadPlaybackSession
    self.lifecycle = lifecycle
    dismissals = IOSActivityDismissals(defaults: defaults)
  }

  /// System activities use the service clock, independently of the screen's last render or fixture.
  /// Playback is read after schedule construction so a concurrent external Stop is observed.
  func publication(settings: SalahSettings?) -> IOSActivityPublication? {
    guard let settings else { return nil }
    let display = SalahDisplay(date: now(), settings: settings, schedule: settings.schedule)
    guard
      let state = SalahActivityAttributes.ContentState(
        display: display, playbackSession: loadPlaybackSession())
    else { return nil }
    return IOSActivityPublication(
      state: state, isApproaching: display.prayerState?.isApproaching == true)
  }

  func refresh(settings: SalahSettings?, isForeground: Bool) async {
    revision &+= 1
    let mine = revision
    guard let publication = publication(settings: settings) else {
      await finishCurrent()
      return
    }
    let state = publication.state
    let eventID = SalahActivityAttributes.eventID(for: state)
    reconcileActivity(eventID: eventID)
    if let activity, activity.attributes.eventID != eventID {
      await finishCurrent()
      guard mine == revision else { return }
    }
    if let activity {
      if activity.activityState == .dismissed || activity.activityState == .ended {
        dismissals.insert(
          activity.attributes.eventID, until: IOSActivityDismissals.deadline(for: state),
          now: now())
        self.activity = nil
        lastPublished = nil
      } else if Self.shouldPublish(state, after: lastPublished) {
        // Commit local ownership before suspension. Timestamp ordering also keeps a
        // slow earlier update from replacing a more recent preference/playback state.
        lastPublished = state
        await activity.update(
          ActivityContent(state: state, staleDate: state.validUntil), timestamp: state.updatedAt)
        guard mine == revision else { return }
      }
    }
    guard activity == nil, isForeground, !dismissals.contains(eventID, at: state.updatedAt)
    else { return }
    let relevant = state.mode != .countdown || publication.isApproaching
    guard relevant else { return }
    request(state)
  }

  /// Explicitly following a prayer may start earlier than the automatic 15-minute window.
  /// An explicit Play shows its activity, even for a prayer whose activity the person dismissed.
  func start(settings: SalahSettings) async {
    revision &+= 1
    let mine = revision
    guard let publication = publication(settings: settings) else { return }
    let state = publication.state
    await finishCurrent()
    guard mine == revision else { return }
    dismissals.remove(SalahActivityAttributes.eventID(for: state))
    request(state)
  }

  func end() async {
    revision &+= 1
    await finishCurrent()
  }

  /// Clear references before waiting. A concurrent foreground refresh may create a new
  /// activity, so the old completion must not clear or end that new reference.
  private func finishCurrent() async {
    let current = lifecycle.activities()
    activity = nil
    lastPublished = nil
    await lifecycle.end(current)
  }

  private func reconcileActivity(eventID: String) {
    if activity == nil {
      let existing = lifecycle.activities()
      activity = existing.first { $0.attributes.eventID == eventID } ?? existing.first
    }
  }

  private func request(_ state: SalahActivityAttributes.ContentState) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    do {
      activity = try Activity.request(
        attributes: SalahActivityAttributes(eventID: SalahActivityAttributes.eventID(for: state)),
        content: ActivityContent(state: state, staleDate: state.validUntil), pushType: nil)
      lastPublished = state
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// Compare all content except the refresh timestamp, then throttle timestamp-only updates.
  /// New presentation fields automatically participate in the synthesized equality.
  nonisolated static func shouldPublish(
    _ state: SalahActivityAttributes.ContentState,
    after lastPublished: SalahActivityAttributes.ContentState?
  ) -> Bool {
    guard var previous = lastPublished else { return true }
    let refreshedAt = previous.updatedAt
    previous.updatedAt = state.updatedAt
    return state != previous || state.updatedAt.timeIntervalSince(refreshedAt) >= 60
  }
}
