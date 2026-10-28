import Foundation
import SalahCore

/// The app's time: the real clock, or in Debug journeys one started at a chosen instant.
nonisolated struct WatchClock: Sendable {
  /// The instant the app shows at launch; `nil` follows the real clock.
  var start: Date?
  /// The real instant the app launched.
  var launch: Date
  /// Whether the clock stays at `start`.
  var frozen: Bool

  init(start: Date? = nil, launch: Date = Date(), frozen: Bool = false) {
    self.start = start
    self.launch = launch
    self.frozen = frozen && start != nil
  }

  /// The app's instant at the real instant `real`.
  func now(at real: Date = Date()) -> Date {
    guard let start else { return real }
    return frozen ? start : start.addingTimeInterval(real.timeIntervalSince(launch))
  }
}

/// Production uses the real clock, the app's own defaults and the session with the iPhone.
/// Test overrides exist only in Debug builds.
@MainActor
struct WatchLaunchConfiguration {
  let repository: any IOSPreferencesRepository
  /// What the app remembers besides the preferences: the last adhan it played and when the
  /// iPhone sent the preferences it has.
  let defaults: UserDefaults
  let clock: WatchClock
  let isTesting: Bool
  /// The page a journey opens on.
  let tab: WatchTab?
  /// A compass reading a journey starts with, as the simulator has no compass.
  let heading: WatchHeading?

  /// A configuration from its parts, for tests.
  init(
    repository: any IOSPreferencesRepository,
    defaults: UserDefaults = WatchLaunchConfiguration.emptyDefaults(), clock: WatchClock,
    isTesting: Bool = true, tab: WatchTab? = nil, heading: WatchHeading? = nil
  ) {
    self.repository = repository
    self.defaults = defaults
    self.clock = clock
    self.isTesting = isTesting
    self.tab = tab
    self.heading = heading
  }

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    #if DEBUG
      func value(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
      }
      if let suite = value("-salah.watch.testSuite"), !suite.isEmpty,
        suite.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }),
        let defaults = UserDefaults(
          suiteName: "io.github.salah-kit.Salah.watchOS.tests." + suite)
      {
        if value("-salah.watch.reset") == "true" {
          defaults.removePersistentDomain(
            forName: "io.github.salah-kit.Salah.watchOS.tests." + suite)
        }
        let testRepository = IOSUserDefaultsPreferencesRepository(defaults: defaults)
        // A fixture stands for preferences the iPhone sent; without one, the watch waits for
        // the iPhone as after a fresh install.
        if (try? testRepository.load()) == nil,
          let place = value("-salah.watch.fixture").flatMap(WatchFixturePlace.init(rawValue:))
        {
          var preferences = IOSPreferences()
          switch value("-salah.watch.language") {
          case "ar": preferences.language = .arabic
          case "en": preferences.language = .english
          default: break
          }
          preferences.location = place.location(arabic: preferences.language == .arabic)
          // Journeys hear nothing: the adhan plays, silently.
          preferences.playbackVolume = 0
          if value("-salah.watch.mute") == "true" { preferences.muteSounds = true }
          preferences.onboardingCompleted = true
          try? testRepository.save(preferences)
        }
        repository = testRepository
        self.defaults = defaults
        isTesting = true
        let start = value("-salah.watch.now").flatMap { try? Date($0, strategy: .iso8601) }
        clock = WatchClock(start: start, frozen: value("-salah.watch.frozen") == "true")
        tab = value("-salah.watch.tab").flatMap(WatchTab.init(rawValue:))
        heading =
          switch value("-salah.watch.heading") {
          case "none": .unavailable
          case "needsLocation": .needsLocation
          case "calibrating": .calibrating
          case let degrees?: Double(degrees).map { .ready(trueHeading: $0) }
          case nil: nil
          }
        return
      }
    #endif
    repository = IOSUserDefaultsPreferencesRepository(defaults: .standard)
    defaults = .standard
    clock = WatchClock()
    isTesting = false
    tab = nil
    heading = nil
  }

  /// A new suite of its own, so a test never sees another's records.
  static func emptyDefaults() -> UserDefaults {
    let suite = "io.github.salah-kit.Salah.watchOS.unit." + UUID().uuidString
    return UserDefaults(suiteName: suite) ?? UserDefaults()
  }
}

#if DEBUG
  /// The places the design's examples use, so journeys can start from a known city.
  nonisolated enum WatchFixturePlace: String, Sendable {
    case makkah, london, jakarta

    /// The place, named as Apple Maps names it in the app's language.
    func location(arabic: Bool = false) -> PrayerLocation {
      switch self {
      case .makkah:
        PrayerLocation(
          latitude: 21.4225, longitude: 39.8262, timeZone: zone("Asia/Riyadh"), countryCode: "SA",
          name: arabic ? "مكة المكرمة" : "Makkah")
      case .london:
        PrayerLocation(
          latitude: 51.5072, longitude: -0.1276, timeZone: zone("Europe/London"),
          countryCode: "GB", name: arabic ? "لندن" : "London")
      case .jakarta:
        PrayerLocation(
          latitude: -6.2088, longitude: 106.8456, timeZone: zone("Asia/Jakarta"),
          countryCode: "ID", name: arabic ? "جاكرتا" : "Jakarta")
      }
    }

    private func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier) ?? .gmt }
  }
#endif
