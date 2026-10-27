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
    resolveTask = nil
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
    // Core Location needs a location fix to correct magnetic north to true north.
    manager.startUpdatingLocation()
    manager.startUpdatingHeading()
  }

  func stopHeading() {
    wantsHeading = false
    manager.stopUpdatingHeading()
    heading = .unavailable
    if !wantsLocation { manager.stopUpdatingLocation() }
  }

  /// iOS 27 uses the rendered view's body, keeping heading correct in rotated iPad layouts.
  func setHeadingReferenceView(_ view: UIView?) {
    if #available(iOS 27.0, *) { manager.headingBody = view }
  }

  /// Before iOS 27, heading follows the interface showing the dial, not the device: an interface
  /// keeps its orientation when the device lies flat or turns to an unsupported orientation.
  func setHeadingOrientation(_ orientation: UIInterfaceOrientation) {
    if #available(iOS 27.0, *) { return }
    if let reference = Self.headingOrientation(for: orientation) {
      manager.headingOrientation = reference
    }
  }

  /// The interface's top edge as a device orientation. Landscape names swap: the interface's
  /// landscape left is the device's landscape right.
  nonisolated static func headingOrientation(for orientation: UIInterfaceOrientation)
    -> CLDeviceOrientation?
  {
    switch orientation {
    case .portrait: .portrait
    case .portraitUpsideDown: .portraitUpsideDown
    case .landscapeLeft: .landscapeRight
    case .landscapeRight: .landscapeLeft
    case .unknown: nil
    @unknown default: nil
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
    guard wantsLocation, let fix = locations.last else { return }
    guard
      Self.isUsableFix(
        accuracy: fix.horizontalAccuracy, age: -fix.timestamp.timeIntervalSinceNow,
        reducedAccuracy: manager.accuracyAuthorization == .reducedAccuracy)
    else {
      // A single request delivers no other fix. If heading keeps updates running, a later usable
      // fix still resolves, since the request stays wanted. While a usable fix resolves, a
      // coarse one changes nothing.
      if resolveTask == nil { failLocation() }
      return
    }
    if !wantsHeading { manager.stopUpdatingLocation() }
    let generation = requestGeneration
    geocoding?.cancel()
    resolveTask?.cancel()
    isLocating = true
    errorMessage = nil
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
        self.resolveTask = nil
        self.onLocationChanged?(resolved)
      } catch is CancellationError {
      } catch {
        // A newer fix cancels this geocode, which can then throw MapKit's own error.
        guard let self, !Task.isCancelled, self.requestGeneration == generation else { return }
        self.resolveTask = nil
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
    failLocation()
  }

  private func failLocation() {
    isLocating = false
    refreshAuthorization()
    errorMessage = "Could not get your location. Try again outdoors or choose a city."
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
