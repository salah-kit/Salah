import Foundation
import SalahCore

/// Production always uses real time and durable preferences. Test overrides exist only in Debug.
@MainActor
struct IOSLaunchConfiguration {
  let repository: any IOSPreferencesRepository
  let now: @Sendable () -> Date
  let isTesting: Bool

  init(arguments: [String] = ProcessInfo.processInfo.arguments) {
    #if DEBUG
      func value(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1)
        else {
          return nil
        }
        return arguments[index + 1]
      }
      let requestedSuite = value("-salah.ios.testSuite")
      if let requestedSuite, !requestedSuite.isEmpty,
        requestedSuite.unicodeScalars.allSatisfy({
          CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }),
        let defaults = UserDefaults(
          suiteName: "io.github.salah-kit.Salah.iOS.tests." + requestedSuite)
      {
        let suite = "io.github.salah-kit.Salah.iOS.tests." + requestedSuite
        if value("-salah.ios.reset") == "true" { defaults.removePersistentDomain(forName: suite) }
        let testRepository = IOSUserDefaultsPreferencesRepository(defaults: defaults)
        if (try? testRepository.load()) == nil {
          var preferences = IOSPreferences()
          if value("-salah.ios.fixture") == "true" {
            preferences.location = PrayerLocation(
              latitude: 21.4225, longitude: 39.8262,
              timeZone: TimeZone(identifier: "Asia/Riyadh") ?? .gmt,
              countryCode: "SA", name: "Makkah")
            preferences.language = .english
            // The prepared design example has an Asr reminder ten minutes before.
            preferences.notifications[.asr]?.beforeEnabled = true
          }
          preferences.onboardingCompleted = value("-salah.ios.skipOnboarding") == "true"
          try? testRepository.save(preferences)
        }
        repository = testRepository
        isTesting = true
        if let text = value("-salah.ios.now"), let date = ISO8601DateFormatter().date(from: text) {
          now = { date }
        } else if value("-salah.ios.fixture") == "true" {
          let date = ISO8601DateFormatter().date(from: "2026-06-02T13:19:00+03:00") ?? Date()
          now = { date }
        } else {
          now = { Date() }
        }
        return
      }
    #endif
    repository = IOSSharedPreferencesRepository()
    now = { Date() }
    isTesting = false
  }
}
