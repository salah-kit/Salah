import Foundation

/// Salah's default place, Makkah, until the current location or a chosen city replaces it.
/// Its names are stored in English, as earlier versions stored them; Salah shows them in its
/// own language.
nonisolated enum DefaultPlace {
  static let city = "Makkah"
  static let state = "Makkah"
  static let country = "SA"
  static let countryName = "Saudi Arabia"
  static let latitude = 21.4167
  static let longitude = 39.8167
  static let timeZone = "Asia/Riyadh"
}

extension Preferences {
  /// Whether the stored place is still the default one: its English names at its
  /// coordinates. A geocoded or chosen place, Makkah included, has names of its own and
  /// other coordinates.
  var isDefaultPlace: Bool {
    city == DefaultPlace.city && state == DefaultPlace.state
      && countryName == DefaultPlace.countryName && latitude == DefaultPlace.latitude
      && longitude == DefaultPlace.longitude
  }

  /// The city as Salah shows it: the default place's in `locale`'s language, any other as
  /// it was stored.
  func placeCity(locale: Locale) -> String {
    isDefaultPlace ? localizedString("location.default.city", locale: locale) : city
  }

  /// The region (state or province) as Salah shows it.
  func placeRegion(locale: Locale) -> String {
    isDefaultPlace ? localizedString("location.default.city", locale: locale) : state
  }

  /// The country as Salah shows it.
  func placeCountry(locale: Locale) -> String {
    isDefaultPlace ? localizedString("location.default.country", locale: locale) : countryName
  }
}
