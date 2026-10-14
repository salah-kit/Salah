import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

extension Preferences {
  /// The Calculation and Adjustments settings, as one value.
  var calculationChoices: CalculationChoices {
    CalculationChoices(
      method: methodPreference, madhab: madhabPreference,
      highLatitudeRule: highLatitudeRulePreference, customFajrAngle: customFajrAngle,
      customIshaAngle: customIshaAngle,
      adjustments: PrayerAdjustments(
        fajr: fajrAdjustment, sunrise: shuruqAdjustment, dhuhr: dhuhrAdjustment,
        asr: asrAdjustment, maghrib: maghribAdjustment, isha: ishaAdjustment),
      delayedIshaInRamadan: delayedIshaInRamadan, hijriOffset: hijriOffset)
  }

  /// The place prayer times are for: the stored coordinates and time zone, the country,
  /// and the name the header shows (the city, or the country when there's none).
  var prayerLocation: PrayerLocation {
    PrayerLocation(
      latitude: latitude, longitude: longitude,
      timeZone: TimeZone(identifier: storedTimeZone) ?? .current,
      countryCode: country.isEmpty ? nil : country, name: city.isEmpty ? countryName : city)
  }

  /// The settings the widget extension builds its timelines from, as the App Group
  /// mirror holds them.
  var mirroredSettings: SalahSettings {
    SalahSettings(
      location: prayerLocation, calculation: calculationChoices.calculationSettings,
      language: appLanguage, theme: resolvedWidgetTheme, silentMode: silentMode,
      hijriOffset: hijriOffset,
      alerts: Dictionary(
        uniqueKeysWithValues: PrayerKind.allCases.map { ($0, PrayerAlerts(config(for: $0))) }),
      jumuahAlerts: jumuahOverrideEnabled ? PrayerAlerts(jumuahConfig) : nil)
  }
}

extension PrayerAlerts {
  /// What the widget shows of a prayer's notification settings.
  init(_ config: PrayerNotificationConfig) {
    self.init(
      alert: config.alertEnabled,
      beforeMinutes: config.preReminderEnabled ? config.preReminderOffset : nil,
      afterMinutes: config.postReminderEnabled ? config.postReminderOffset : nil)
  }
}
