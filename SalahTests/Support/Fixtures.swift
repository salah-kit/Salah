import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

/// The fixture the tests and baselines share: the app's default location and calculation
/// settings (Makkah, Umm al-Qura, Shafi, middle of the night; see
/// `PreferencesDefaults.swift`) on Tuesday 2 June 2026, outside Ramadan.
///
/// SalahCalculation gives, Asia/Riyadh: Fajr 04:11, Sunrise 05:38, Dhuhr 12:19, Asr 15:35,
/// Maghrib 19:00, Isha 20:30 (and Asr 15:36 on 3 June) - the times adhan-swift 1.4.0 gave
/// before Salah moved onto SalahKit, minute for minute.
enum Fixture {
  static let timeZone = TimeZone(identifier: "Asia/Riyadh")!
  static let latitude = 21.4167
  static let longitude = 39.8167
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

  /// The fixture day, or `offset` days later, as an owning day.
  static func civilDay(offset: Int = 0) -> CivilDay {
    CivilDay(year: year, month: month, day: day).adding(days: offset)
  }

  static var location: PrayerLocation {
    PrayerLocation(
      latitude: latitude, longitude: longitude, timeZone: timeZone, countryCode: "SA",
      name: "Makkah")
  }

  /// The calculation choices the default preferences make: Umm al-Qura, Shafi, middle
  /// of the night, the delayed Ramadan Isha on, plus an Isha adjustment.
  static func choices(ishaAdjustment: Int = 0) -> CalculationChoices {
    CalculationChoices(
      method: .ummAlQura, madhab: .shafi, highLatitudeRule: .middleOfTheNight,
      customFajrAngle: 18, customIshaAngle: 17.5,
      adjustments: PrayerAdjustments(isha: ishaAdjustment), delayedIshaInRamadan: true,
      hijriOffset: 0)
  }

  static func schedule(ishaAdjustment: Int = 0) -> PrayerSchedule {
    PrayerSchedule(
      source: SalahPrayerSource(choices(ishaAdjustment: ishaAdjustment).calculationSettings),
      location: location)
  }

  /// The fixture day's events (or a later day's), as the app's schedule gives them.
  static func day(dayOffset: Int = 0, ishaAdjustment: Int = 0) -> PrayerDay {
    schedule(ishaAdjustment: ishaAdjustment).day(civilDay(offset: dayOffset)).day!
  }

  /// One event of the fixture day (or a later day).
  static func event(_ kind: PrayerKind, dayOffset: Int = 0, ishaAdjustment: Int = 0)
    -> PrayerEvent
  {
    day(dayOffset: dayOffset, ishaAdjustment: ishaAdjustment)[kind]!
  }

  static func time(_ kind: PrayerKind, dayOffset: Int = 0, ishaAdjustment: Int = 0) -> Date {
    event(kind, dayOffset: dayOffset, ishaAdjustment: ishaAdjustment).time
  }

  /// The menu bar's and the notifications' clock text for a time.
  static func formattedTime(_ date: Date) -> String {
    PrayerDisplayFormatter(timeZone: timeZone).fullTime(for: date)
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
    _ scratch: ScratchDefaults, settings: [PrayerKind: PrayerNotificationConfig] = [:]
  ) -> Preferences {
    let preferences = Preferences(defaults: scratch.defaults)
    for (prayer, config) in settings {
      preferences.setConfig(config, for: prayer)
    }
    return preferences
  }
}
