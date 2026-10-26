import CoreLocation
import Foundation
import SalahCore
import SalahTimes
import Testing

@Suite("Apple TV launch, storage and sound", .serialized)
@MainActor
struct TVServicesTests {
  init() { TVTestResources.use() }

  @Test func productionUsesTheRealClockAndItsOwnDefaults() {
    let configuration = TVLaunchConfiguration(arguments: ["SalahTV"])
    #expect(!configuration.isTesting)
    #expect(configuration.route == nil)
    #expect(configuration.clock.start == nil)
    #expect(abs(configuration.clock.now().timeIntervalSinceNow) < 1)
  }

  @Test func journeysStartFromAFixtureInTheirOwnSuite() throws {
    let suite = "unit-" + UUID().uuidString
    defer {
      UserDefaults(suiteName: "io.github.salah-kit.Salah.tvOS.tests." + suite)?
        .removePersistentDomain(forName: "io.github.salah-kit.Salah.tvOS.tests." + suite)
    }
    let configuration = TVLaunchConfiguration(arguments: [
      "SalahTV", "-salah.tv.testSuite", suite, "-salah.tv.reset", "true",
      "-salah.tv.fixture", "makkah", "-salah.tv.language", "ar", "-salah.tv.skipOnboarding",
      "true", "-salah.tv.now", "2026-06-02T13:19:00+03:00", "-salah.tv.frozen", "true",
      "-salah.tv.route", "room",
    ])
    #expect(configuration.isTesting)
    #expect(configuration.route == .roomDisplay)
    #expect(configuration.clock.now() == TVFixtures.date("2026-06-02T13:19:00+03:00"))
    let preferences = try #require(try configuration.repository.load())
    #expect(preferences.location?.name == "مكة المكرمة")
    #expect(preferences.language == .arabic)
    #expect(preferences.onboardingCompleted)
  }

  @Test func anUnsafeSuiteNameFallsBackToProduction() {
    let configuration = TVLaunchConfiguration(arguments: [
      "SalahTV", "-salah.tv.testSuite", "../escape",
    ])
    #expect(!configuration.isTesting)
  }

  @Test func aStartedClockRunsUnlessFrozen() {
    let launch = Date(timeIntervalSince1970: 1_000)
    let start = TVFixtures.date("2026-06-02T18:59:57+03:00")
    let running = TVClock(start: start, launch: launch)
    #expect(running.now(at: launch.addingTimeInterval(5)) == start.addingTimeInterval(5))
    let frozen = TVClock(start: start, launch: launch, frozen: true)
    #expect(frozen.now(at: launch.addingTimeInterval(5)) == start)
    // Without a start there's nothing to freeze.
    #expect(!TVClock(frozen: true).frozen)
  }

  @Test func preferencesSurviveAReloadOfTheStore() {
    let repository = TVFixtures.repository(TVFixtures.preferences())
    let store = IOSAppStore(repository: repository, now: { Date() })
    store.updatePreferences { $0.madhab = .hanafi }
    let reloaded = IOSAppStore(repository: repository, now: { Date() })
    #expect(reloaded.preferences.madhab == .hanafi)
    #expect(!reloaded.needsOnboarding)
  }

  @Test func aRequestWithoutAUsableFixEnds() {
    let manager = StubLocationManager()
    let location = TVLocationService(manager: manager)
    let makkah = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)
    let stale = CLLocation(
      coordinate: makkah, altitude: 0, horizontalAccuracy: 50, verticalAccuracy: -1,
      timestamp: Date().addingTimeInterval(-600))
    let inaccurate = CLLocation(
      coordinate: makkah, altitude: 0, horizontalAccuracy: 20_000, verticalAccuracy: -1,
      timestamp: Date())
    for (index, fix) in [stale, inaccurate].enumerated() {
      location.requestLocation()
      #expect(location.isLocating)
      #expect(manager.locationRequests == index + 1)
      location.locationManager(manager, didUpdateLocations: [fix])
      #expect(!location.isLocating)
      #expect(location.errorMessage == .noFix)
    }
  }

  @Test func theTVOffersOnlySoundsItCanPlay() {
    #expect(TVAudioService.sounds == [.fajrAdhan, .adhan, .softTone, .none])
  }

  @Test func playsAndStopsASound() {
    let audio = TVAudioService()
    var changes: [Bool] = []
    audio.onPlaybackChanged = { changes.append($0) }
    #expect(!audio.play(.none, volume: 0.5, locale: Locale(identifier: "en")))
    #expect(audio.play(.softTone, volume: 0.5, locale: Locale(identifier: "en")))
    #expect(audio.isPlaying)
    #expect(!audio.hasQueuedDua)
    audio.stop()
    #expect(!audio.isPlaying)
    #expect(changes == [true, false])
  }

  @Test func theBundledAdhansAreFound() {
    let files = TVAudioService.cachedFiles
    #expect(files.playbackURL(for: .adhan) != nil)
    #expect(files.playbackURL(for: .fajrAdhan) != nil)
  }
}
