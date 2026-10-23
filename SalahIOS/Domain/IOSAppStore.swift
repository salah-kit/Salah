import Foundation
import Observation
import SalahCore
import SalahTimes

nonisolated enum IOSTab: String, CaseIterable, Sendable {
  case today, times, qibla, settings
}

nonisolated enum IOSOnboardingStep: Int, CaseIterable, Sendable {
  case welcome, location, notifications, calculation, ready
}

nonisolated enum IOSPermissionStatus: String, Sendable {
  case notDetermined, authorized, denied, restricted
}

nonisolated enum IOSSettingsDestination: String, CaseIterable, Hashable, Sendable {
  case location, calculation, madhab, highLatitude, adjustments, hijri
  case alerts, sound, appearance, language, about
}

/// The application state. Feature views depend on this value boundary, never platform globals.
@MainActor @Observable
final class IOSAppStore {
  private(set) var preferences: IOSPreferences
  private(set) var settings: SalahSettings?
  private(set) var schedule: PrayerSchedule?
  private(set) var now: Date
  private(set) var playback: SalahPlayback?
  private(set) var playbackHasQueuedDua = false
  private(set) var persistenceFailed = false
  private(set) var notificationPermission: IOSPermissionStatus = .notDetermined
  private(set) var locationPermission: IOSPermissionStatus = .notDetermined
  var selectedTab: IOSTab = .today
  var selectedDay: CivilDay
  var onboardingStep: IOSOnboardingStep = .welcome
  var settingsPath: [IOSSettingsDestination] = []

  /// Compact navigation and the regular-width sidebar select the same category.
  var selectedSettingsDestination: IOSSettingsDestination? {
    get { settingsPath.first }
    set { settingsPath = newValue.map { [$0] } ?? [] }
  }

  /// An empty detail column starts at Calculation; an incoming route keeps its selection.
  func prepareSettingsForRegularWidth() {
    guard settingsPath.isEmpty else { return }
    settingsPath = [.calculation]
  }
  /// Composition connects side effects after constructing the store and platform services.
  @ObservationIgnored var onPreferencesChanged: (@MainActor (IOSPreferences) -> Void)?
  @ObservationIgnored var onStopPlayback: (@MainActor () -> Void)?
  @ObservationIgnored var onPlayPrayer: (@MainActor (PrayerEvent) -> Void)?

  @ObservationIgnored private let repository: any IOSPreferencesRepository
  @ObservationIgnored private let clock: @Sendable () -> Date
  @ObservationIgnored private var unsavedBase: IOSPreferences?

