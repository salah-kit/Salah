import SwiftUI

/// The language Salah shows: macOS's, or one of its own languages by its native name. The
/// system choice names the language macOS uses.
struct LanguagePicker: View {
  @Bindable var prefs = Preferences.shared

  var body: some View {
    Picker("settings.general.language", selection: $prefs.appLanguage) {
      Text(verbatim: Self.systemTitle(locale: prefs.appLanguage.locale)).tag(AppLanguage.system)
      ForEach(AppLanguage.concreteCases, id: \.self) { language in
        Text(verbatim: language.nativeName).tag(language)
      }
    }
    .settingsPopUp()
  }

  /// "System (English)": the system choice, with the name of the language macOS uses, in
  /// the language Salah shows.
  static func systemTitle(locale: Locale) -> String {
    String(
      format: localizedString("settings.general.language.systemValue", locale: locale),
      locale: locale, systemLanguageName(in: locale))
  }

  /// The language macOS uses, named in `locale`. `AppLanguage.system`'s locale reads the
  /// global preferences, past the `AppleLanguages` Salah sets for its own language.
  static func systemLanguageName(in locale: Locale) -> String {
    let code = AppLanguage.system.locale.language.languageCode?.identifier ?? "en"
    return locale.localizedString(forLanguageCode: code) ?? code
  }
}
