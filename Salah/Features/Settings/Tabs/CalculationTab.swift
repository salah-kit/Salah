import SwiftUI

struct CalculationContent: View {
  @Bindable var prefs = Preferences.shared

  var body: some View {
    Section {
      Toggle(isOn: $prefs.autoDetectMethod) {
        Text("settings.calc.autoDetect")
        if let suggestion = CalculationText.methodSuggestion(
          prefs.suggestedMethod, country: prefs.placeCountry(locale: .app), locale: .app)
        {
          Text(verbatim: suggestion)
        }
      }
      .settingsRow(detail: true)

      // Enabled while the method is suggested: choosing one by hand turns suggestions off.
      Picker(
        "settings.calc.methodPicker",
        selection: Binding(get: { prefs.methodPreference }, set: { prefs.chooseMethod($0) })
      ) {
        ForEach(CalculationText.methodOrder, id: \.self) { method in
          Text(LocalizedStringKey(method.titleKey)).tag(method)
        }
      }
      .settingsPopUp()
      .settingsRow(last: true)
    } header: {
      SettingsHeader("settings.calc.method", isFirst: true)
    }
    // Refreshes are emitted by the preference didSets; these only run the extra
    // auto-detect re-derivation when the toggles flip on.
    .onChange(of: prefs.autoDetectMethod) {
      if prefs.autoDetectMethod { prefs.updateAutoDetectedSettings() }
    }
    .onChange(of: prefs.autoDetectHighLatitudeRule) {
      if prefs.autoDetectHighLatitudeRule { prefs.updateAutoDetectedSettings() }
    }

    if prefs.methodPreference == .custom {
      Section {
        HStack {
          Text("settings.calc.fajrAngle")
          Spacer()
          TextField("", value: $prefs.customFajrAngle, format: .number)
            .frame(width: 60)
            .multilineTextAlignment(.trailing)
        }
        .settingsRow()
        HStack {
          Text("settings.calc.ishaAngle")
          Spacer()
          TextField("", value: $prefs.customIshaAngle, format: .number)
            .frame(width: 60)
            .multilineTextAlignment(.trailing)
        }
        .settingsRow(last: true)
      } header: {
        SettingsHeader("settings.calc.customAngles")
      }
    }

    Section {
      Picker("settings.calc.madhab", selection: $prefs.madhabPreference) {
        Text("settings.calc.madhab.shafi").tag(MadhabPreference.shafi)
        Text("settings.calc.madhab.hanafi").tag(MadhabPreference.hanafi)
      }
      .settingsPopUp()
      .settingsRow(last: true)
    } header: {
      SettingsHeader("prayer.asr")
    }

    Section {
      Toggle(isOn: $prefs.autoDetectHighLatitudeRule) {
        Text("settings.calc.highLat.autoDetect")
        Text(
          verbatim: CalculationText.ruleSuggestion(prefs.suggestedHighLatitudeRule, locale: .app))
      }
      .settingsRow(detail: true)

      Picker(
        "settings.calc.highLat.rule",
        selection: Binding(
          get: { prefs.highLatitudeRulePreference }, set: { prefs.chooseHighLatitudeRule($0) })
      ) {
        ForEach(
          [HighLatitudeRulePreference.middleOfTheNight, .seventhOfTheNight, .twilightAngle],
          id: \.self
        ) { rule in
          Text(LocalizedStringKey(rule.titleKey)).tag(rule)
        }
      }
      .settingsPopUp()
      .settingsRow(last: true)
    } header: {
      SettingsHeader("settings.calc.highLat")
    }
  }
}

/// How the Calculation pane names its choices and suggestions.
enum CalculationText {
  /// The methods in the pop-up's order.
  static let methodOrder: [MethodPreference] = [
    .egyptian, .karachi, .northAmerica, .muslimWorldLeague, .ummAlQura, .gulf,
    .moonsightingCommittee, .kuwait, .qatar, .singapore, .tehran, .custom,
  ]

  /// "Umm al-Qura for Saudi Arabia" / "أم القرى للسعودية": the method Salah suggests and
  /// the country it suggests it for, or `nil` without a country.
  static func methodSuggestion(_ method: MethodPreference, country: String, locale: Locale)
    -> String?
  {
    guard !country.isEmpty else { return nil }
    var country = country
    // Arabic joins the preposition ل to the country, and ل with the article ال makes لل:
    // "للسعودية", not "لالسعودية".
    if locale.language.languageCode == .arabic, country.hasPrefix("ال") {
      country.removeFirst()
    }
    return String(
      format: localizedString("settings.calc.autoDetect.detail", locale: locale), locale: locale,
      localizedString(dynamicKey: method.titleKey, locale: locale), country)
  }

  /// "Middle of the night here": the rule Salah would choose at the current place.
  static func ruleSuggestion(_ rule: HighLatitudeRulePreference, locale: Locale) -> String {
    String(
      format: localizedString("settings.calc.highLat.autoDetect.detail", locale: locale),
      locale: locale, localizedString(dynamicKey: rule.titleKey, locale: locale))
  }
}

extension MethodPreference {
  /// The catalog key of the method's name.
  var titleKey: String {
    switch self {
    case .egyptian: "settings.calc.method.egyptian"
    case .karachi: "settings.calc.method.karachi"
    case .northAmerica: "settings.calc.method.northAmerica"
    case .muslimWorldLeague: "settings.calc.method.mwl"
    case .ummAlQura: "settings.calc.method.ummAlQura"
    case .gulf: "settings.calc.method.gulf"
    case .moonsightingCommittee: "settings.calc.method.moonsighting"
    case .custom: "settings.calc.method.custom"
    case .kuwait: "settings.calc.method.kuwait"
    case .qatar: "settings.calc.method.qatar"
    case .singapore: "settings.calc.method.singapore"
    case .tehran: "settings.calc.method.tehran"
    }
  }
}

extension HighLatitudeRulePreference {
  /// The catalog key of the rule's name.
  var titleKey: String {
    switch self {
    case .middleOfTheNight: "settings.calc.highLat.middle"
    case .seventhOfTheNight: "settings.calc.highLat.seventh"
    case .twilightAngle: "settings.calc.highLat.twilight"
    }
  }
}
