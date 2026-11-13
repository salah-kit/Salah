import Foundation
import SalahCore

/// Salah's own wording for times, durations and reminders, in an explicit locale and the
/// location's time zone. The app's menu bar and the widget extension share it, so both
/// draw the same text.
///
/// Durations come from SalahCore's `PrayerDurationFormat`; clock times use the locale's
/// short format. Reminder phrases retain Salah's "10m before" word order.
nonisolated struct SalahText: Sendable {
  /// The locale for words and digits: the user's language, with its native digits.
  var locale: Locale
  /// The time zone clock times are read in: the location's, not the device's.
  var timeZone: TimeZone
  /// Where the clock and digit formatters are kept: the shared cache, unless a test counts
  /// its own.
  var formatters: SalahFormatterCache = .shared

  /// The language code the hand-written tables key on (`SalahWidgetLabels`,
  /// `LocalizedTimeUnit`).
  var languageCode: String? { locale.language.languageCode?.identifier }

  /// The labels for the locale's language.
  var labels: SalahWidgetLabels { SalahWidgetLabels.localized(forLanguageCode: languageCode) }

  // MARK: - Clock times

  /// A clock time without its day period, bidi-isolated, for the menu bar: "4:11".
  func compactTime(_ date: Date) -> String {
    let (time, period) = formatters.clock(locale: locale, timeZone: timeZone) {
      ($0.time.string(from: date), $0.period.string(from: date))
    }
    let periodTrimCharacters = CharacterSet.whitespacesAndNewlines
      .union(CharacterSet(charactersIn: "\u{00A0}\u{202F}"))

    return
      time
      .replacingOccurrences(of: period, with: "")
      .trimmingCharacters(in: periodTrimCharacters)
      .bidiIsolated
  }

  /// A clock time in the locale's short format: "4:11 AM", "٤:١١ ص".
  ///
  /// Every row of every widget entry asks for one, so the formatter behind it is made once
  /// for the locale and the zone and reused.
  func clockTime(_ date: Date) -> String {
    formatters.clock(locale: locale, timeZone: timeZone) {
      $0.time.string(from: date)
    }
  }

  /// The locale's short clock format for app-owned strings and compact status text. Each
  /// call makes a formatter of the caller's own; `clockTime(_:)` formats with a shared one.
  func timeFormatter() -> DateFormatter {
    Self.makeTimeFormatter(locale: locale, timeZone: timeZone)
  }

  fileprivate static func makeTimeFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    formatter.calendar = locale.calendar
    formatter.locale = locale
    formatter.timeZone = timeZone
    return formatter
  }

  // MARK: - Durations

  /// A countdown or count-up, SalahCore's compact form: "45s", "12m", "2:15", "+12m".
  func duration(
    _ seconds: TimeInterval, direction: PrayerDurationFormat.Direction = .remaining,
    bidiIsolated: Bool = false
  ) -> String {
    PrayerDurationFormat.string(
      seconds, direction: direction, locale: locale, bidiIsolated: bidiIsolated)
  }

  // MARK: - Numbers and reminders

  /// An integer in the locale's digits, without grouping.
  func digits(_ value: Int, minimumDigits: Int = 1) -> String {
    formatters.digits(locale: locale, minimumDigits: minimumDigits) {
      $0.string(from: NSNumber(value: value))
    } ?? "\(value)"
  }

  /// Minutes with the language's unit, bidi-isolated: "10m", "١٠ د", "10 min".
  func minutes(_ minutes: Int) -> String {
    "\(digits(minutes))\(LocalizedTimeUnit.minuteSuffix(forLanguageCode: languageCode))"
      .bidiIsolated
  }

  /// A reminder's offset in the language's word order: "10m before", "قبل ١٠ د",
  /// "10 min avant".
  func offsetPhrase(_ minutes: Int, before: Bool) -> String {
    let word = before ? labels.before : labels.after
    let value = self.minutes(minutes)
    switch languageCode {
    case "ar": return "\(word) \(value)"  // قبل ١٠ د
    default: return "\(value) \(word)"  // 10m before, 10 min avant
    }
  }

  /// The reminders alone, for a focus card: "10m before · 5m after"; `nil` without
  /// reminders.
  func reminderDetail(_ alerts: PrayerAlerts) -> String? {
    var parts: [String] = []
    if let before = alerts.beforeMinutes { parts.append(offsetPhrase(before, before: true)) }
    if let after = alerts.afterMinutes { parts.append(offsetPhrase(after, before: false)) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  /// The alert and its reminders on one line: "Alert on · 10m before · 5m after". Silent
  /// mode leads with "Silent", since nothing sounds whatever the alert setting.
  func reminderSummary(_ alerts: PrayerAlerts, silentMode: Bool) -> String {
    let head = silentMode ? labels.silent : (alerts.alert ? labels.alertOn : labels.alertOff)
    return ([head] + [reminderDetail(alerts)].compactMap { $0 }).joined(separator: " · ")
  }

  // MARK: - Dates

  /// The Hijri date's day, month name and year, after the user's day offset, without an
  /// era: ("16", "Dhuʻl-Hijjah", "1447").
  func hijri(_ date: Date, dayOffset: Int) -> (day: String, month: String, year: String) {
    let format = HijriDateFormat(locale: locale, timeZone: timeZone, dayOffset: dayOffset)
    let components = format.components(of: date)
    return (
      digits(components.day), format.string(from: date, template: "MMMM"),
      digits(components.year)
    )
  }

  /// The civil date in full: "Tuesday, June 2, 2026", in the locale's calendar, or the
  /// Gregorian one where the locale counts in Hijri, as ar_SA does. Arabic has no comma
  /// before the year: "الثلاثاء، ٢ يونيو ٢٠٢٦".
  func gregorianDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = locale.civilCalendar
    formatter.timeZone = timeZone
    formatter.dateStyle = .full
    formatter.timeStyle = .none
    if languageCode == "ar", let format = formatter.dateFormat {
      formatter.dateFormat = format.replacingOccurrences(of: "\u{060C} y", with: " y")
    }
    return formatter.string(from: date)
  }

  /// The civil date from a template in the locale's order, such as "EEEEMMMMd" →
  /// "Tuesday, June 2", in the same calendar as `gregorianDate(_:)`.
  func civilDate(_ date: Date, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = locale.civilCalendar
    formatter.timeZone = timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }

  /// A range of civil dates from a template, such as "d MMMM yyyy" → "1 – 7 June 2026", in
  /// the same calendar as `gregorianDate(_:)`.
  func civilRange(from start: Date, to end: Date, template: String) -> String {
    let formatter = DateIntervalFormatter()
    formatter.locale = locale
    formatter.calendar = locale.civilCalendar
    formatter.timeZone = timeZone
    formatter.dateTemplate = template
    return formatter.string(from: start, to: end)
  }
}

