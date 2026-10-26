import Foundation
import SalahCore

/// Apple TV wording in the language chosen in Salah: the design's Arabic, and the String
/// Catalog for the other languages.
nonisolated struct TVCopy: Sendable {
  let locale: Locale

  func callAsFunction(_ english: String, _ arabic: String) -> String {
    IOSL10n.text(english, arabic: arabic, locale: locale, bundle: AppResources.bundle)
  }

  /// A catalog sentence with its arguments, keeping numbers in the language's digits.
  func format(_ english: String, _ arabic: String, _ arguments: CVarArg...) -> String {
    String(format: self(english, arabic), locale: locale, arguments: arguments)
  }
}

/// The clock forms the TV draws: a time split from its day period for the large numerals,
/// and the 24-hour times of the week grid.
nonisolated struct TVTimeText: Sendable {
  let text: SalahText

  init(locale: Locale, timeZone: TimeZone) {
    text = SalahText(locale: locale, timeZone: timeZone)
  }

  /// The locale's short time, bidi-isolated: "3:35 PM", "٣:٣٥ م".
  func time(_ date: Date) -> String {
    text.timeFormatter().string(from: date).bidiIsolated
  }

  /// The time without its day period, for a large numeral: "11:40".
  func clock(_ date: Date) -> String { text.compactTime(date) }

  /// The day period the clock leaves out, such as "AM", or `nil` for a 24-hour locale.
  func period(_ date: Date) -> String? {
    let formatter = text.timeFormatter()
    let full = formatter.string(from: date)
    let periodFormatter = DateFormatter()
    periodFormatter.locale = formatter.locale
    periodFormatter.timeZone = formatter.timeZone
    periodFormatter.dateFormat = "a"
    let period = periodFormatter.string(from: date)
    return full.contains(period) ? period : nil
  }

  /// A 24-hour time for the week's grid, where columns of AM and PM would be ambiguous.
  func time24(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = text.locale
    formatter.timeZone = text.timeZone
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date).bidiIsolated
  }

  /// The civil date from a template in the locale's order, such as "EEEEMMMMd" →
  /// "Tuesday, June 2", in the same calendar as `SalahText.gregorianDate(_:)`.
  func date(_ date: Date, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = text.locale
    formatter.calendar = text.locale.civilCalendar
    formatter.timeZone = text.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }

  /// A range of civil dates from a template, such as "d MMMM yyyy" → "1 – 7 June 2026", in
  /// the same calendar as `date(_:template:)`.
  func range(from start: Date, to end: Date, template: String) -> String {
    let formatter = DateIntervalFormatter()
    formatter.locale = text.locale
    formatter.calendar = text.locale.civilCalendar
    formatter.timeZone = text.timeZone
    formatter.dateTemplate = template
    return formatter.string(from: start, to: end)
  }

  /// The Hijri date with the person's offset: "16 Dhuʻl-Hijjah 1447".
  func hijri(_ date: Date, offset: Int) -> String {
    let value = text.hijri(date, dayOffset: offset)
    return "\(value.day) \(value.month) \(value.year)"
  }
}
