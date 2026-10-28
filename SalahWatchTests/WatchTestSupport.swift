import Foundation
import SalahAlerts
import SalahCore
import SalahWidgets
import WatchConnectivity

/// The test bundle compiles the app's sources and resources, so resources resolve to it.
final class WatchTestResources: NSObject {
  static func use() { AppResources.bundle = Bundle(for: WatchTestResources.self) }
}

/// The places and moments the design uses: London on Monday 12 October 2026 (Asr 3:37 PM,
/// Maghrib 6:14 PM, Isha 7:58 PM, in British Summer Time), Makkah, and the Kaaba itself.
enum WatchFixtures {
  static let london = PrayerLocation(
    latitude: 51.5072, longitude: -0.1276, timeZone: TimeZone(identifier: "Europe/London")!,
    countryCode: "GB", name: "London")
  static let makkah = PrayerLocation(
    latitude: 21.4225, longitude: 39.8262, timeZone: TimeZone(identifier: "Asia/Riyadh")!,
    countryCode: "SA", name: "Makkah")

  static func preferences(
    _ location: PrayerLocation = london, language: AppLanguage = .english,
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
    at text: String, preferences: IOSPreferences = preferences(), playback: SalahPlayback? = nil
  ) -> WatchPrayerPresentation {
    WatchPrayerPresentation(
      display: display(at: text, preferences: preferences, playback: playback))
  }

  /// An empty defaults suite of its own, so a test never sees another's records.
  static func defaults() -> UserDefaults {
    let suite = "io.github.salah-kit.Salah.watchOS.unit." + UUID().uuidString
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

  /// The context the iPhone sends for `preferences`.
  static func context(_ preferences: IOSPreferences, sentAt text: String) -> [String: Any] {
    try! WatchPreferencesMessage(preferences: preferences, sentAt: date(text)).context()
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

/// A watch session the test drives: what the iPhone delivered, and the requests the watch
/// sends it.
@MainActor
final class FakeWatchSession: WatchSession {
  private var state = WCSessionActivationState.activated
  /// How many times the activation state was read.
  private(set) var activationChecks = 0
  var activationState: WCSessionActivationState {
    get {
      activationChecks += 1
      return state
    }
    set { state = newValue }
  }
  var receivedApplicationContext: [String: Any] = [:]
  var isReachable = true
  var hasContentPending = false
  private(set) var requests = 0
  /// The iPhone's reply to the next request; `nil` sends none, as when it can't be reached.
  var reply: [String: Any]?

  func requestPreferences(reply handler: @escaping @Sendable ([String: Any]) -> Void) {
    requests += 1
    if let reply { handler(reply) }
  }
}

/// The settings mirror in a suite of the test's own, recording the reloads it asks for.
nonisolated final class RecordingReloads: @unchecked Sendable {
  private let lock = NSLock()
  private var kinds: [[String]] = []

  var reloads: [[String]] { lock.withLock { kinds } }

  func record(_ widgetKinds: [String]) { lock.withLock { kinds.append(widgetKinds) } }

  func value() -> SharedValue<SalahSettings> {
    let suite = "io.github.salah-kit.Salah.watchOS.unit." + UUID().uuidString
    return SharedValue(
      appGroup: suite, key: SalahWidgetConstants.settingsKey,
      reloadTimelines: { [self] in self.record($0) })
  }
}
