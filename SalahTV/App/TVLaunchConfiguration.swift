import Foundation
import SalahCalculation
import SalahCore

/// The app's time: the real clock, or in Debug journeys one started at a chosen instant.
nonisolated struct TVClock: Sendable {
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

/// Production always uses the real clock and the app's own preferences. Test overrides
/// exist only in Debug builds.
@MainActor
struct TVLaunchConfiguration {
  let repository: any IOSPreferencesRepository
  /// What the app remembers across launches besides the preferences, such as the last adhan
  /// it played.
  let defaults: UserDefaults
  let clock: TVClock
  let isTesting: Bool
  /// The screen a journey opens on, such as the room display.
  let route: TVRoute?

  /// A configuration from its parts, for tests.
  init(
    repository: any IOSPreferencesRepository,
    defaults: UserDefaults = TVLaunchConfiguration.emptyDefaults(), clock: TVClock,
    isTesting: Bool = true, route: TVRoute? = nil
  ) {
    self.repository = repository
    self.defaults = defaults
    self.clock = clock
    self.isTesting = isTesting
    self.route = route
  }

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    #if DEBUG
      func value(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
      }
      if let suite = value("-salah.tv.testSuite"), !suite.isEmpty,
        suite.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }),
        let defaults = UserDefaults(suiteName: "io.github.salah-kit.Salah.tvOS.tests." + suite)
      {
        if value("-salah.tv.reset") == "true" {
          defaults.removePersistentDomain(forName: "io.github.salah-kit.Salah.tvOS.tests." + suite)
        }
        let testRepository = IOSUserDefaultsPreferencesRepository(defaults: defaults)
        if (try? testRepository.load()) == nil {
          var preferences = IOSPreferences()
          switch value("-salah.tv.language") {
          case "ar": preferences.language = .arabic
          case "en": preferences.language = .english
          default: break
          }
          if let place = value("-salah.tv.fixture").flatMap(TVFixturePlace.init(rawValue:)) {
            preferences.location = place.location(arabic: preferences.language == .arabic)
          }
          switch value("-salah.tv.appearance") {
          case "dark": preferences.appearance = .dark
          case "light": preferences.appearance = .light
          default: break
          }
          preferences.onboardingCompleted = value("-salah.tv.skipOnboarding") == "true"
          try? testRepository.save(preferences)
        }
        repository = testRepository
        self.defaults = defaults
        isTesting = true
        let start = value("-salah.tv.now").flatMap { try? Date($0, strategy: .iso8601) }
        clock = TVClock(start: start, frozen: value("-salah.tv.frozen") == "true")
        route = value("-salah.tv.route").flatMap(TVRoute.init(rawValue:))
        return
      }
    #endif
    repository = IOSUserDefaultsPreferencesRepository(defaults: .standard)
    defaults = .standard
    clock = TVClock()
    isTesting = false
    route = nil
  }

  /// A new suite of its own, so a test never sees another's records.
  static func emptyDefaults() -> UserDefaults {
    let suite = "io.github.salah-kit.Salah.tvOS.unit." + UUID().uuidString
    return UserDefaults(suiteName: suite) ?? UserDefaults()
  }
}

#if DEBUG
  /// The places the design's examples use, so journeys can start from a known city.
  nonisolated enum TVFixturePlace: String, Sendable {
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
