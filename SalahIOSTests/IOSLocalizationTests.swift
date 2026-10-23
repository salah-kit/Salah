import Foundation
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
