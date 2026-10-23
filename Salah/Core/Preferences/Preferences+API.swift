import Foundation
import SalahCore

extension Preferences {
  func config(for prayer: PrayerKind) -> PrayerNotificationConfig {
    (notificationSettings[prayer.settingsKey] ?? PrayerNotificationConfig.defaultConfig(for: prayer))
      .sanitized()
  }

  func config(for prayer: PrayerKind, on date: Date) -> PrayerNotificationConfig {
    if usesJumuahOverride(for: prayer, on: date) {
      return jumuahConfig
    }
    return config(for: prayer)
  }

  func setConfig(_ config: PrayerNotificationConfig, for prayer: PrayerKind) {
    notificationSettings[prayer.settingsKey] = config.sanitized()
  }

  func setConfig(_ config: PrayerNotificationConfig, for prayer: PrayerKind, on date: Date) {
    if usesJumuahOverride(for: prayer, on: date) {
      setJumuahConfig(config)
    } else {
      setConfig(config, for: prayer)
    }
  }

  /// Flips an event's alert. Friday-aware, so toggling Jumu'ah edits the Jumu'ah settings
  /// while the override is on, matching the row's name and state.
  func toggleAlert(for event: PrayerEvent) {
    var config = config(for: event.kind, on: event.time)
    config.alertEnabled.toggle()
    setConfig(config, for: event.kind, on: event.time)
  }

  var jumuahConfig: PrayerNotificationConfig {
    (notificationSettings[PrayerKind.jumuahSettingsKey] ?? config(for: .dhuhr)).sanitized()
  }

  func setJumuahConfig(_ config: PrayerNotificationConfig) {
    notificationSettings[PrayerKind.jumuahSettingsKey] = config.sanitized()
  }

  func seedJumuahConfigIfNeeded() {
    guard notificationSettings[PrayerKind.jumuahSettingsKey] == nil else { return }
    notificationSettings[PrayerKind.jumuahSettingsKey] = config(for: .dhuhr)
  }

  private func usesJumuahOverride(for prayer: PrayerKind, on date: Date) -> Bool {
    prayer == .dhuhr && jumuahOverrideEnabled && isFridayInStoredTimeZone(date)
  }

  private func isFridayInStoredTimeZone(_ date: Date) -> Bool {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: storedTimeZone) ?? .current
    return calendar.component(.weekday, from: date) == 6
  }

  func updateAutoDetectedSettings() {
    // Re-entrant-safe: when called from inside `updateLocation`'s batch, these
    // writes join that batch; called on its own they coalesce to one refresh.
    batchUpdates {
      if autoDetectMethod {
        methodPreference = MethodPreference.detect(forCountry: country)
      }
      if autoDetectHighLatitudeRule {
        highLatitudeRulePreference = abs(latitude) > 48 ? .seventhOfTheNight : .middleOfTheNight
      }
    }
  }

  func updateLocation(
    latitude: Double, longitude: Double, city: String, state: String, country: String,
    countryName: String, timeZone: String
  ) {
    // One coalesced refresh for the whole location change, not seven.
    batchUpdates {
      self.latitude = latitude
      self.longitude = longitude
      self.city = city
      self.state = state
      self.country = country
      self.countryName = countryName
      self.storedTimeZone = timeZone
      updateAutoDetectedSettings()
    }
  }

  func enforceVisibleMenuBarContent() {
    if !displayIcon && !displayNextPrayer {
      displayIcon = true
    }

    if displayNextPrayer && nextPrayerDisplayName == .none && nextPrayerDisplayType == .none {
      nextPrayerDisplayType = .timeUntil
    }
  }
}
