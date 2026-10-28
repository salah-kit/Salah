import CoreLocation
import Foundation
import Observation

/// The watch's compass, for the Qibla dial. The prayer times and the Qibla bearing come from
/// the place chosen on the iPhone; the watch's own location only corrects the compass to true
/// north, so the dial asks for When In Use access the first time it shows.
@MainActor @Observable
final class WatchHeadingService: NSObject, @preconcurrency CLLocationManagerDelegate {
  private(set) var heading: WatchHeading = .unavailable

  @ObservationIgnored private let manager: CLLocationManager
  @ObservationIgnored private let compassAvailable: Bool
  @ObservationIgnored private var wantsHeading = false

  override convenience init() {
    self.init(manager: CLLocationManager(), compassAvailable: CLLocationManager.headingAvailable())
  }

  init(manager: CLLocationManager, compassAvailable: Bool) {
    self.manager = manager
    self.compassAvailable = compassAvailable
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    manager.distanceFilter = 1_000
    manager.headingFilter = 2
  }

  /// Starts the compass while the dial shows, asking for location access first if the person
  /// hasn't been asked.
  func start() {
    wantsHeading = true
    update()
  }

  /// Stops the compass when the dial leaves the screen or Salah leaves the wrist.
  func stop() {
    wantsHeading = false
    manager.stopUpdatingHeading()
    manager.stopUpdatingLocation()
    if heading != .needsLocation { heading = .unavailable }
  }

  private func update() {
    guard wantsHeading else { return }
    guard compassAvailable else {
      heading = .unavailable
      return
    }
    switch manager.authorizationStatus {
    case .notDetermined:
      heading = .unavailable
      manager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      heading = .needsLocation
      manager.stopUpdatingHeading()
      manager.stopUpdatingLocation()
    default:
      if case .ready = heading {} else { heading = .calibrating }
      // Core Location needs a location fix to correct magnetic north to true north.
      manager.startUpdatingLocation()
      manager.startUpdatingHeading()
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    update()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    guard wantsHeading else { return }
    heading = .reading(trueHeading: newHeading.trueHeading, accuracy: newHeading.headingAccuracy)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

  /// A refused location is the person's choice; heading interference asks for calibration.
  /// Other failures, such as no fix yet, pass as Core Location keeps trying.
  func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
    guard wantsHeading else { return }
    switch (error as? CLError)?.code {
    case .denied?: heading = .needsLocation
    case .headingFailure?: heading = .calibrating
    default: break
    }
  }
}
