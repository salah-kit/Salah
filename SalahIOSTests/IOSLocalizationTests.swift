import Foundation
import SalahCore
import Testing

@Suite("iOS explicit language selection")
struct IOSLocalizationTests {
  private var resources: Bundle { Bundle(for: IOSLocalizationResources.self) }

  @Test(
    arguments: [
      ("en", "Location"), ("ar", "الموقع"), ("fr", "Lieu"), ("ur", "مقام"),
      ("id", "Lokasi"), ("tr", "Konum"), ("fa", "موقعیت مکانی"),
      ("bn", "অবস্থান"), ("ms", "Lokasi"),
    ])
  func selectedLanguageLoadsItsOwnCatalogWithoutChangingTheProcess(
    language: String, expected: String
  ) {
    #expect(
      IOSL10n.text("Location", locale: Locale(identifier: language), bundle: resources) == expected)
  }

  @Test func languageSwitchChangesTheSameKeyImmediately() {
    let french = IOSL10n.text("Location", locale: Locale(identifier: "fr"), bundle: resources)
    let turkish = IOSL10n.text("Location", locale: Locale(identifier: "tr"), bundle: resources)
    #expect(french == "Lieu")
    #expect(turkish == "Konum")
  }

  @Test func contextualArabicRetainsTheDesignWording() {
    let locale = Locale(identifier: "ar-u-nu-arab")
    #expect(IOSL10n.text("None", arabic: "بلا صوت", locale: locale, bundle: resources) == "بلا صوت")
    #expect(
      IOSL10n.text("None", arabic: "بلا تعديل", locale: locale, bundle: resources) == "بلا تعديل")
  }

  @Test func anUnknownKeyFallsBackToItsReadableEnglishText() {
    #expect(
      IOSL10n.text("Readable missing copy", locale: Locale(identifier: "fr"), bundle: resources)
        == "Readable missing copy")
  }

  /// Where the region counts in Hijri, Times' title still gives the Gregorian date above the
  /// Hijri one, for a day and for its week.
  @Test(arguments: [("en_SA", "June 2026"), ("ar_SA", "يونيو")])
  func timesTitleIsGregorianWhereTheRegionCountsInHijri(identifier: String, month: String) throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    let text = SalahText(locale: Locale(identifier: identifier), timeZone: timeZone)
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let week = (0..<7).map { day.adding(days: $0) }
    #expect(IOSTimesView.dateTitle(day: day, week: [], text: text).contains(month))
    #expect(IOSTimesView.dateTitle(day: day, week: week, text: text).contains(month))
  }

  /// A week row's day number is in the same calendar as the title above it: Solar Hijri in
  /// Persian, where 2 June 2026 is 12 Khordad.
  @Test func weekRowsNumberTheirDaysInTheTitlesCalendar() throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Tehran"))
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let persian = SalahText(locale: AppLanguage.persian.locale, timeZone: timeZone)
    #expect(IOSTimesView.dayNumber(day, text: persian).contains("۱۲"))
    let english = SalahText(locale: AppLanguage.english.locale, timeZone: timeZone)
    #expect(IOSTimesView.dayNumber(day, text: english) == "2")
  }

  @Test func catalogTemplatesRetainTheChosenLanguagesWordOrder() {
    #expect(
      IOSL10n.format(
        "Turn %@ right", locale: Locale(identifier: "fr"), bundle: resources, arguments: "20°")
        == "Tournez de 20° à droite")
    #expect(
      IOSL10n.format(
        "%@ ago", locale: Locale(identifier: "tr"), bundle: resources, arguments: "5 dk")
        == "5 dk önce")
  }
}

private final class IOSLocalizationResources: NSObject {}
