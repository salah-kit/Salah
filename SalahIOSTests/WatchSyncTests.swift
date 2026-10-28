import Foundation
import SalahCore
import SalahTimes
import Testing
import WatchConnectivity

@Suite("Preferences sent to the watch") @MainActor
struct WatchSyncTests {
  private static let makkah = PrayerLocation(
    latitude: 21.4225, longitude: 39.8262, timeZone: TimeZone(identifier: "Asia/Riyadh")!,
    countryCode: "SA", name: "Makkah")

  private static func preferences(_ edit: (inout IOSPreferences) -> Void = { _ in })
    -> IOSPreferences
  {
    var preferences = IOSPreferences()
    preferences.location = makkah
    edit(&preferences)
    return preferences
  }

  /// A session the test controls, which records each context the iPhone sends.
  @MainActor
  final class FakeSession: IOSWatchSession {
    var activationState: WCSessionActivationState = .activated
    var isPaired = true
    var isWatchAppInstalled = true
    private(set) var applicationContext: [String: Any] = [:]
    private(set) var sent: [WatchPreferencesMessage] = []
    var failure: (any Error)?

    func updateApplicationContext(_ context: [String: Any]) throws {
      if let failure { throw failure }
      applicationContext = context
      sent.append(try WatchPreferencesMessage(context: context))
    }
  }

  private let sentAt = Date(timeIntervalSince1970: 1_791_000_000)

  @Test func sendsThePreferencesOnceTheyHaveAPlace() {
    let session = FakeSession()
    let sync = IOSWatchSync(session: session, now: { [sentAt] in sentAt })
    sync.send(IOSPreferences())
    #expect(session.sent.isEmpty)
    sync.send(Self.preferences())
    #expect(session.sent.map(\.preferences) == [Self.preferences().normalized()])
    #expect(session.sent.first?.sentAt == sentAt)
  }

  @Test func doesntSendWhatTheWatchAlreadyHas() {
    let session = FakeSession()
    let sync = IOSWatchSync(session: session)
    sync.send(Self.preferences())
    sync.send(Self.preferences())
    #expect(session.sent.count == 1)
    sync.send(Self.preferences { $0.madhab = .hanafi })
    #expect(session.sent.map(\.preferences.madhab) == [.shafi, .hanafi])
  }

  @Test func waitsForAPairedWatchWithSalah() {
    let session = FakeSession()
    session.activationState = .notActivated
    session.isWatchAppInstalled = false
    let sync = IOSWatchSync(session: session)
    sync.send(Self.preferences())
    #expect(session.sent.isEmpty)
    // Activation alone isn't enough without the watch app.
    session.activationState = .activated
    sync.sessionChanged(watchAppInstalled: false)
    #expect(session.sent.isEmpty)
    session.isWatchAppInstalled = true
    sync.sessionChanged(watchAppInstalled: true)
    #expect(session.sent.count == 1)
  }

  /// A newly installed watch app starts with nothing, so it gets the same preferences again.
  @Test func sendsAgainToANewlyInstalledWatchApp() {
    let session = FakeSession()
    let sync = IOSWatchSync(session: session)
    sync.send(Self.preferences())
    sync.sessionChanged(watchAppInstalled: false)
    #expect(session.sent.count == 1)
    sync.sessionChanged(watchAppInstalled: true)
    #expect(session.sent.count == 2)
  }

  @Test func repliesToTheWatchsRequest() throws {
    let sync = IOSWatchSync(session: nil, now: { [sentAt] in sentAt })
    #expect(sync.reply().isEmpty)
    sync.send(Self.preferences())
    let reply = try WatchPreferencesMessage(context: sync.reply())
    #expect(reply.preferences == Self.preferences().normalized())
    #expect(reply.sentAt == sentAt)
  }

  @Test func saysWhyASendFailed() {
    let session = FakeSession()
    session.failure = WCError(.payloadTooLarge)
    let sync = IOSWatchSync(session: session)
    sync.send(Self.preferences())
    #expect(sync.errorMessage != nil)
    session.failure = nil
    sync.send(Self.preferences { $0.muteSounds = true })
    #expect(sync.errorMessage == nil)
  }
}
