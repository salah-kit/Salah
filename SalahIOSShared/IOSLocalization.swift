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
