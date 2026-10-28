import Foundation
@preconcurrency import WatchConnectivity

/// The WatchConnectivity session the receiver uses: `WCSession` on the watch, or a test's
/// double.
@MainActor
protocol WatchSession: AnyObject {
  var activationState: WCSessionActivationState { get }
  /// The last context the iPhone sent that this watch received.
  var receivedApplicationContext: [String: Any] { get }
  var isCompanionAppInstalled: Bool { get }
  var isReachable: Bool { get }
  var hasContentPending: Bool { get }
  /// Asks the iPhone app for the preferences. `reply` gets its answer on a queue of the
  /// session's; nothing comes back when the iPhone can't be reached after all.
  func requestPreferences(reply: @escaping @Sendable ([String: Any]) -> Void)
}

extension WCSession: WatchSession {
  func requestPreferences(reply: @escaping @Sendable ([String: Any]) -> Void) {
    // Unreachable after all: the context arrives when the iPhone app next runs.
    sendMessage(
      [WatchPreferencesMessage.requestKey: true], replyHandler: { reply($0) },
      errorHandler: { _ in })
  }
}

/// Receives the preferences the iPhone app sends and keeps the latest.
///
/// A context the iPhone sends is delivered when the watch app next runs, in the background if
/// need be. Once the session is active the receiver reads the last delivered context again,
/// in case a delivery was missed, and asks a reachable iPhone for the preferences while the
/// watch has none. Each is kept only when the iPhone sent it after the preferences the watch
/// already has, so an older send never replaces newer ones.
@MainActor
final class WatchPreferencesReceiver {
  /// The defaults key of the instant the iPhone sent the preferences the watch has.
  static let sentKey = "salah.watch.preferences.sentAt"

  /// Called with preferences newer than the watch's.
  var onPreferences: ((IOSPreferences) -> Void)?
  /// Whether the watch has preferences, so it doesn't ask the iPhone for them again.
  var hasPreferences: () -> Bool = { false }
  /// Why the last context or reply couldn't be used, for diagnostics and tests.
  private(set) var lastRejection: WatchPreferencesMessage.ReadError?

  private let defaults: UserDefaults
  private let session: (any WatchSession)?
  private var delegate: Delegate?

  /// The watch's own session, activated now so a context delivered in the background reaches
  /// the receiver.
  convenience init(defaults: UserDefaults) {
    guard WCSession.isSupported() else {
      self.init(session: nil, defaults: defaults)
      return
    }
    let session = WCSession.default
    self.init(session: session, defaults: defaults)
    let delegate = Delegate(receiver: self)
    self.delegate = delegate
    session.delegate = delegate
    session.activate()
  }

  init(session: (any WatchSession)?, defaults: UserDefaults) {
    self.session = session
    self.defaults = defaults
  }

  /// A context the iPhone delivered, or a reply to the watch's request.
  func receive(_ context: [String: Any]) {
    let message: WatchPreferencesMessage
    do {
      message = try WatchPreferencesMessage(context: context)
    } catch {
      // An empty reply comes from an iPhone that isn't set up: nothing to keep.
      if error != .noPreferences { lastRejection = error }
      return
    }
    lastRejection = nil
    if let sent = defaults.object(forKey: Self.sentKey) as? Date, message.sentAt <= sent {
      return
    }
    defaults.set(message.sentAt, forKey: Self.sentKey)
    onPreferences?(message.preferences)
  }

  /// The session is active: read the last delivered context again, and ask the iPhone while
  /// the watch has no preferences. Also called when Salah becomes active.
  func sessionActivated() {
    guard let session, session.activationState == .activated else { return }
    let context = session.receivedApplicationContext
    if !context.isEmpty { receive(context) }
    requestIfNeeded()
  }

  /// Asks a reachable iPhone for the preferences, while the watch has none. iOS wakes Salah on
  /// the iPhone to answer.
  func requestIfNeeded() {
    guard let session, session.activationState == .activated, !hasPreferences(),
      session.isCompanionAppInstalled, session.isReachable
    else { return }
    session.requestPreferences { [weak self] context in
      let reply = UncheckedContext(context)
      Task { @MainActor in self?.receive(reply.value) }
    }
  }

  /// Waits until WatchConnectivity has delivered what it holds for Salah, for the system's
  /// background task that woke the app to receive it.
  func finishPendingContent() async {
    guard let session else { return }
    var waited = 0
    while session.hasContentPending, waited < 50 {
      waited += 1
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
    }
  }

  /// The session's delegate. WatchConnectivity calls it on a queue of its own, so it hands each
  /// event to the receiver on the main actor.
  private final class Delegate: NSObject, WCSessionDelegate {
    private weak var receiver: WatchPreferencesReceiver?

    init(receiver: WatchPreferencesReceiver) { self.receiver = receiver }

    nonisolated func session(
      _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
      error: (any Error)?
    ) {
      Task { @MainActor in self.receiver?.sessionActivated() }
    }

    nonisolated func session(
      _ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]
    ) {
      let context = UncheckedContext(applicationContext)
      Task { @MainActor in self.receiver?.receive(context.value) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
      Task { @MainActor in self.receiver?.requestIfNeeded() }
    }
  }
}

/// A received context, carried to the main actor. It holds only property-list values.
nonisolated private struct UncheckedContext: @unchecked Sendable {
  let value: [String: Any]
  init(_ value: [String: Any]) { self.value = value }
}
