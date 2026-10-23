import Foundation
import SalahCore
import Testing

/// The dropdown's words, as Figma writes them: how long ago a prayer began, minutes in the
/// language's words and plural forms, the hero's footer, the banner's title and the alert
/// toggle's name.
@Suite("Dropdown text")
struct MenuDropdownTextTests {
  init() { TestEnvironment.configure() }

  let english = AppLanguage.english.locale
  let arabic = AppLanguage.arabic.locale

  func plain(_ string: String) -> String {
    string.replacingOccurrences(of: "\u{2068}", with: "")
      .replacingOccurrences(of: "\u{2069}", with: "")
  }

  /// "1 hr ago", not the formatter's "1 hr. ago"; Arabic "منذ", with real plurals.
  @Test func agoReadsAsFigmaWritesIt() {
    let cases: [(TimeInterval, String, String)] = [
      (60 * 60, "1 hr ago", "منذ ساعة"),
      (186 * 60, "3 hr ago", "منذ ٣ ساعات"),
      (4 * 60, "4 min ago", "منذ ٤ دقائق"),
      (2 * 60, "2 min ago", "منذ دقيقتين"),
      (61 * 60, "1 hr ago", "منذ ساعة"),
      (30, "1 min ago", "منذ دقيقة"),
    ]
    for (seconds, en, ar) in cases {
      #expect(plain(MenuDuration.ago(seconds, locale: english)) == en)
      #expect(plain(MenuDuration.ago(seconds, locale: arabic)) == ar)
    }
  }

  /// Arabic minutes are words with their plural forms; English keeps "min".
  @Test func minutesTakeTheLanguagesPluralForms() {
    let arabicMinutes = [1, 2, 4, 10, 11, 30, 100].map { MenuDuration.minutes($0, locale: arabic) }
    #expect(
      arabicMinutes == [
        "دقيقة", "دقيقتين", "٤ دقائق", "١٠ دقائق", "١١ دقيقة", "٣٠ دقيقة", "١٠٠ دقيقة",
      ])
    #expect(MenuDuration.minutes(10, locale: english) == "10 min")
    #expect(MenuDuration.minutes(1, locale: english) == "1 min")
    #expect(MenuDuration.hours(3, locale: arabic) == "٣ ساعات")
  }

  /// Every language has the minutes, the hours and the "ago" template, in its own digits.
  @Test func everyLanguageHasTheDurations() {
    for language in AppLanguage.allCases where language != .system {
      let locale = language.locale
      let digits = SalahText(locale: locale, timeZone: Fixture.timeZone).digits(10)
      let minutes = MenuDuration.minutes(10, locale: locale)
      #expect(minutes.contains(digits), "\(language): \(minutes)")
      #expect(!minutes.contains("%"), "\(language): \(minutes)")
      let ago = MenuDuration.ago(3 * 3_600, locale: locale)
      #expect(!ago.contains("%") && ago != "menu.row.ago", "\(language): \(ago)")
    }
  }

  /// The row's "in 10 min" says the minutes in words in Arabic; from an hour on it's "2:16".
  /// The approaching countdown keeps the short unit, and the count-up says words.
  @Test func rowsAndTheHeroSayTheMinutesAsFigmaDoes() {
    #expect(MenuDuration.until(10 * 60, locale: english) == "10 min")
    #expect(MenuDuration.until(10 * 60, locale: arabic) == "١٠ دقائق")
    #expect(plain(MenuDuration.until(136 * 60, locale: arabic)) == "٢:١٦")
    #expect(MenuDuration.string(10 * 60, locale: english) == "10 min")
    #expect(MenuDuration.string(10 * 60, locale: arabic) == "١٠ د")
    #expect(MenuDuration.string(4 * 60, countingUp: true, locale: english) == "+4 min")
    #expect(MenuDuration.string(4 * 60, countingUp: true, locale: arabic) == "+٤ دقائق")
    #expect(MenuDuration.reminder(minutes: 10, locale: arabic) == "١٠ دقائق")
    #expect(MenuDuration.reminder(minutes: 30, locale: arabic) == "٣٠ دقيقة")
    #expect(MenuDuration.reminder(minutes: 10, locale: english) == "10 min")
    #expect(MenuDuration.reminder(minutes: 60, locale: english) == "1 hr")
  }

  /// Silent mode hides the adhan's footer, which won't sound, and keeps the reminder's,
  /// whose banner still shows.
  @Test func silentModeKeepsTheReminderFooter() {
    let asr = PrayerAlerts(alert: true, beforeMinutes: 10)
    #expect(
      MenuHeroFooter(alerts: asr, isPrayer: true, isApproaching: false, silentMode: true)
        == .reminder(minutes: 10))
    #expect(
      MenuHeroFooter(alerts: asr, isPrayer: true, isApproaching: false, silentMode: false)
        == .reminder(minutes: 10))
    let alertOnly = PrayerAlerts(alert: true)
    #expect(
      MenuHeroFooter(alerts: alertOnly, isPrayer: true, isApproaching: false, silentMode: true)
        == .none)
    #expect(
      MenuHeroFooter(alerts: alertOnly, isPrayer: true, isApproaching: false, silentMode: false)
        == .adhan)
    #expect(
      MenuHeroFooter(alerts: asr, isPrayer: true, isApproaching: true, silentMode: false)
        == .adhan)
    #expect(
      MenuHeroFooter(alerts: asr, isPrayer: true, isApproaching: true, silentMode: true) == .none)
  }

  /// Location access denied has its own short banner title; other failures keep their
  /// message.
  @Test @MainActor func deniedLocationHasItsOwnBannerTitle() {
    AppLanguageScope.with(.english) {
      let denied = FailureNotice(
        domain: .location, category: .terminal, messageKey: LocationFailure.denied.messageKey,
        bannerTitleKey: LocationFailure.denied.bannerTitleKey)
      #expect(denied.bannerTitle == "Location is off for Salah")
      let restricted = FailureNotice(
        domain: .location, category: .terminal,
        messageKey: LocationFailure.restricted.messageKey,
        bannerTitleKey: LocationFailure.restricted.bannerTitleKey)
      #expect(restricted.bannerTitle == restricted.message)
    }
    AppLanguageScope.with(.arabic) {
      let denied = FailureNotice(
        domain: .location, category: .terminal, messageKey: LocationFailure.denied.messageKey,
        bannerTitleKey: LocationFailure.denied.bannerTitleKey)
      #expect(denied.bannerTitle == "الموقع متوقف لتطبيق صلاة")
    }
  }

  /// The alert toggle reads "Alert for Asr, on".
  @Test func theAlertToggleSaysItsPrayerAndState() {
    #expect(MenuBellLabel.name(prayer: "Asr", day: nil, locale: english) == "Alert for Asr")
    #expect(
      MenuBellLabel.name(prayer: "Fajr", day: "Tomorrow", locale: english)
        == "Tomorrow · Alert for Fajr")
    #expect(MenuBellLabel.value(isOn: true, locale: english) == "on")
    #expect(MenuBellLabel.value(isOn: false, locale: english) == "off")
    #expect(plain(MenuBellLabel.name(prayer: "العصر", day: nil, locale: arabic)) == "تنبيه العصر")
  }
}
