import Foundation

/// Loads iOS app and extension copy with the language chosen in Salah.
///
/// The catalog is compiled into both targets. The explicit resource locale makes a language
/// change take effect immediately without changing the device's language or restarting the app.
nonisolated enum IOSL10n {
  static func text(
    _ english: String, arabic: String? = nil, locale: Locale, bundle: Bundle = .main
  ) -> String {
    // Preserve the design's contextual Arabic wording, such as “None” for sounds versus offsets.
    if locale.language.languageCode?.identifier == "ar", let arabic { return arabic }
    let resource = LocalizedStringResource(
      String.LocalizationValue(stringLiteral: english), locale: locale,
      bundle: bundle == .main ? .main : .atURL(bundle.bundleURL))
    return String(localized: resource)
  }

  /// Formats a catalog-owned sentence, keeping numbers in the selected language's digits.
  static func format(
    _ english: String, arabic: String? = nil, locale: Locale, bundle: Bundle = .main,
    arguments: CVarArg...
  ) -> String {
    String(
      format: text(english, arabic: arabic, locale: locale, bundle: bundle), locale: locale,
      arguments: arguments)
  }

  /// Arabic minutes after بعد or منذ, the noun in the number the count takes: "دقيقة واحدة",
  /// "دقيقتين", "٣ دقائق", "١١ دقيقة", in the locale's digits. A `%lld` entry can't vary its
  /// noun, and an `arabic:` literal can't carry plural variations.
  static func arabicMinutes(_ count: Int, locale: Locale) -> String {
    arabicCount(
      count, one: "دقيقة واحدة", two: "دقيقتين", few: "دقائق", many: "دقيقة", other: "دقيقة",
      locale: locale)
  }

  /// An Arabic day offset as a value, signed: "+ يوم واحد", "− يومان", "+ ٣ أيام".
  static func arabicDayOffset(_ value: Int, locale: Locale) -> String {
    let days = arabicCount(
      value, one: "يوم واحد", two: "يومان", few: "أيام", many: "يومًا", other: "يوم",
      locale: locale)
    return value > 0 ? "+ \(days)" : value < 0 ? "− \(days)" : days
  }

  /// Arabic's count forms: the noun alone for one and two, a plural noun for 3–10, and a
  /// singular one from 11, both after the locale's digits.
  private static func arabicCount(
    _ count: Int, one: String, two: String, few: String, many: String, other: String,
    locale: Locale
  ) -> String {
    let magnitude = abs(count)
    if magnitude == 1 { return one }
    if magnitude == 2 { return two }
    let formatter = NumberFormatter()
    formatter.locale = locale
    formatter.usesGroupingSeparator = false
    let digits = formatter.string(from: NSNumber(value: magnitude)) ?? "\(magnitude)"
    let noun =
      switch magnitude % 100 {
      case 3...10: few
      case 11...99: many
      default: other
      }
    return "\(digits) \(noun)"
  }
}

nonisolated extension IOSCalculationMethod {
  func title(locale: Locale) -> String {
    IOSL10n.text(title(), arabic: title(isArabic: true), locale: locale)
  }
}

nonisolated extension IOSSound {
  func title(locale: Locale) -> String {
    switch self {
    case .custom: title()
    default: IOSL10n.text(title(), arabic: title(isArabic: true), locale: locale)
    }
  }
}
