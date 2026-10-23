import Foundation
import SalahCore
import Testing

/// Salah's text for times and durations. Countdowns, count-ups and "since" text now come
/// from SalahCore's `PrayerDurationFormat` (the app's own formatter moved there, with its
/// tests); these pin that the menu bar and the widgets still read as they did in English,
/// Arabic and French, and that clock times keep Salah's "j:mm a" form.
@Suite("Salah text")
struct SalahTextTests {
  init() { TestEnvironment.configure() }

  let english = SalahText(locale: AppLanguage.english.locale, timeZone: Fixture.timeZone)
  let arabic = SalahText(locale: AppLanguage.arabic.locale, timeZone: Fixture.timeZone)
  let french = SalahText(locale: AppLanguage.french.locale, timeZone: Fixture.timeZone)

  /// The three tiers, rounded down, with "+" for a count-up; the app's formatter gave the
  /// same strings in these languages.
  @Test func durationsKeepTheirTiers() {
    let inputs: [TimeInterval] = [0, 45, 59, 60, 61, 49 * 60, 3_599, 3_600, 3_661, 10_140]
    #expect(
      inputs.map { english.duration($0) }
        == ["0s", "45s", "59s", "1m", "1m", "49m", "59m", "1:00", "1:01", "2:49"])
    #expect(
      inputs.map { arabic.duration($0) }
        == ["٠ث", "٤٥ث", "٥٩ث", "١د", "١د", "٤٩د", "٥٩د", "١:٠٠", "١:٠١", "٢:٤٩"])
    #expect(
      inputs.map { french.duration($0) }
        == ["0s", "45s", "59s", "1min", "1min", "49min", "59min", "1:00", "1:01", "2:49"])
    #expect(english.duration(16 * 60, direction: .elapsed) == "+16m")
    #expect(arabic.duration(45, direction: .elapsed) == "+٤٥ث")
    #expect(english.duration(-5) == "0s")
    #expect(english.duration(3_600, bidiIsolated: true) == "\u{2068}1:00\u{2069}")
  }

  /// The menu bar's countdown and count-up are these durations, bidi-isolated.
  @Test func theMenuBarCountsDownAndUp() {
    let formatter = PrayerDisplayFormatter(timeZone: Fixture.timeZone)
    let start = Fixture.date(13, 0)
    AppLanguageScope.with(.english) {
      #expect(
        formatter.countdown(from: start, to: start.adding(minutes: 49)) == "\u{2068}49m\u{2069}")
      #expect(
        formatter.countUp(from: start, to: start.adding(seconds: 45)) == "\u{2068}+45s\u{2069}")
    }
  }

  /// Clock times keep Salah's form: the locale's short time, with the leading zero a
  /// 24-hour locale writes ("04:11"), bidi-isolated; the compact form drops the period.
  @Test func clockTimesKeepSalahsForm() {
    let fajr = Fixture.time(.fajr)
    let asr = Fixture.time(.asr)
    #expect(english.time(fajr) == "\u{2068}4:11\u{202F}AM\u{2069}")
    #expect(french.time(fajr) == "\u{2068}04:11\u{2069}")
    #expect(french.time(asr) == "\u{2068}15:35\u{2069}")
    #expect(arabic.time(asr) == "\u{2068}٣:٣٥\u{00A0}م\u{2069}")
    #expect(english.compactTime(asr) == "\u{2068}3:35\u{2069}")
  }

  /// Reminder phrases keep each language's word order and unit spacing.
  @Test func reminderPhrases() {
    #expect(english.offsetPhrase(10, before: true) == "\u{2068}10m\u{2069} before")
    #expect(arabic.offsetPhrase(10, before: true) == "قبل \u{2068}١٠ د\u{2069}")
    #expect(french.offsetPhrase(5, before: false) == "\u{2068}5 min\u{2069} après")
  }

  /// The header's dates follow Figma: the Hijri year has no era, in every language, and
  /// the Arabic Gregorian date has no comma before its year.
  @Test func theHeaderDatesHaveNoEraAndArabicHasNoCommaBeforeTheYear() {
    let date = Fixture.date(13, 19)
    let englishHijri = english.hijri(date, dayOffset: 0)
    #expect(
      [englishHijri.day, englishHijri.month, englishHijri.year] == ["16", "Dhuʻl-Hijjah", "1447"])
    let arabicHijri = arabic.hijri(date, dayOffset: 0)
    #expect([arabicHijri.day, arabicHijri.month, arabicHijri.year] == ["١٦", "ذو الحجة", "١٤٤٧"])
    for language in AppLanguage.allCases where language != .system {
      let text = SalahText(locale: language.locale, timeZone: Fixture.timeZone)
      let year = text.hijri(date, dayOffset: 0).year
      #expect(year == text.digits(1447), "\(language): \(year)")
    }
    #expect(english.gregorianDate(date) == "Tuesday, June 2, 2026")
    #expect(arabic.gregorianDate(date) == "الثلاثاء، ٢ يونيو ٢٠٢٦")
    #expect(french.gregorianDate(date) == "mardi 2 juin 2026")
  }
}
