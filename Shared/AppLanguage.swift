import Foundation

nonisolated enum AppLanguage: String, Codable, CaseIterable, Sendable {
  case system
  case english
  case arabic
  case french
  case urdu
  case indonesian
  case turkish
  case persian
  case bengali
  case malay

  /// Locale used for translation lookup, number formatting, and digit shaping.
  /// Arabic mode explicitly forces the `arab` numbering system because
  /// `Locale(identifier: "ar")` on macOS otherwise defaults to Latin digits in
  /// NumberFormatter output.
  var locale: Locale {
    switch self {
    case .system:
      // Bypass our own app-container `AppleLanguages` override by reading the
      // global preferences scope directly. `Locale.current` caches the
      // process's startup locale and `Locale.preferredLanguages` honours our
      // container override; neither flips back to the real system language
      // when the user toggles to `.system` mid-session.
      if let langs = CFPreferencesCopyValue(
        "AppleLanguages" as CFString,
        kCFPreferencesAnyApplication,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
      ) as? [String], let first = langs.first {
        return Locale(identifier: first)
      }
      return Locale.autoupdatingCurrent
    case .english:
      return Locale(identifier: "en")
    case .arabic:
      var components = Locale.Components(languageCode: .arabic)
      components.numberingSystem = Locale.NumberingSystem("arab")
      return Locale(components: components)
    case .french:
      return Locale(identifier: "fr")
    case .indonesian:
      return Locale(identifier: "id")
    case .turkish:
      return Locale(identifier: "tr")
    case .malay:
      return Locale(identifier: "ms")
    case .urdu:
      return Self.localeWithNumbering("ur", numberingSystem: "arabext")
    case .persian:
      return Self.localeWithNumbering("fa", numberingSystem: "arabext")
    case .bengali:
      return Self.localeWithNumbering("bn", numberingSystem: "beng")
    }
  }

  /// Builds a `Locale` whose `NumberFormatter`/digit shaping uses an explicit
  /// numbering system. Needed because `Locale(identifier:)` on macOS otherwise
  /// emits Latin digits for some languages (e.g. Urdu/Persian default to Latin
  /// unless `arabext` is forced; Bengali to `beng`). Mirrors the `.arabic` case.
  private static func localeWithNumbering(_ code: String, numberingSystem: String) -> Locale {
    var components = Locale.Components(languageCode: Locale.LanguageCode(code))
    components.numberingSystem = Locale.NumberingSystem(numberingSystem)
    return Locale(components: components)
  }

  /// Language identifier(s) for `AppleLanguages` UserDefaults. Setting this
  /// makes `Bundle.main.preferredLocalizations` resolve to the chosen language,
  /// which is what drives the system's own strings, such as the app menu's items (built
  /// from `CFBundleDisplayName`). Returns `nil` for
  /// `.system` so the OS picks based on user's global language order.
  /// The `AppleTextDirection` default for this language, which lays AppKit out right to
  /// left: macOS sets it only for a right-to-left system language, so Salah sets it for its
  /// own. Nil follows the system.
  var appleTextDirectionOverride: Bool? {
    switch self {
    case .system: nil
    case .arabic, .urdu, .persian: true
    case .english, .french, .indonesian, .turkish, .bengali, .malay: false
    }
  }

  var appleLanguagesOverride: [String]? {
    switch self {
    case .system: return nil
    case .english: return ["en"]
    case .arabic: return ["ar"]
    case .french: return ["fr"]
    case .urdu: return ["ur"]
    case .indonesian: return ["id"]
    case .turkish: return ["tr"]
    case .persian: return ["fa"]
    case .bengali: return ["bn"]
    case .malay: return ["ms"]
    }
  }
}

// MARK: - Display helpers

nonisolated extension AppLanguage {
  /// All concrete language cases (excludes `.system`). Source of truth the
  /// picker iterates over so adding a new language is a single enum case.
  static var concreteCases: [AppLanguage] {
    AppLanguage.allCases.filter { $0 != .system }
  }

  /// ISO language code for concrete languages, `nil` for `.system`.
  var languageCode: String? {
    switch self {
    case .system: return nil
    case .english: return "en"
    case .arabic: return "ar"
    case .french: return "fr"
    case .urdu: return "ur"
    case .indonesian: return "id"
    case .turkish: return "tr"
    case .persian: return "fa"
    case .bengali: return "bn"
    case .malay: return "ms"
    }
  }

  /// Native name written in the language's own script. Callers handle the
  /// `.system` case separately since its label is localized via the catalog.
  var nativeName: String {
    switch self {
    case .system: return ""
    case .english: return "English"
    case .arabic: return "العربية"
    case .french: return "Français"
    case .urdu: return "اردو"
    case .indonesian: return "Bahasa Indonesia"
    case .turkish: return "Türkçe"
    case .persian: return "فارسی"
    case .bengali: return "বাংলা"
    case .malay: return "Bahasa Melayu"
    }
  }
}
