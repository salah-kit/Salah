import Foundation
import SalahCore
import SalahTimes
import Testing
import WatchConnectivity

@Suite("Preferences from the iPhone")
@MainActor
struct WatchPreferencesReceiverTests {
  private func receiver(
    session: FakeWatchSession? = FakeWatchSession(), hasPreferences: Bool = false
  ) -> (WatchPreferencesReceiver, Recorder) {
    let receiver = WatchPreferencesReceiver(session: session, defaults: WatchFixtures.defaults())
    let recorder = Recorder()
    receiver.onPreferences = { preferences in
      recorder.received.append(preferences)
      return recorder.keeps
    }
    receiver.hasPreferences = { hasPreferences }
    return (receiver, recorder)
  }

  @MainActor
  final class Recorder {
    var received: [IOSPreferences] = []
    /// Whether the watch manages to store what it receives.
    var keeps = true
  }

  @Test func keepsWhatTheIPhoneSent() {
    let (receiver, recorder) = receiver()
    let preferences = WatchFixtures.preferences()
    receiver.receive(WatchFixtures.context(preferences, sentAt: "2026-10-12T12:00:00Z"))
    #expect(recorder.received == [preferences.normalized()])
    #expect(receiver.lastRejection == nil)
  }

  /// A context read again at launch, or a reply to a request, never replaces newer preferences.
  @Test func ignoresAnOlderOrRepeatedSend() {
    let (receiver, recorder) = receiver()
    let newer = WatchFixtures.preferences { $0.madhab = .hanafi }
    receiver.receive(WatchFixtures.context(newer, sentAt: "2026-10-12T12:05:00Z"))
    receiver.receive(
      WatchFixtures.context(WatchFixtures.preferences(), sentAt: "2026-10-12T12:00:00Z"))
    receiver.receive(WatchFixtures.context(newer, sentAt: "2026-10-12T12:05:00Z"))
    #expect(recorder.received.map(\.madhab) == [.hanafi])
  }

  @Test func rejectsWhatItCantRead() {
    let (receiver, recorder) = receiver()
    receiver.receive([
      WatchPreferencesMessage.preferencesKey: Data("{".utf8),
      WatchPreferencesMessage.sentKey: Date(),
    ])
    #expect(recorder.received.isEmpty)
    #expect(receiver.lastRejection == .unreadable)
    // An iPhone that isn't set up replies with nothing to keep, which isn't an error.
    receiver.receive([:])
    #expect(receiver.lastRejection == .unreadable)
    #expect(recorder.received.isEmpty)
  }

  @Test func readsTheLastDeliveredContextOnceActive() {
    let session = FakeWatchSession()
    session.receivedApplicationContext = WatchFixtures.context(
      WatchFixtures.preferences(), sentAt: "2026-10-12T12:00:00Z")
    let (receiver, recorder) = receiver(session: session, hasPreferences: true)
    receiver.sessionActivated()
    #expect(recorder.received.count == 1)
    // Read again at the next activation, it's the same send.
    receiver.sessionActivated()
    #expect(recorder.received.count == 1)
    #expect(session.requests == 0)
  }

  @Test func asksTheIPhoneWhileTheWatchHasNoPreferences() {
    let session = FakeWatchSession()
    session.reply = WatchFixtures.context(
      WatchFixtures.preferences(), sentAt: "2026-10-12T12:00:00Z")
    let (receiver, _) = receiver(session: session)
    receiver.sessionActivated()
    #expect(session.requests == 1)
  }

  @Test func asksOnlyAReachableIPhoneWithSalah() {
    let unreachable = FakeWatchSession()
    unreachable.isReachable = false
    receiver(session: unreachable).0.requestIfNeeded()
    #expect(unreachable.requests == 0)

    let inactive = FakeWatchSession()
    inactive.activationState = .notActivated
    receiver(session: inactive).0.requestIfNeeded()
    #expect(inactive.requests == 0)

    let alreadySetUp = FakeWatchSession()
    receiver(session: alreadySetUp, hasPreferences: true).0.requestIfNeeded()
    #expect(alreadySetUp.requests == 0)
  }

  @Test func theReplyArrivesOnTheMainActor() async {
    let session = FakeWatchSession()
    session.reply = WatchFixtures.context(
      WatchFixtures.preferences(), sentAt: "2026-10-12T12:00:00Z")
    let (receiver, recorder) = receiver(session: session)
    receiver.requestIfNeeded()
    // The reply hops to the main actor before it's kept.
    for _ in 0..<50 where recorder.received.isEmpty {
      await Task.yield()
    }
    #expect(recorder.received.count == 1)
  }

  /// WatchConnectivity delivers only the iPhone's latest context, so a delivery is kept even
  /// when the iPhone's clock has gone back since it sent the watch's preferences.
  @Test func keepsADeliveryWhateverItsDate() {
    let (receiver, recorder) = receiver()
    receiver.receive(
      WatchFixtures.context(WatchFixtures.preferences(), sentAt: "2026-10-12T13:00:00Z"))
    let corrected = WatchFixtures.preferences { $0.madhab = .hanafi }
    receiver.receive(
      WatchFixtures.context(corrected, sentAt: "2026-10-12T12:00:00Z"), delivered: true)
    #expect(recorder.received.map(\.madhab) == [.shafi, .hanafi])
  }

  /// Preferences the watch couldn't store are read again, rather than counted as had.
  @Test func readsAgainWhatItCouldntStore() {
    let (receiver, recorder) = receiver()
    let context = WatchFixtures.context(WatchFixtures.preferences(), sentAt: "2026-10-12T12:00:00Z")
    recorder.keeps = false
    receiver.receive(context)
    recorder.keeps = true
    receiver.receive(context)
    #expect(recorder.received.count == 2)
    receiver.receive(context)
    #expect(recorder.received.count == 2)
  }

  /// WatchConnectivity calls the reply and error handlers on a queue of its own: neither may
  /// assume the main actor, which would stop the app.
  @Test func theHandlersRunOffTheMainActor() async {
    await withCheckedContinuation { (finished: CheckedContinuation<Void, Never>) in
      let handlers = WatchPreferencesReceiver.handlers { _ in finished.resume() }
      DispatchQueue.global().async {
        handlers.error(CocoaError(.featureUnsupported))
        handlers.reply([:])
      }
    }
  }

  /// A background launch to deliver a context waits for the session to activate first.
  @Test func backgroundDeliveryWaitsForActivation() async {
    let session = FakeWatchSession()
    session.activationState = .notActivated
    let (receiver, _) = receiver(session: session)
    Task {
      try? await Task.sleep(for: .milliseconds(300))
      session.activationState = .activated
    }
    await receiver.finishPendingContent()
    // It found the session inactive and checked again until it was active.
    #expect(session.activationChecks >= 2)
    #expect(session.activationState == .activated)
  }

  @Test func messagesRoundTrip() throws {
    let preferences = WatchFixtures.preferences(language: .arabic) { $0.muteSounds = true }
    let sent = WatchFixtures.date("2026-10-12T12:00:00Z")
    let context = try WatchPreferencesMessage(preferences: preferences, sentAt: sent).context()
    let read = try WatchPreferencesMessage(context: context)
    #expect(read.preferences == preferences.normalized())
    #expect(read.sentAt == sent)
    #expect(throws: WatchPreferencesMessage.ReadError.noPreferences) {
      try WatchPreferencesMessage(context: [:])
    }
  }
}
