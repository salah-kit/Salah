import CoreLocation
import MapKit
import SalahCore

nonisolated enum IOSLocationError: Error { case unresolvedTimeZone }

@MainActor enum IOSMapLocation {
  /// A city's own zone is mandatory; substituting the phone's zone makes distant times wrong.
  static func resolve(_ item: MKMapItem, coordinate: CLLocationCoordinate2D? = nil)
    -> PrayerLocation?
  {
    let coordinate = coordinate ?? item.location.coordinate
    guard CLLocationCoordinate2DIsValid(coordinate), let zone = item.timeZone else { return nil }
    return PrayerLocation(
      latitude: coordinate.latitude, longitude: coordinate.longitude, timeZone: zone,
      countryCode: item.addressRepresentations?.region?.identifier,
      name: item.addressRepresentations?.cityName ?? item.name ?? item.address?.shortAddress)
  }
}