/// The formatters behind `SalahText`'s clock times and digits, made once for each locale
/// and zone.
///
/// Creating a `DateFormatter` opens ICU's data for its locale, which costs far more than
/// formatting with it. A widget timeline draws every row of every entry several times over,
/// so a formatter per call made WidgetKit's archiving slow enough to leave a placed widget
/// on its placeholder. Formatting runs under the cache's lock, one caller at a time.
nonisolated final class SalahFormatterCache: @unchecked Sendable {
  static let shared = SalahFormatterCache()

  /// The clock formatters for one locale and zone.
  struct Clock {
    /// The locale's short time: "4:11 AM".
    let time: DateFormatter
    /// The day period alone, which `compactTime(_:)` removes: "AM".
    let period: DateFormatter
  }

  private struct ClockKey: Hashable {
    let locale: Locale
    let timeZone: TimeZone
  }

  private struct DigitsKey: Hashable {
    let locale: Locale
    let minimumDigits: Int
  }

  /// A person's languages and places are few; past this the cache starts over rather than
  /// growing with every locale a long-running app ever showed.
  private static let capacity = 32

  private let lock = NSLock()
  private var clocks: [ClockKey: Clock] = [:]
  private var numbers: [DigitsKey: NumberFormatter] = [:]
  private var created = 0

  /// How many formatters the cache has made, for the tests that hold it to one per key.
  var creations: Int { lock.withLock { created } }

  func clock<Value>(locale: Locale, timeZone: TimeZone, _ format: (Clock) -> Value) -> Value {
    lock.withLock {
      let key = ClockKey(locale: locale, timeZone: timeZone)
      if let clock = clocks[key] { return format(clock) }
      let time = SalahText.makeTimeFormatter(locale: locale, timeZone: timeZone)
      let period = DateFormatter()
      period.dateFormat = "a"
      period.locale = time.locale
      period.timeZone = timeZone
      let clock = Clock(time: time, period: period)
      if clocks.count >= Self.capacity { clocks.removeAll() }
      clocks[key] = clock
      created += 2
      return format(clock)
    }
  }

  func digits<Value>(locale: Locale, minimumDigits: Int, _ format: (NumberFormatter) -> Value)
    -> Value
  {
    lock.withLock {
      let key = DigitsKey(locale: locale, minimumDigits: minimumDigits)
      if let formatter = numbers[key] { return format(formatter) }
      let formatter = NumberFormatter()
      formatter.locale = locale
      formatter.minimumIntegerDigits = minimumDigits
      formatter.usesGroupingSeparator = false
      if numbers.count >= Self.capacity { numbers.removeAll() }
      numbers[key] = formatter
      created += 1
      return format(formatter)
    }
  }
}

nonisolated extension String {
  /// The string between U+2068 FIRST STRONG ISOLATE and U+2069 POP DIRECTIONAL ISOLATE,
  /// so it keeps its own direction inside text of the other direction.
  var bidiIsolated: String {
    "\u{2068}\(self)\u{2069}"
  }
}

nonisolated extension Locale {
  /// The calendar for the civil date beside the Hijri one: the locale's own, unless it
  /// counts in Hijri itself, as Saudi Arabia's does, which would show the Hijri date twice.
  var civilCalendar: Calendar {
    switch calendar.identifier {
    case .islamic, .islamicCivil, .islamicTabular, .islamicUmmAlQura:
      Calendar(identifier: .gregorian)
    default: calendar
    }
  }
}
