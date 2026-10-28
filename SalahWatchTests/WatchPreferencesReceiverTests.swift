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
    receiver.onPreferences = { recorder.received.append($0) }
    receiver.hasPreferences = { hasPreferences }
    return (receiver, recorder)
  }

  @MainActor
  final class Recorder {
    var received: [IOSPreferences] = []
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

    let withoutApp = FakeWatchSession()
    withoutApp.isCompanionAppInstalled = false
    receiver(session: withoutApp).0.requestIfNeeded()
    #expect(withoutApp.requests == 0)

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
