import Foundation
import SalahCalculation
import SalahCore
import SalahWidgets

/// The app's settings that the widget extension needs, mirrored into the App Group.
///
/// The app keeps its preferences in its own defaults, which the extension can't read. It
/// saves this value at launch and whenever a preference with the `display`,
/// `prayerTimes` or `localization` effect changes (`PrayerManager`), and the extension
/// builds its own schedule from it, so the widget stays right on the days the app isn't
/// running. `SharedValue.settings` reloads the widget only when the value changed.
///
/// Version 2: the version is in the key (`SalahWidgetConstants.settingsKey`), so a change
/// to the shape takes a new key, and a value that no longer decodes reads as missing.
nonisolated struct SalahSettings: Codable, Equatable, Sendable {
  /// Where: the coordinates, the time zone that defines the days, the country, and the
  /// name the header shows.
  var location: PrayerLocation
  /// How to calculate: every SalahTimes parameter, the Ramadan Isha rule included.
  var calculation: CalculationSettings
  /// The language the user chose.
  var language: AppLanguage
  /// Light, dark, or the system's appearance.
  var appearance: SalahAppearance
  /// Whether the sky follows the time of day; the neutral sky when it doesn't.
  var followsTimeOfDay: Bool
  /// Whether silent mode is on.
  var silentMode: Bool
  /// Days added to the Hijri date, for a local moon sighting.
  var hijriOffset: Int
  /// Each prayer's alert and reminders, sunrise included.
  var alerts: [PrayerKind: PrayerAlerts]
  /// Friday Dhuhr's alert and reminders while the Jumu'ah override is on; `nil` when it's
  /// off, so Friday's Dhuhr uses Dhuhr's own.
  var jumuahAlerts: PrayerAlerts?
}

/// One prayer's alert settings, as the widget shows them: whether it alerts at its time,
/// and its reminders. Sounds stay in the app.
nonisolated struct PrayerAlerts: Codable, Equatable, Sendable {
  /// Whether the prayer alerts at its time.
  var alert: Bool
  /// The before-reminder's offset in minutes, or `nil` when it's off.
  var beforeMinutes: Int?
  /// The after-reminder's offset in minutes, or `nil` when it's off.
  var afterMinutes: Int?

  init(alert: Bool, beforeMinutes: Int? = nil, afterMinutes: Int? = nil) {
    self.alert = alert
    self.beforeMinutes = beforeMinutes
    self.afterMinutes = afterMinutes
  }
}

nonisolated extension SalahSettings {
  /// The schedule these settings describe: Salah's calculated source at the location.
  var schedule: PrayerSchedule {
    PrayerSchedule(source: SalahPrayerSource(calculation), location: location)
  }

  /// The locale every surface draws in: the chosen language, with its native digits.
  var locale: Locale { language.locale }

  /// The interface labels in the chosen language.
  var labels: SalahWidgetLabels {
    SalahWidgetLabels.localized(forLanguageCode: locale.language.languageCode?.identifier)
  }

  /// The alert settings of an event: the Jumu'ah settings for Friday's Dhuhr while the
  /// override is on, otherwise its prayer's own.
  func alerts(for event: PrayerEvent) -> PrayerAlerts {
    if event.observance == .jumuah, let jumuahAlerts {
      return jumuahAlerts
    }
    return alerts[event.kind] ?? PrayerAlerts(alert: false)
  }
}

nonisolated extension SharedValue where Value == SalahSettings {
  /// The settings mirror in Salah's App Group. The app writes it; the extension reads it.
  static var settings: Self {
    SharedValue(appGroup: SalahWidgetConstants.appGroupID, key: SalahWidgetConstants.settingsKey)
  }
}
