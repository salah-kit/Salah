import Foundation
import UserNotifications

/// An in-memory notification center that logs every call in order. Adding a
/// request whose identifier is already pending replaces it, with or without a
/// trigger, as Apple documents. The real center also delivers an immediate
/// (nil-trigger) request at once; the fake leaves `delivered` to the test.
final class FakeNotificationCenter: PrayerAlertNotificationCenter {
  enum Call: Equatable {
    case authorizationStatus
    case requestAuthorization
    case pendingRequests
    case removePending([String])
    case deliveredNotifications
    case removeDelivered([String])
    case add(String)
  }

  struct AddFailure: Error {}

  /// Weak, as `UNUserNotificationCenter.delegate` is: the scheduler makes itself the
  /// delegate of the center it holds.
  weak var delegate: (any UNUserNotificationCenterDelegate)?
  var status: UNAuthorizationStatus = .authorized
  /// The status `requestAuthorization` leaves behind.
  var statusAfterRequest: UNAuthorizationStatus = .authorized
  var pending: [UNNotificationRequest] = []
  var delivered: [PrayerAlertDeliveredNotification] = []
  /// Every request `add` accepted, in order, including immediate (nil-trigger) ones.
  private(set) var added: [UNNotificationRequest] = []
  var failingIdentifiers: Set<String> = []
  private(set) var calls: [Call] = []

  func authorizationStatus() async -> UNAuthorizationStatus {
    calls.append(.authorizationStatus)
    return status
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    calls.append(.requestAuthorization)
    status = statusAfterRequest
    return status == .authorized
  }

  func pendingNotificationRequests() async -> [UNNotificationRequest] {
    calls.append(.pendingRequests)
    return pending
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    calls.append(.removePending(identifiers))
    pending.removeAll { identifiers.contains($0.identifier) }
  }

  func deliveredNotificationSummaries() async -> [PrayerAlertDeliveredNotification] {
    calls.append(.deliveredNotifications)
    return delivered
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    calls.append(.removeDelivered(identifiers))
    delivered.removeAll { identifiers.contains($0.identifier) }
  }

  func add(_ request: UNNotificationRequest) async throws {
    calls.append(.add(request.identifier))
    if failingIdentifiers.contains(request.identifier) { throw AddFailure() }
    added.append(request)
    pending.removeAll { $0.identifier == request.identifier }
    guard request.trigger != nil else { return }
    pending.append(request)
  }

  /// Requests added with a calendar trigger, in the order they were added.
  var scheduled: [UNNotificationRequest] { added.filter { $0.trigger != nil } }
  /// Requests added without a trigger: the immediate catch-up deliveries.
  var immediate: [UNNotificationRequest] { added.filter { $0.trigger == nil } }

  func forgetCalls() {
    calls = []
    added = []
  }
}

/// Records what the scheduler asks the audio player to do instead of playing it.
final class RecordingAudioPlayer: PrayerAlertAudioPlaying {
  struct Play {
    var request: AudioPlaybackRequest
    var followUp: AudioPlaybackRequest?
  }

  private(set) var plays: [Play] = []
  private(set) var stopCount = 0

  func play(_ request: AudioPlaybackRequest, followUp: AudioPlaybackRequest?) {
    plays.append(Play(request: request, followUp: followUp))
  }

  func stop() {
    stopCount += 1
  }
}

/// A clock that only moves when a test moves it. Timers the scheduler arms are
/// kept here instead of on a run loop.
final class ManualClock {
  var now: Date
  private(set) var timers: [Timer] = []

  init(_ now: Date) {
    self.now = now
  }

  var alertClock: PrayerAlertClock {
    PrayerAlertClock(
      now: { [unowned self] in now },
      scheduleTimer: { [unowned self] in timers.append($0) }
    )
  }
}

/// Lets the scheduler's fire-and-forget tasks run to completion. The fake center
/// never suspends, so a few turns of the main actor drain everything; the loop
/// stops once a full round adds no new calls.
@MainActor
func settle(_ center: FakeNotificationCenter) async {
  var quietRounds = 0
  var lastCount = -1
  for _ in 0..<200 where quietRounds < 5 {
    await Task.yield()
    quietRounds = center.calls.count == lastCount ? quietRounds + 1 : 0
    lastCount = center.calls.count
  }
}
