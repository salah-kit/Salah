import Foundation
import SalahAlerts
import UserNotifications

/// An instant that tests set by hand and any thread can read: the manual clock's time,
/// which the fake center also stamps its deliveries with.
nonisolated final class TestInstant: @unchecked Sendable {
  // @unchecked: every access to `stored` holds `lock`.
  private let lock = NSLock()
  private var stored: Date

  init(_ date: Date) {
    stored = date
  }

  /// The current instant.
  var value: Date {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}

/// An alert clock that only moves when a test moves it, and keeps the wake-ups the
/// engine asks for instead of arming timers.
final class ManualAlertClock: AlertClock {
  /// The clock's time, shared with the fake center.
  let instant: TestInstant
  /// Every wake-up the engine asked for, in order; `nil` disarms.
  private(set) var wakes: [Date?] = []
  private var action: (@MainActor @Sendable () -> Void)?

  init(_ now: Date) {
    instant = TestInstant(now)
  }

  /// The current instant. Setting it moves time without firing the wake-up, as a sleep
  /// or a clock change does.
  var now: Date {
    get { instant.value }
    set { instant.value = newValue }
  }

  /// The wake-up armed last, if any.
  var armed: Date? { wakes.last ?? nil }

  /// Keeps the wake-up, replacing the one armed before.
  func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void) {
    wakes.append(date)
    self.action = date == nil ? nil : action
  }

  /// Moves the clock to the armed instant and fires the wake-up, as a timer would.
  func fire() {
    guard let armed, let action else { return }
    now = armed
    self.action = nil
    action()
  }
}

/// An in-memory notification center that logs every call in order.
///
/// It holds its delegate weakly, as `UNUserNotificationCenter` does. Adding a request
/// whose identifier is pending replaces it; a request without a trigger is delivered at
/// once, dated at the shared instant, and never becomes pending. Pending requests stay
/// pending until a test drops them: the fake never fires a trigger itself.
///
/// A class with a lock rather than an actor: `UNNotificationRequest` isn't `Sendable`,
/// so an actor couldn't take or return it across the protocol's nonisolated requirements.
nonisolated final class FakeNotificationCenter: PrayerNotificationCenter, @unchecked Sendable {
  // @unchecked: every stored property is read and written while holding `lock`, and the
  // requests it holds are immutable once created.

  /// One call the coordinator or its scheduler made.
  enum Call: Equatable, Sendable {
    case authorizationStatus
    case requestAuthorization
    case pendingRequests
    case add(String)
    case removePending([String])
    case deliveredNotifications
    case removeDelivered([String])
  }

  private let lock = NSLock()
  private let time: TestInstant?
  private weak var storedDelegate: (any UNUserNotificationCenterDelegate)?
  private var storedStatus: UNAuthorizationStatus
  private var storedStatusAfterRequest: UNAuthorizationStatus
  private var pendingRequests: [UNNotificationRequest]
  private var deliveredRecords: [DeliveredNotificationRecord] = []
  private var postedRequests: [UNNotificationRequest] = []
  private var log: [Call] = []

  /// A center with `status`, which `requestAuthorization` turns into `statusAfterRequest`.
  /// Immediate deliveries are dated at `time`, or now without one.
  init(
    status: UNAuthorizationStatus = .authorized,
    statusAfterRequest: UNAuthorizationStatus = .authorized,
    time: TestInstant? = nil, pending: [UNNotificationRequest] = []
  ) {
    storedStatus = status
    storedStatusAfterRequest = statusAfterRequest
    self.time = time
    pendingRequests = pending
  }

  /// The center's delegate, held weakly.
  var delegate: (any UNUserNotificationCenterDelegate)? {
    get { lock.withLock { storedDelegate } }
    set { lock.withLock { storedDelegate = newValue } }
  }

  /// The app's authorization.
  var status: UNAuthorizationStatus {
    get { lock.withLock { storedStatus } }
    set { lock.withLock { storedStatus = newValue } }
  }

  /// The pending requests, in the order they were added.
  var pending: [UNNotificationRequest] { lock.withLock { pendingRequests } }
  /// The delivered notifications.
  var delivered: [DeliveredNotificationRecord] { lock.withLock { deliveredRecords } }
  /// The immediate (nil-trigger) requests, in the order they were posted.
  var posted: [UNNotificationRequest] { lock.withLock { postedRequests } }
  /// Every call, in order.
  var calls: [Call] { lock.withLock { log } }

  /// The pending request with `identifier`, if any.
  func pendingRequest(_ identifier: String) -> UNNotificationRequest? {
    pending.first { $0.identifier == identifier }
  }

  /// Forgets the calls and the posted requests so far.
  func forgetCalls() {
    lock.withLock {
      log = []
      postedRequests = []
    }
  }

  /// Removes a pending request without a call, as when the system fires or loses it.
  func dropPending(_ identifier: String) {
    lock.withLock { pendingRequests.removeAll { $0.identifier == identifier } }
  }

  // MARK: PrayerNotificationCenter

  func authorizationStatus() async -> UNAuthorizationStatus {
    lock.withLock {
      log.append(.authorizationStatus)
      return storedStatus
    }
  }

  func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
    lock.withLock {
      log.append(.requestAuthorization)
      storedStatus = storedStatusAfterRequest
      return storedStatus == .authorized
    }
  }

  func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
    lock.withLock {
      log.append(.pendingRequests)
      return pendingRequests
    }
  }

  func add(_ request: UNNotificationRequest) async throws {
    let date = time?.value ?? Date()
    lock.withLock {
      log.append(.add(request.identifier))
      pendingRequests.removeAll { $0.identifier == request.identifier }
      if request.trigger == nil {
        postedRequests.append(request)
        deliveredRecords.removeAll { $0.identifier == request.identifier }
        deliveredRecords.append(
          DeliveredNotificationRecord(identifier: request.identifier, date: date))
      } else {
        pendingRequests.append(request)
      }
    }
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
    lock.withLock {
      log.append(.removePending(identifiers))
      pendingRequests.removeAll { identifiers.contains($0.identifier) }
    }
  }

  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] {
    lock.withLock {
      log.append(.deliveredNotifications)
      return deliveredRecords
    }
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {
    lock.withLock {
      log.append(.removeDelivered(identifiers))
      deliveredRecords.removeAll { identifiers.contains($0.identifier) }
    }
  }
}

/// Records what the coordinator asks the audio player to do instead of playing it.
final class RecordingAudioPlayer: PrayerAlertAudioPlaying {
  /// One `play` call.
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

extension AudioPlaybackResource {
  /// The file a resource plays, or `nil` for in-memory data.
  var url: URL? {
    if case .url(let url) = self { return url }
    return nil
  }
}
