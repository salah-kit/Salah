import Foundation
import Testing

@Suite("The watch's languages")
@MainActor
struct WatchLocalizationTests {
  init() { WatchTestResources.use() }

  /// The watch's own text comes from its catalog, in the language chosen on the iPhone.
  @Test(
    arguments: [
      ("en", "Set up Salah on your iPhone"), ("ar", "أعدّ صلاة على جهاز iPhone"),
      ("fr", "Configurez Salah sur votre iPhone"), ("ur", "اپنے iPhone پر Salah ترتیب دیں"),
      ("id", "Atur Salah di iPhone Anda"), ("tr", "Salah’ı iPhone’unuzda kurun"),
      ("fa", "Salah را روی iPhone خود راه‌اندازی کنید"),
      ("bn", "আপনার iPhone-এ Salah সেট আপ করুন"), ("ms", "Sediakan Salah pada iPhone anda"),
    ])
  func watchTextIsInEveryLanguage(language: String, expected: String) {
    let copy = WatchCopy(locale: Locale(identifier: language))
    #expect(copy("Set up Salah on your iPhone", "أعدّ صلاة على جهاز iPhone") == expected)
  }

  /// Text the watch shares with the iPhone app reads the same on both.
  @Test func sharedTextMatchesTheIPhone() {
    let french = WatchCopy(locale: Locale(identifier: "fr"))
    #expect(french("Compass unavailable", "البوصلة غير متاحة") == "Boussole indisponible")
  }

  @Test func theCatalogHasEveryLanguage() {
    let languages: Set = ["en", "ar", "fr", "ur", "id", "tr", "fa", "bn", "ms"]
    #expect(languages.isSubset(of: Set(AppResources.bundle.localizations)))
  }
}
