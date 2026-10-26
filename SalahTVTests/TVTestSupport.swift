import CoreLocation
import Foundation
import SalahAlerts
import SalahCore

/// The test bundle compiles the app's sources and resources, so resources resolve to it.
final class TVTestResources: NSObject {
  static func use() { AppResources.bundle = Bundle(for: TVTestResources.self) }
}

/// The places and moments the design uses: Makkah on Tuesday 2 June 2026, London in the
/// week of 12 October 2026, and Jakarta on Friday 16 October 2026.
enum TVFixtures {
  static let makkah = PrayerLocation(
    latitude: 21.4225, longitude: 39.8262, timeZone: TimeZone(identifier: "Asia/Riyadh")!,
    countryCode: "SA", name: "Makkah")
  static let london = PrayerLocation(
    latitude: 51.5072, longitude: -0.1276, timeZone: TimeZone(identifier: "Europe/London")!,
    countryCode: "GB", name: "London")
  static let jakarta = PrayerLocation(
    latitude: -6.2088, longitude: 106.8456, timeZone: TimeZone(identifier: "Asia/Jakarta")!,
    countryCode: "ID", name: "Jakarta")

  static func preferences(
    _ location: PrayerLocation = makkah, language: AppLanguage = .english,
    edit: (inout IOSPreferences) -> Void = { _ in }
  ) -> IOSPreferences {
    var preferences = IOSPreferences()
    preferences.location = location
    preferences.language = language
    preferences.onboardingCompleted = true
    edit(&preferences)
    return preferences
  }

  static func date(_ text: String) -> Date {
    // Fixture text is a constant ISO 8601 instant.
    try! Date(text, strategy: .iso8601)
  }

  static func display(
    at text: String, preferences: IOSPreferences = preferences(), playback: SalahPlayback? = nil
  ) -> SalahDisplay {
    let settings = preferences.mirror!
    return SalahDisplay(
      date: date(text), settings: settings, schedule: settings.schedule, playback: playback)
  }

  static func presentation(
    at text: String, preferences: IOSPreferences = preferences()
  ) -> TVPrayerPresentation {
    TVPrayerPresentation(
      display: display(at: text, preferences: preferences), preferences: preferences)
  }

  /// An empty defaults suite of its own, so a test never sees another's records.
  static func defaults() -> UserDefaults {
    let suite = "io.github.salah-kit.Salah.tvOS.unit." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  /// A repository in its own defaults suite, so a test never sees another's preferences.
  @MainActor
  static func repository(_ preferences: IOSPreferences? = nil)
    -> IOSUserDefaultsPreferencesRepository
  {
    let repository = IOSUserDefaultsPreferencesRepository(defaults: defaults())
    if let preferences { try? repository.save(preferences) }
    return repository
  }
}

/// Text as people read it: without the bidi isolates around times, and with ordinary
/// spaces for the narrow ones between a time and its day period.
func plain(_ text: String) -> String {
  text.replacingOccurrences(of: "\u{2068}", with: "")
    .replacingOccurrences(of: "\u{2069}", with: "")
    .replacingOccurrences(of: "\u{202F}", with: " ")
    .replacingOccurrences(of: "\u{00A0}", with: " ")
}

/// An alert clock the test moves by hand.
@MainActor
final class ManualAlertClock: AlertClock {
  var now: Date
  private(set) var wakeDate: Date?
  private var action: (@MainActor @Sendable () -> Void)?

  init(now: Date) { self.now = now }

  func wake(at date: Date?, perform action: @escaping @MainActor @Sendable () -> Void) {
    wakeDate = date
    self.action = date == nil ? nil : action
  }

  /// Moves to `date` and fires the armed wake-up if it's due.
  func advance(to date: Date) {
    now = date
    guard let wakeDate, wakeDate <= date, let action else { return }
    self.wakeDate = nil
    self.action = nil
    action()
  }
}

/// Records what the runtime asks of the screen saver.
@MainActor
final class RecordingIdleTimer: TVIdleTimerControlling {
  var keepsScreenOn = false {
    didSet { changes.append(keepsScreenOn) }
  }
  private(set) var changes: [Bool] = []

  init() {}
}

/// A location manager with permission that never asks Core Location for a fix, so a test
/// delivers the update itself.
nonisolated final class StubLocationManager: CLLocationManager {
  private(set) var locationRequests = 0

  override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }

  override func requestLocation() { locationRequests += 1 }
}
