@preconcurrency import ActivityKit
import Foundation
import SalahCore
import SalahWidgets

/// Starts only a relevant foreground prayer activity and maintains its bounded state.
/// Background suspension is expected: staleDate makes the extension show recovery rather
/// than promising updates the process cannot deliver.
@MainActor
final class IOSActivityCoordinator {
  private var activity: Activity<SalahActivityAttributes>?
  private var dismissedEventIDs: Set<String> = []
  private var lastPublished: SalahActivityAttributes.ContentState?
  private var revision: UInt64 = 0
  private(set) var lastError: String?

  func refresh(display: SalahDisplay?, isForeground: Bool) async {
    revision &+= 1
    let mine = revision
    guard let display,
      let state = SalahActivityAttributes.ContentState(
        display: display, playbackSession: SharedValue<IOSPlaybackSession>.iosPlayback.load())
    else {
      await finishCurrent()
      return
    }
    let eventID = SalahActivityAttributes.eventID(for: state)
    reconcileActivity(eventID: eventID)
    if let activity, activity.attributes.eventID != eventID {
      await finishCurrent()
      guard mine == revision else { return }
    }
    if let activity {
      if activity.activityState == .dismissed || activity.activityState == .ended {
        dismissedEventIDs.insert(activity.attributes.eventID)
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
    guard activity == nil, isForeground, !dismissedEventIDs.contains(eventID) else { return }
    let relevant = state.mode != .countdown || display.prayerState?.isApproaching == true
    guard relevant else { return }
    request(state)
  }

  /// Explicitly following a prayer may start earlier than the automatic 15-minute window.
  func start(display: SalahDisplay) async {
    revision &+= 1
    let mine = revision
    guard
      let state = SalahActivityAttributes.ContentState(
        display: display, playbackSession: SharedValue<IOSPlaybackSession>.iosPlayback.load())
    else { return }
    await finishCurrent()
    guard mine == revision else { return }
    dismissedEventIDs.remove(SalahActivityAttributes.eventID(for: state))
    request(state)
  }

  func end() async {
    revision &+= 1
    await finishCurrent()
  }

  /// Clear references before waiting. A concurrent foreground refresh may create a new
  /// activity, so the old completion must not clear or end that new reference.
  private func finishCurrent() async {
    let current = Activity<SalahActivityAttributes>.activities
    activity = nil
    lastPublished = nil
    for activity in current {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  private func reconcileActivity(eventID: String) {
    if activity == nil {
      let existing = Activity<SalahActivityAttributes>.activities
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
