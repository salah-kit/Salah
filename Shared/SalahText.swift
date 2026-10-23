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

  /// The language code the hand-written tables key on (`SalahWidgetLabels`,
  /// `LocalizedTimeUnit`).
  var languageCode: String? { locale.language.languageCode?.identifier }

  /// The labels for the locale's language.
  var labels: SalahWidgetLabels { SalahWidgetLabels.localized(forLanguageCode: languageCode) }

  // MARK: - Clock times

  /// A clock time without its day period, bidi-isolated, for the menu bar: "4:11".
  func compactTime(_ date: Date) -> String {
    let formatter = timeFormatter()
    let periodFormatter = DateFormatter()
    periodFormatter.dateFormat = "a"
    periodFormatter.locale = formatter.locale
    periodFormatter.timeZone = timeZone
    let periodTrimCharacters = CharacterSet.whitespacesAndNewlines
      .union(CharacterSet(charactersIn: "\u{00A0}\u{202F}"))

    return formatter.string(from: date)
      .replacingOccurrences(of: periodFormatter.string(from: date), with: "")
      .trimmingCharacters(in: periodTrimCharacters)
      .bidiIsolated
  }

  /// The locale's short clock format for app-owned strings and compact status text.
  func timeFormatter() -> DateFormatter {
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
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.minimumIntegerDigits = minimumDigits
    formatter.usesGroupingSeparator = false
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
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

  /// The Gregorian date in full: "Tuesday, June 2, 2026". Arabic has no comma before the
  /// year: "الثلاثاء، ٢ يونيو ٢٠٢٦".
  func gregorianDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateStyle = .full
    formatter.timeStyle = .none
    if languageCode == "ar", let format = formatter.dateFormat {
      formatter.dateFormat = format.replacingOccurrences(of: "\u{060C} y", with: " y")
    }
    return formatter.string(from: date)
  }
}

nonisolated extension String {
  /// The string between U+2068 FIRST STRONG ISOLATE and U+2069 POP DIRECTIONAL ISOLATE,
  /// so it keeps its own direction inside text of the other direction.
  var bidiIsolated: String {
    "\u{2068}\(self)\u{2069}"
  }
}
