import CoreLocation
import Foundation
import MapKit
import Observation
import SalahCore
import UIKit

/// A compass is useful for Qibla only when it measures true north with usable accuracy.
nonisolated enum IOSHeadingState: Equatable, Sendable {
  case unavailable
  case calibrating
  case ready(trueHeading: Double, accuracy: Double)

  static func reading(trueHeading: Double, accuracy: Double) -> Self {
    guard trueHeading.isFinite, accuracy.isFinite, trueHeading >= 0, accuracy >= 0,
      accuracy <= 15
    else { return .calibrating }
    return .ready(trueHeading: trueHeading.truncatingRemainder(dividingBy: 360), accuracy: accuracy)
  }
}

/// Owns foreground location and heading sensors. A missing fix never becomes a sample city.
@MainActor @Observable
final class IOSLocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
  private(set) var authorizationStatus: IOSPermissionStatus = .notDetermined
  private(set) var location: PrayerLocation?
  private(set) var isLocating = false
  private(set) var errorMessage: String?
  private(set) var heading: IOSHeadingState = .unavailable
  var onLocationChanged: ((PrayerLocation) -> Void)?
  var onAuthorizationChanged: ((IOSPermissionStatus) -> Void)?

  @ObservationIgnored private let manager: CLLocationManager
  @ObservationIgnored private var geocoding: MKReverseGeocodingRequest?
  @ObservationIgnored private var resolveTask: Task<Void, Never>?
  @ObservationIgnored private var requestGeneration = UUID()
  @ObservationIgnored private var wantsLocation = false
  @ObservationIgnored private var wantsHeading = false
  @ObservationIgnored private var orientationObserver: NSObjectProtocol?

  override convenience init() { self.init(manager: CLLocationManager()) }

  init(manager: CLLocationManager) {
    self.manager = manager
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    manager.distanceFilter = 1_000
    manager.headingFilter = 2
    refreshAuthorization()
  }

  func refreshAuthorization() {
    let status = Self.permission(manager.authorizationStatus)
    let changed = status != authorizationStatus
    authorizationStatus = status
    if changed { onAuthorizationChanged?(status) }
    if authorizationStatus == .denied || authorizationStatus == .restricted {
      cancelLocation()
      manager.stopUpdatingHeading()
      heading = .unavailable
      location = nil
    }
  }

  func requestLocation() {
    requestGeneration = UUID()
    geocoding?.cancel()
    resolveTask?.cancel()
    wantsLocation = true
    isLocating = true
    errorMessage = nil
    refreshAuthorization()
    switch authorizationStatus {
    case .notDetermined: manager.requestWhenInUseAuthorization()
    case .authorized: manager.requestLocation()
    case .denied, .restricted:
      isLocating = false
      errorMessage = "Location access is off. Enable it in Settings or choose a city."
    }
  }

  /// Cancels a GPS selection, including a geocode that might otherwise overwrite a manual city.
  func cancelLocation() {
    wantsLocation = false
    isLocating = false
    requestGeneration = UUID()
    resolveTask?.cancel()
    resolveTask = nil
    geocoding?.cancel()
    geocoding = nil
    if !wantsHeading { manager.stopUpdatingLocation() }
  }

  func startHeading() {
    wantsHeading = true
    refreshAuthorization()
    guard CLLocationManager.headingAvailable(), authorizationStatus == .authorized else {
      heading = .unavailable
      return
    }
    heading = .calibrating
    setHeadingOrientation(UIDevice.current.orientation)
    if orientationObserver == nil {
      UIDevice.current.beginGeneratingDeviceOrientationNotifications()
      orientationObserver = NotificationCenter.default.addObserver(
        forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.setHeadingOrientation(UIDevice.current.orientation) }
      }
    }
    // Core Location needs a location fix to correct magnetic north to true north.
    manager.startUpdatingLocation()
    manager.startUpdatingHeading()
  }

  func stopHeading() {
    wantsHeading = false
    manager.stopUpdatingHeading()
    heading = .unavailable
    if let orientationObserver {
      NotificationCenter.default.removeObserver(orientationObserver)
      self.orientationObserver = nil
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    if !wantsLocation { manager.stopUpdatingLocation() }
  }

  /// iOS 27 uses the rendered view's body, keeping heading correct in rotated iPad layouts.
  func setHeadingReferenceView(_ view: UIView?) {
    if #available(iOS 27.0, *) { manager.headingBody = view }
  }

  func setHeadingOrientation(_ orientation: UIDeviceOrientation) {
    if #available(iOS 27.0, *) { return }
    switch orientation {
    case .portrait: manager.headingOrientation = .portrait
    case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
    case .landscapeLeft: manager.headingOrientation = .landscapeLeft
    case .landscapeRight: manager.headingOrientation = .landscapeRight
    default: break
    }
  }

  isolated deinit {
    if let orientationObserver {
      NotificationCenter.default.removeObserver(orientationObserver)
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    refreshAuthorization()
    if authorizationStatus == .authorized {
      if wantsLocation { self.manager.requestLocation() }
      if wantsHeading { startHeading() }
    } else if authorizationStatus == .denied || authorizationStatus == .restricted {
      errorMessage = "Location access is off. Enable it in Settings or choose a city."
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard wantsLocation, let fix = locations.last,
      Self.isUsableFix(accuracy: fix.horizontalAccuracy, age: -fix.timestamp.timeIntervalSinceNow)
    else { return }
    if !wantsHeading { manager.stopUpdatingLocation() }
    let generation = requestGeneration
    geocoding?.cancel()
    resolveTask?.cancel()
    guard let request = MKReverseGeocodingRequest(location: fix) else {
      isLocating = false
      errorMessage = "This location could not be resolved. Try again or choose a city."
      return
    }
    geocoding = request
    resolveTask = Task { [weak self] in
      do {
        let items = try await request.mapItems
        try Task.checkCancellation()
        guard let self, self.requestGeneration == generation, self.wantsLocation else { return }
        guard let item = items.first,
          let resolved = IOSMapLocation.resolve(item, coordinate: fix.coordinate)
        else { throw IOSLocationError.unresolvedTimeZone }
        self.location = resolved
        self.isLocating = false
        self.wantsLocation = false
        self.errorMessage = nil
        self.onLocationChanged?(resolved)
      } catch is CancellationError {
      } catch {
        guard let self, self.requestGeneration == generation else { return }
        self.isLocating = false
        self.errorMessage =
          "Could not find this location’s time zone. Check your connection or choose a city."
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    guard wantsHeading else { return }
    heading = IOSHeadingState.reading(
      trueHeading: newHeading.trueHeading, accuracy: newHeading.headingAccuracy)
  }

  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
    wantsHeading
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    guard wantsLocation else { return }
    isLocating = false
    refreshAuthorization()
    errorMessage = "Could not get your location. Try again outdoors or choose a city."
  }

  nonisolated static func isUsableFix(accuracy: Double, age: TimeInterval) -> Bool {
    accuracy.isFinite && accuracy >= 0 && accuracy <= 5_000 && age >= -5 && age <= 120
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