  init(
    repository: any IOSPreferencesRepository = IOSAppGroupPreferencesRepository(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.repository = repository
    clock = now
    let current = now()
    self.now = current
    let loaded: IOSPreferences
    do {
      loaded = try repository.load()?.normalized() ?? IOSPreferences()
    } catch {
      loaded = IOSPreferences()
      persistenceFailed = true
    }
    preferences = loaded
    settings = loaded.mirror
    schedule = loaded.mirror?.schedule
    selectedDay = CivilDay(containing: current, in: loaded.location?.timeZone ?? .current)
  }

  var needsOnboarding: Bool { !preferences.onboardingCompleted }
  var locale: Locale { preferences.language.locale }
  var names: PrayerNames { PrayerNames(locale: locale) }
  var isArabic: Bool { locale.language.languageCode?.identifier == "ar" }
  var timeZone: TimeZone { preferences.location?.timeZone ?? .current }
  var today: CivilDay { CivilDay(containing: now, in: timeZone) }

  var display: SalahDisplay? {
    guard let settings, let schedule else { return nil }
    return SalahDisplay(date: now, settings: settings, schedule: schedule, playback: playback)
  }

  var selectedDayAvailability: PrayerDayAvailability? { schedule?.day(selectedDay) }
  var weekDays: [CivilDay] {
    let mondayOffset = (selectedDay.weekday + 5) % 7
    let first = selectedDay.adding(days: -mondayOffset)
    return (0..<7).map { first.adding(days: $0) }
  }

  var qiblaBearing: Double? {
    guard let location = preferences.location else { return nil }
    return Qibla.direction(
      from: Coordinates(latitude: location.latitude, longitude: location.longitude))
  }

  var qiblaDistanceKilometers: Double? {
    guard let location = preferences.location else { return nil }
    let first = location.latitude * .pi / 180
    let target = Qibla.kaaba.latitude * .pi / 180
    let latitudeDelta = target - first
    let longitudeDelta = (Qibla.kaaba.longitude - location.longitude) * .pi / 180
    let a =
      pow(sin(latitudeDelta / 2), 2)
      + cos(first) * cos(target) * pow(sin(longitudeDelta / 2), 2)
    return 6_371.0088 * 2 * atan2(sqrt(max(0, min(1, a))), sqrt(max(0, 1 - a)))
  }

  func updatePreferences(_ change: (inout IOSPreferences) -> Void) {
    var changed = preferences
    change(&changed)
    changed = changed.normalized()
    guard changed != preferences else { return }
    let previousToday = today
    let wasToday = selectedDay == previousToday
    let base = unsavedBase ?? preferences
    do {
      preferences = try repository.update { $0.mergeChanges(from: base, to: changed) }
      unsavedBase = nil
      persistenceFailed = false
    } catch {
      // Keep the user's active edits usable, while surfacing that they were not saved.
      preferences = changed
      unsavedBase = base
      persistenceFailed = true
    }
    settings = preferences.mirror
    schedule = settings?.schedule
    if wasToday { selectedDay = today }
    onPreferencesChanged?(preferences)
  }

  /// The caller controls automatic mode separately, so choosing a city always stops following.
  func select(location: PrayerLocation) {
    updatePreferences {
      let candidates = [location] + ($0.location.map { [$0] } ?? []) + $0.recentLocations
      var recent: [PrayerLocation] = []
      for candidate in candidates {
        guard
          !recent.contains(where: {
            abs($0.latitude - candidate.latitude) < 0.0001
              && abs($0.longitude - candidate.longitude) < 0.0001
          })
        else { continue }
        recent.append(candidate)
      }
      $0.recentLocations = Array(recent.prefix(5))
      $0.location = location
      $0.useCurrentLocation = false
    }
  }

  func completeOnboarding() {
    guard preferences.location != nil else {
      onboardingStep = .location
      return
    }
    updatePreferences { $0.onboardingCompleted = true }
    selectedTab = .today
    selectedDay = today
  }

  func tick(at date: Date? = nil) {
    let previous = today
    let wasToday = selectedDay == previous
    now = date ?? clock()
    if wasToday { selectedDay = today }
  }

  /// Called when a scene becomes active or its clock/time-zone context changes.
  func refresh() {
    tick()
    let wasToday = selectedDay == today
    do {
      if let base = unsavedBase {
        let pending = preferences
        preferences = try repository.update { $0.mergeChanges(from: base, to: pending) }
        unsavedBase = nil
      }
      if let latest = try repository.load() {
        preferences = latest.normalized()
        persistenceFailed = false
      }
    } catch {
      persistenceFailed = true
    }
    settings = preferences.mirror
    schedule = settings?.schedule
    if wasToday { selectedDay = today }
  }

  func toggleAlert(for event: PrayerEvent) {
    updatePreferences {
      if event.observance == .jumuah, $0.jumuahOverrideEnabled {
        $0.jumuahAlerts.atTime.toggle()
      } else {
        var value = $0.alerts(for: event.kind)
        value.atTime.toggle()
        $0.notifications[event.kind] = value
      }
    }
  }

  /// Friday inherits Dhuhr until the first explicit override. Turning that override
  /// off keeps its edited values for the next time it is enabled.
  func setJumuahOverrideEnabled(_ enabled: Bool) {
    updatePreferences {
      if enabled, !$0.jumuahOverrideSeeded {
        $0.jumuahAlerts = $0.alerts(for: .dhuhr)
        $0.jumuahOverrideSeeded = true
      }
      $0.jumuahOverrideEnabled = enabled
    }
  }

  func setPlayback(_ playback: SalahPlayback?, hasQueuedDua: Bool = false) {
    self.playback = playback
    playbackHasQueuedDua = playback != nil && hasQueuedDua
  }
  func playPrayer(_ event: PrayerEvent) {
    guard !preferences.muteSounds else { return }
    onPlayPrayer?(event)
  }
  func stopPlayback() {
    onStopPlayback?()
    setPlayback(nil)
  }
  func setNotificationPermission(_ status: IOSPermissionStatus) { notificationPermission = status }
  func setLocationPermission(_ status: IOSPermissionStatus) { locationPermission = status }

  func handle(url: URL) {
    guard url.scheme?.lowercased() == "salah" else { return }
    let host = url.host?.lowercased()
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    let destination = host == "settings" && !path.isEmpty ? path : (host ?? path)
    switch destination {
    case "today", "prayer", "play": selectedTab = .today
    case "times": selectedTab = .times
    case "qibla": selectedTab = .qibla
    case "settings", "location", "notifications", "alerts", "calculation", "sound", "appearance",
      "madhab", "highlatitude", "high-latitude", "adjustments", "hijri", "language", "about":
      selectedTab = .settings
      let route: IOSSettingsDestination? =
        switch destination {
        case "notifications", "alerts": .alerts
        case "high-latitude": .highLatitude
        default: IOSSettingsDestination.allCases.first { $0.rawValue.lowercased() == destination }
        }
      settingsPath = route.map { [$0] } ?? []
    default: return
    }
    if destination == "times",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let date = components.queryItems?.first(where: { $0.name == "date" })?.value,
      let day = CivilDay(date), day.isValid
    {
      selectedDay = day
    }
  }
}
