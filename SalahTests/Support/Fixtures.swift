import Adhan
import Foundation

/// The fixture the characterization tests and baselines share: the app's default
/// location and calculation settings (Makkah, Umm al-Qura, Shafi, middle of the
/// night; see `PreferencesDefaults.swift`) on Tuesday 2 June 2026, outside Ramadan.
///
/// Times Adhan 1.4.0 gives for that day, Asia/Riyadh: Fajr 04:11, Sunrise 05:38,
/// Dhuhr 12:19, Asr 15:35, Maghrib 19:00, Isha 20:30.
enum Fixture {
  static let timeZone = TimeZone(identifier: "Asia/Riyadh")!
  static let coordinates = Coordinates(latitude: 21.4167, longitude: 39.8167)
  static let year = 2026
  static let month = 6
  static let day = 2

  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar
  }

  /// A wall-clock time on the fixture day (or `dayOffset` days later) in Riyadh.
  static func date(
    _ hour: Int, _ minute: Int, _ second: Int = 0, dayOffset: Int = 0
  ) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day + dayOffset
    components.hour = hour
    components.minute = minute
    components.second = second
    return calendar.date(from: components)!
  }

  static func dayComponents(offset: Int = 0) -> DateComponents {
    calendar.dateComponents([.year, .month, .day], from: date(12, 0, dayOffset: offset))
  }

  /// The parameters `PrayerManager.calculationParameters(for:)` builds from the
  /// default preferences: the method's parameters plus madhab, high-latitude rule
  /// and per-prayer minute adjustments. (Its Ramadan Isha delay doesn't apply in
  /// June 2026, and the method isn't Custom, so no custom angles.)
  static func parameters(ishaAdjustment: Int = 0) -> CalculationParameters {
    var params = MethodPreference.ummAlQura.adhanMethod.params
    params.madhab = .shafi
    params.highLatitudeRule = HighLatitudeRulePreference.middleOfTheNight.adhanRule
    params.adjustments = PrayerAdjustments(
      fajr: 0, sunrise: 0, dhuhr: 0, asr: 0, maghrib: 0, isha: ishaAdjustment)
    return params
  }

  static func prayerTimes(dayOffset: Int = 0, ishaAdjustment: Int = 0) -> PrayerTimes {
    PrayerTimes(
      coordinates: coordinates, date: dayComponents(offset: dayOffset),
      calculationParameters: parameters(ishaAdjustment: ishaAdjustment))!
  }

  /// Yesterday, today and tomorrow, as `PrayerManager` hands them to the scheduler.
  static var threeDayWindow: [PrayerTimes] {
    [prayerTimes(dayOffset: -1), prayerTimes(), prayerTimes(dayOffset: 1)]
  }

  /// The menu bar's and the notifications' clock text for a time.
  static func formattedTime(_ date: Date) -> String {
    PrayerDisplayFormatter(timeZone: timeZone, hijriOffset: 0).fullTime(for: date)
  }
}

extension Date {
  func adding(minutes: Double = 0, seconds: Double = 0) -> Date {
    addingTimeInterval(minutes * 60 + seconds)
  }
}

/// Notification settings for one prayer, spelled out so tests read like settings.
extension PrayerNotificationConfig {
  static func alert(
    _ alertEnabled: Bool = true,
    sound: AdhanSound = .alafasy,
    before: Int? = nil,
    beforeSound: AdhanSound = .system,
    after: Int? = nil,
    afterSound: AdhanSound = .system
  ) -> PrayerNotificationConfig {
    PrayerNotificationConfig(
      alertEnabled: alertEnabled, alertSound: sound,
      preReminderEnabled: before != nil, preReminderOffset: before ?? 10,
      preReminderSound: beforeSound,
      postReminderEnabled: after != nil, postReminderOffset: after ?? 5,
      postReminderSound: afterSound)
  }

  static let off = PrayerNotificationConfig.alert(false)
}

extension Preferences {
  /// Fresh preferences over their own suite, with the given per-prayer settings.
  /// Prayers left out keep the app's defaults.
  static func scratch(
    _ scratch: ScratchDefaults, settings: [Prayer: PrayerNotificationConfig] = [:]
  ) -> Preferences {
    let preferences = Preferences(defaults: scratch.defaults)
    for (prayer, config) in settings {
      preferences.setConfig(config, for: prayer)
    }
    return preferences
  }
}
