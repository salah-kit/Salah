import Foundation
import Observation
@preconcurrency import WatchConnectivity

/// The WatchConnectivity session the sync uses: `WCSession` on an iPhone, or a test's double.
@MainActor
protocol IOSWatchSession: AnyObject {
  var activationState: WCSessionActivationState { get }
  var isPaired: Bool { get }
  var isWatchAppInstalled: Bool { get }
  /// The last context this iPhone sent.
  var applicationContext: [String: Any] { get }
  func updateApplicationContext(_ context: [String: Any]) throws
}

extension WCSession: IOSWatchSession {}

/// Sends the preferences to the watch app, which keeps its own copy.
///
/// It sends them as the session's application context whenever they change, which the system
/// delivers when the watch app next runs, and answers the watch app's request for them, for
/// which iOS wakes Salah in the background. Before setup there's no location, so nothing is
/// sent: the watch keeps what it has.
@MainActor @Observable
final class IOSWatchSync {
  /// Why the last send failed, such as a context the session refused.
  private(set) var errorMessage: String?

  @ObservationIgnored private let session: (any IOSWatchSession)?
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private var preferences: IOSPreferences?
  @ObservationIgnored private var receiver: Receiver?

  /// The iPhone's own session, activated now so a request from the watch can wake Salah.
  convenience init() {
    guard WCSession.isSupported() else {
      self.init(session: nil)
      return
    }
    let session = WCSession.default
    self.init(session: session)
    let receiver = Receiver(sync: self)
    self.receiver = receiver
    session.delegate = receiver
    session.activate()
  }

  init(session: (any IOSWatchSession)?, now: @escaping @Sendable () -> Date = { Date() }) {
    self.session = session
    self.now = now
  }

  /// Sends `preferences` unless the watch already has them. Without a location there's
  /// nothing to send.
  func send(_ preferences: IOSPreferences) {
    guard preferences.location != nil else { return }
    self.preferences = preferences
    deliver(force: false)
  }

  /// The session activated, or the watch app was installed or removed: deliver what's
  /// pending. A newly installed watch app gets the preferences again, under a new date,
  /// because it starts with none.
  func sessionChanged(watchAppInstalled: Bool) {
    deliver(force: watchAppInstalled)
  }

  /// The reply to the watch's request: the current preferences, or an empty reply before
  /// setup.
  func reply() -> [String: Any] {
    guard let preferences else { return [:] }
    return (try? WatchPreferencesMessage(preferences: preferences, sentAt: now()).context()) ?? [:]
  }

  private func deliver(force: Bool) {
    guard let session, let preferences, session.activationState == .activated,
      session.isPaired, session.isWatchAppInstalled
    else { return }
    if !force, let sent = try? WatchPreferencesMessage(context: session.applicationContext),
      sent.preferences == preferences.normalized()
    {
      return
    }
    do {
      try session.updateApplicationContext(
        WatchPreferencesMessage(preferences: preferences, sentAt: now()).context())
      errorMessage = nil
    } catch {
      errorMessage = String(describing: error)
    }
  }

  /// The session's delegate. WatchConnectivity calls it on a queue of its own, so it hands
  /// each event to the sync on the main actor.
  private final class Receiver: NSObject, WCSessionDelegate {
    private weak var sync: IOSWatchSync?
    private var installed: Bool?

    init(sync: IOSWatchSync) { self.sync = sync }

    nonisolated func session(
      _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
      error: (any Error)?
    ) {
      Task { @MainActor in self.watchStateChanged(session) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
      Task { @MainActor in self.watchStateChanged(session) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The person switched to another watch: activate for it.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
      session.activate()
    }

    nonisolated func session(
      _ session: WCSession, didReceiveMessage message: [String: Any],
      replyHandler: @escaping ([String: Any]) -> Void
    ) {
      guard message[WatchPreferencesMessage.requestKey] != nil else {
        replyHandler([:])
        return
      }
      let reply = UncheckedReply(replyHandler)
      Task { @MainActor in reply.send(self.sync?.reply() ?? [:]) }
    }

    @MainActor private func watchStateChanged(_ session: WCSession) {
      let isInstalled = session.isPaired && session.isWatchAppInstalled
      let newlyInstalled = isInstalled && installed == false
      installed = isInstalled
      sync?.sessionChanged(watchAppInstalled: newlyInstalled)
    }
  }
}

/// WatchConnectivity's reply handler, carried to the main actor and back. The session lets
/// it be called from any thread.
nonisolated private struct UncheckedReply: @unchecked Sendable {
  let handler: ([String: Any]) -> Void
  init(_ handler: @escaping ([String: Any]) -> Void) { self.handler = handler }
  func send(_ reply: [String: Any]) { handler(reply) }
}
