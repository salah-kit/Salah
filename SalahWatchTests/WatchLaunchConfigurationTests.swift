import Foundation
import SalahCore
import Testing

@Suite("The watch app's launch configuration")
@MainActor
struct WatchLaunchConfigurationTests {
  @Test func journeysStartFromAFixtureInTheirOwnSuite() throws {
    let suite = "launch-" + UUID().uuidString
    let configuration = WatchLaunchConfiguration(arguments: [
      "-salah.watch.testSuite", suite, "-salah.watch.reset", "true",
      "-salah.watch.fixture", "london", "-salah.watch.language", "ar",
      "-salah.watch.now", "2026-10-12T12:19:00Z", "-salah.watch.frozen", "true",
      "-salah.watch.tab", "qibla", "-salah.watch.heading", "93",
    ])
    let preferences = try #require(try configuration.repository.load())
    #expect(preferences.location?.name == "لندن")
    #expect(preferences.language == .arabic)
    #expect(preferences.playbackVolume == 0)
    #expect(configuration.isTesting)
    #expect(configuration.clock.frozen)
    #expect(configuration.clock.now() == WatchFixtures.date("2026-10-12T12:19:00Z"))
    #expect(configuration.tab == .qibla)
    #expect(configuration.heading == .ready(trueHeading: 93))
  }

  /// Without a fixture the watch waits for the iPhone, as after a fresh install.
  @Test func journeysWithoutAFixtureHaveNoPreferences() throws {
    let configuration = WatchLaunchConfiguration(arguments: [
      "-salah.watch.testSuite", "launch-" + UUID().uuidString, "-salah.watch.reset", "true",
    ])
    #expect(try configuration.repository.load() == nil)
    #expect(configuration.heading == nil)
  }

  @Test func productionIgnoresUnsafeSuites() {
    let configuration = WatchLaunchConfiguration(arguments: [
      "-salah.watch.testSuite", "../escape",
    ])
    #expect(!configuration.isTesting)
    #expect(configuration.clock.start == nil)
    #expect(configuration.tab == nil)
  }

  @Test func aRunningClockKeepsTime() {
    let start = WatchFixtures.date("2026-10-12T12:19:00Z")
    let launch = Date(timeIntervalSince1970: 1_000)
    let clock = WatchClock(start: start, launch: launch)
    #expect(clock.now(at: launch.addingTimeInterval(90)) == start.addingTimeInterval(90))
    #expect(WatchClock(start: start, launch: launch, frozen: true).now(at: .distantFuture) == start)
  }
}
