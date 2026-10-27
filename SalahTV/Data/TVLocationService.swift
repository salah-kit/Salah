import CoreLocation
import Foundation
import MapKit
import Observation
import SalahCore

/// One location request with When In Use permission. An Apple TV doesn't move, so a single
/// fix is enough, and Allow Once is too. A missing fix never becomes a sample city.
@MainActor @Observable
final class TVLocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
  private(set) var authorizationStatus: IOSPermissionStatus = .notDetermined
  private(set) var isLocating = false
  private(set) var errorMessage: TVLocationError?
  @ObservationIgnored var onLocationChanged: ((PrayerLocation) -> Void)?
  @ObservationIgnored var onAuthorizationChanged: ((IOSPermissionStatus) -> Void)?

  @ObservationIgnored private let manager: CLLocationManager
  @ObservationIgnored private var resolveTask: Task<Void, Never>?
  @ObservationIgnored private var geocoding: MKReverseGeocodingRequest?
  @ObservationIgnored private var requestGeneration = UUID()
  @ObservationIgnored private var wantsLocation = false

  override convenience init() { self.init(manager: CLLocationManager()) }

  init(manager: CLLocationManager) {
    self.manager = manager
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    refreshAuthorization()
  }

  func refreshAuthorization() {
    let status = Self.permission(manager.authorizationStatus)
    let changed = status != authorizationStatus
    authorizationStatus = status
    if changed { onAuthorizationChanged?(status) }
    if status == .denied || status == .restricted, wantsLocation {
      cancelLocation()
      errorMessage = .accessOff
    }
  }

  /// Asks once for permission if needed, then for one fix, which is resolved to its city and
  /// time zone.
  func requestLocation() {
    cancelLocation()
    wantsLocation = true
    isLocating = true
    errorMessage = nil
    refreshAuthorization()
    switch authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorized: manager.requestLocation()
    case .denied, .restricted:
      wantsLocation = false
      isLocating = false
      errorMessage = .accessOff
    }
  }

  /// Cancels a request, including a city lookup that might otherwise replace a chosen city.
  func cancelLocation() {
    wantsLocation = false
    isLocating = false
    requestGeneration = UUID()
    resolveTask?.cancel()
    resolveTask = nil
    geocoding?.cancel()
    geocoding = nil
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    refreshAuthorization()
    if authorizationStatus == .authorized, wantsLocation, resolveTask == nil {
      manager.requestLocation()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard wantsLocation, resolveTask == nil else { return }
    // `requestLocation()` delivers one update, so a request without a usable fix ends here.
    guard
      let fix = locations.last(where: {
        Self.isUsableFix(
          accuracy: $0.horizontalAccuracy, age: -$0.timestamp.timeIntervalSinceNow,
          reducedAccuracy: manager.accuracyAuthorization == .reducedAccuracy)
      })
    else {
      finish(with: .noFix)
      return
    }
    guard let request = MKReverseGeocodingRequest(location: fix) else {
      finish(with: .unresolved)
      return
    }
    let generation = requestGeneration
    geocoding = request
    resolveTask = Task { [weak self] in
      do {
        let items = try await request.mapItems
        try Task.checkCancellation()
        guard let self, self.requestGeneration == generation, self.wantsLocation else { return }
        guard let item = items.first,
          let resolved = IOSMapLocation.resolve(item, coordinate: fix.coordinate)
        else { throw IOSLocationError.unresolvedTimeZone }
        self.wantsLocation = false
        self.isLocating = false
        self.resolveTask = nil
        self.geocoding = nil
        self.onLocationChanged?(resolved)
      } catch is CancellationError {
      } catch {
        guard let self, self.requestGeneration == generation else { return }
        self.finish(with: .unresolved)
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    guard wantsLocation, resolveTask == nil else { return }
    refreshAuthorization()
    guard wantsLocation else { return }
    finish(with: .noFix)
  }

  private func finish(with error: TVLocationError) {
    cancelLocation()
    errorMessage = error
  }

  /// Approximate location reports fixes about 5 km wide and up to 20 minutes old. Within 20 km,
  /// prayer times usually move by under a minute.
  nonisolated static func isUsableFix(
    accuracy: Double, age: TimeInterval, reducedAccuracy: Bool = false
  ) -> Bool {
    let maximumAccuracy: Double = reducedAccuracy ? 20_000 : 5_000
    let maximumAge: TimeInterval = reducedAccuracy ? 1_200 : 120
    return accuracy.isFinite && accuracy >= 0 && accuracy <= maximumAccuracy && age >= -5
      && age <= maximumAge
  }

  nonisolated static func permission(_ status: CLAuthorizationStatus) -> IOSPermissionStatus {
    switch status {
    case .authorizedAlways, .authorizedWhenInUse: .authorized
    case .denied: .denied
    case .restricted: .restricted
    case .notDetermined: .notDetermined
    @unknown default: .restricted
    }
  }
}

/// Why a location request ended without a city.
nonisolated enum TVLocationError: Equatable, Sendable {
  /// Location access is off for Salah, or Location Services are off.
  case accessOff
  /// Core Location gave no fix.
  case noFix
  /// The fix couldn't be resolved to a city and its time zone.
  case unresolved

  func message(_ copy: TVCopy) -> String {
    switch self {
    case .accessOff:
      copy(
        "Location access is off for Salah. Turn it on in Settings, or choose a city.",
        "الوصول إلى الموقع متوقف لتطبيق صلاة. شغّله من الإعدادات، أو اختر مدينة.")
    case .noFix:
      copy(
        "This Apple TV couldn’t find its location. Try again or choose a city.",
        "تعذّر على جهاز Apple TV هذا تحديد موقعه. حاول مرة أخرى أو اختر مدينة.")
    case .unresolved:
      copy(
        "Couldn’t find this location’s city and time zone. Check the connection or choose a city.",
        "تعذّر العثور على مدينة هذا الموقع ومنطقته الزمنية. تحقّق من الاتصال أو اختر مدينة.")
    }
  }
}
