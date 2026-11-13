import CoreLocation
import Foundation
import MapKit
import SalahCore

/// Names a saved place in the language Salah is set to.
///
/// A place is saved with the name the geocoder gave it in the device's language. When Salah
/// uses another language, the widgets, the Live Activity, notifications and the app itself
/// would otherwise show that name among words of a different language.
@MainActor protocol IOSPlaceNaming {
  /// The place's name in `locale`'s language, or `nil` when it can't be found now.
  func name(of location: PrayerLocation, in locale: Locale) async -> String?
}

/// MapKit names the place at the saved coordinates in the requested language.
@MainActor final class IOSMapKitPlaceNamer: IOSPlaceNaming {
  func name(of location: PrayerLocation, in locale: Locale) async -> String? {
    let place = CLLocation(latitude: location.latitude, longitude: location.longitude)
    guard let request = MKReverseGeocodingRequest(location: place) else { return nil }
    request.preferredLocale = locale
    guard let item = try? await request.mapItems.first else { return nil }
    return item.addressRepresentations?.cityName ?? item.name
  }
}

/// The test fixture's place has a translated name in the catalog; nothing asks the network.
@MainActor struct IOSFixturePlaceNamer: IOSPlaceNaming {
  func name(of location: PrayerLocation, in locale: Locale) async -> String? {
    guard location.name == "Makkah" else { return nil }
    return IOSL10n.text("Makkah", arabic: "مكة المكرمة", locale: locale)
  }
}

/// One request for a place's name in a language.
nonisolated struct IOSPlaceQuestion: Equatable, Sendable {
  var location: PrayerLocation
  var languageCode: String
}
