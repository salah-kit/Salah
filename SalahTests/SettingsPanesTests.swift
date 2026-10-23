import Foundation
import SalahCore
import Testing

/// What the settings panes write and decide: the default place in the app's language, a
/// place's region, coordinates and time zone, the Calculation suggestions and their
/// switches, and the values beside the panes' steppers.
@Suite("Settings panes")
struct SettingsPanesTests {
  init() { TestEnvironment.configure() }

  let english = AppLanguage.english.locale
  let arabic = AppLanguage.arabic.locale

  // MARK: - The default place

  /// Until a location or a city replaces it, the default place reads in the app's language
  /// wherever Salah shows it: the place name every surface takes from the settings, and the
  /// Location pane's city, region and country.
  @Test func theDefaultPlaceReadsInTheAppsLanguage() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    #expect(preferences.isDefaultPlace)

    preferences.appLanguage = .english
    #expect(preferences.mirroredSettings.location.name == "Makkah")
    #expect(preferences.placeCountry(locale: english) == "Saudi Arabia")

    preferences.appLanguage = .arabic
    #expect(preferences.mirroredSettings.location.name == "مكة المكرمة")
    #expect(preferences.placeCity(locale: arabic) == "مكة المكرمة")
    #expect(preferences.placeRegion(locale: arabic) == "مكة المكرمة")
    #expect(preferences.placeCountry(locale: arabic) == "السعودية")
    // What's stored stays the English names earlier versions stored.
    #expect(preferences.city == "Makkah" && preferences.countryName == "Saudi Arabia")
  }

  /// An install from an earlier version, which saved the default place's English names,
  /// reads in the app's language too.
  @Test func anEarlierInstallsSavedDefaultPlaceIsTranslated() {
    let scratch = ScratchDefaults()
    scratch.defaults.set("Makkah", forKey: Preferences.Key.city)
    scratch.defaults.set("Makkah", forKey: Preferences.Key.state)
    scratch.defaults.set("Saudi Arabia", forKey: Preferences.Key.countryName)
    scratch.defaults.set(21.4167, forKey: Preferences.Key.latitude)
    scratch.defaults.set(39.8167, forKey: Preferences.Key.longitude)
    scratch.defaults.set(AppLanguage.arabic.rawValue, forKey: Preferences.Key.appLanguage)
    let preferences = Preferences(defaults: scratch.defaults)
    #expect(preferences.mirroredSettings.location.name == "مكة المكرمة")
  }

  /// A geocoded or chosen place keeps the names it came with, Makkah included: only the
  /// default place, at its own coordinates, is translated.
  @Test func aPlaceOfItsOwnKeepsItsNames() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    preferences.appLanguage = .arabic
    preferences.updateLocation(
      latitude: 30.0444, longitude: 31.2357, city: "Cairo", state: "Cairo Governorate",
      country: "EG", countryName: "Egypt", timeZone: "Africa/Cairo")
    #expect(!preferences.isDefaultPlace)
    #expect(preferences.mirroredSettings.location.name == "Cairo")
    #expect(preferences.placeCountry(locale: arabic) == "Egypt")

    preferences.updateLocation(
      latitude: 21.4225, longitude: 39.8262, city: "Makkah", state: "Makkah",
      country: "SA", countryName: "Saudi Arabia", timeZone: "Asia/Riyadh")
    #expect(!preferences.isDefaultPlace)
    #expect(preferences.mirroredSettings.location.name == "Makkah")
  }

  // MARK: - Location

  /// The region and the coordinates take the language's comma, and the coordinates its
  /// digits and decimal separator.
  @Test func regionAndCoordinatesFollowTheLanguage() {
    #expect(
      LocationText.pair("Makkah", "Saudi Arabia", locale: english) == "Makkah, Saudi Arabia")
    #expect(
      plain(LocationText.pair("مكة المكرمة", "السعودية", locale: arabic)) == "مكة المكرمة، السعودية"
    )
    #expect(LocationText.pair("", "Egypt", locale: english) == "Egypt")
    #expect(
      LocationText.coordinates(latitude: 21.4167, longitude: 39.8167, locale: english)
        == "21.4167, 39.8167")
    #expect(
      LocationText.coordinates(latitude: 21.4167, longitude: 39.8167, locale: arabic)
        == "٢١٫٤١٦٧، ٣٩٫٨١٦٧")
  }

  /// The time zone is its identifier in a language written in Latin script, and its city
  /// in another script.
  @Test func theTimeZoneReadsInTheLanguagesScript() {
    #expect(LocationText.timeZone("Asia/Riyadh", locale: english) == "Asia/Riyadh")
    #expect(
      LocationText.timeZone("Asia/Riyadh", locale: AppLanguage.french.locale) == "Asia/Riyadh")
    #expect(plain(LocationText.timeZone("Asia/Riyadh", locale: arabic)) == "توقيت الرياض")
  }

  // MARK: - Calculation

  /// Choosing a method by hand turns suggesting from the location off, so the choice
  /// stays when Salah moves; the pop-up stays enabled while it's on.
  @Test func choosingAMethodByHandTurnsSuggestionsOff() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    #expect(preferences.autoDetectMethod)
    preferences.chooseMethod(.egyptian)
    #expect(!preferences.autoDetectMethod)
    #expect(preferences.methodPreference == .egyptian)
    preferences.updateLocation(
      latitude: 21.4225, longitude: 39.8262, city: "Makkah", state: "Makkah",
      country: "SA", countryName: "Saudi Arabia", timeZone: "Asia/Riyadh")
    #expect(preferences.methodPreference == .egyptian)
  }

  /// Choosing a high-latitude rule by hand turns choosing automatically off.
  @Test func choosingARuleByHandTurnsAutomaticOff() {
    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    #expect(preferences.autoDetectHighLatitudeRule)
    preferences.chooseHighLatitudeRule(.twilightAngle)
    #expect(!preferences.autoDetectHighLatitudeRule)
    #expect(preferences.highLatitudeRulePreference == .twilightAngle)
    preferences.updateLocation(
      latitude: 59.3293, longitude: 18.0686, city: "Stockholm", state: "Stockholm",
      country: "SE", countryName: "Sweden", timeZone: "Europe/Stockholm")
    #expect(preferences.highLatitudeRulePreference == .twilightAngle)
  }

  /// The switches' details name what Salah would choose: the method for the country, and
  /// the rule here. Arabic joins ل to a country with the article as لل.
  @Test func theSuggestionsNameWhatSalahWouldChoose() {
    #expect(
      CalculationText.methodSuggestion(.ummAlQura, country: "Saudi Arabia", locale: english)
        == "Umm al-Qura for Saudi Arabia")
    #expect(
      plain(CalculationText.methodSuggestion(.ummAlQura, country: "السعودية", locale: arabic))
        == "أم القرى للسعودية")
    #expect(
      plain(CalculationText.methodSuggestion(.egyptian, country: "مصر", locale: arabic))
        == "الهيئة المصرية العامة لمصر")
    #expect(CalculationText.methodSuggestion(.ummAlQura, country: "", locale: english) == nil)
    #expect(
      CalculationText.ruleSuggestion(.middleOfTheNight, locale: english)
        == "Middle of the night here")
    #expect(
      plain(CalculationText.ruleSuggestion(.middleOfTheNight, locale: arabic)) == "منتصف الليل هنا")

    let scratch = ScratchDefaults()
    let preferences = Preferences(defaults: scratch.defaults)
    #expect(preferences.suggestedMethod == .ummAlQura)
    #expect(preferences.suggestedHighLatitudeRule == .middleOfTheNight)
  }

  // MARK: - Adjustments and Notifications

  /// The Ramadan switch's detail gives Isha's minutes in the language's digits and plural,
  /// and the method that delays it.
  @Test func theRamadanDetailNamesItsMinutesAndMethod() {
    #expect(
      AdjustmentsContent.delayedIshaDetail(method: .ummAlQura, locale: english)
        == "Isha 120 min after Maghrib, for Umm al-Qura")
    #expect(
      AdjustmentsContent.delayedIshaDetail(method: .ummAlQura, locale: arabic)
        .contains("العشاء بعد المغرب بـ"))
    #expect(
      AdjustmentsContent.delayedIshaDetail(method: .ummAlQura, locale: arabic)
        .contains("١٢٠ دقيقة"))
    #expect(
      plain(AdjustmentsContent.delayedIshaDetail(method: .ummAlQura, locale: arabic))
        .hasSuffix("في أم القرى"))
    for language in AppLanguage.concreteCases {
      let detail = AdjustmentsContent.delayedIshaDetail(method: .qatar, locale: language.locale)
      #expect(!detail.contains("%"), "\(language): \(detail)")
    }
  }

  /// A prayer's own minutes: "0 min" / "٠ د".
  @Test func aPrayersMinutesUseTheShortUnit() {
    #expect(AdjustmentRow.valueText(0, locale: english) == "0 min")
    #expect(AdjustmentRow.valueText(-5, locale: english) == "-5 min")
    #expect(plain(AdjustmentRow.valueText(0, locale: arabic)) == "٠ د")
  }

  /// A reminder's minutes take each language's plural: Arabic says "١٠ دقائق" and "٣٠
  /// دقيقة", and words for one and two.
  @Test func aRemindersMinutesTakeThePlural() {
    #expect(NotificationsContent.minutesText(10, locale: english) == "10 min")
    let arabicMinutes = [1, 2, 10, 30, 120].map {
      NotificationsContent.minutesText($0, locale: arabic)
    }
    #expect(arabicMinutes == ["دقيقة واحدة", "دقيقتان", "١٠ دقائق", "٣٠ دقيقة", "١٢٠ دقيقة"])
  }

  /// The Notifications picker spells Jumu'ah with its ’.
  @Test func thePickerSpellsJumuahWithItsApostrophe() {
    #expect(NotificationTarget.jumuah.name(NotificationTarget.names(locale: english)) == "Jumu’ah")
    #expect(NotificationTarget.jumuah.name(NotificationTarget.names(locale: arabic)) == "الجمعة")
  }

  /// The soft tone is a sound of its own, after the adhans, and not an adhan.
  @Test func theSoftToneIsATone() {
    #expect(AdhanSound.toneSounds == [.softTone])
    #expect(!AdhanSound.adhanSounds.contains(.softTone))
    #expect(!BuiltInAdhanSound.softTone.isAdhan)
    #expect(BuiltInAdhanSound.softTone.bundledURL != nil)
  }

  /// The language pop-up names the language macOS uses beside System.
  @Test func theSystemChoiceNamesMacOSsLanguage() {
    let title = LanguagePicker.systemTitle(locale: english)
    #expect(title == "System (\(LanguagePicker.systemLanguageName(in: english)))")
    #expect(LanguagePicker.systemTitle(locale: arabic).hasPrefix("النظام ("))
  }

  /// The text without the isolates Foundation puts around an argument in a right-to-left
  /// language, which change how it reads in no way.
  private func plain(_ text: String?) -> String? {
    text.map { plain($0) }
  }

  private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{2068}", with: "").replacingOccurrences(
      of: "\u{2069}", with: "")
  }
}
