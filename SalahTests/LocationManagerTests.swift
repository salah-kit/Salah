import CoreLocation
import Foundation
import Testing

/// "Use current location" decides whether Salah follows the Mac's location: with it off,
/// the permission macOS reports to every new location manager neither starts updates nor
/// moves the chosen place, and a fix that arrives late is dropped.
///
/// Regression: with the permission granted, every launch started location updates and
/// applied the fix whatever the setting, so the place a user (or a test launch) chose was
/// replaced by the Mac's own a moment after launch.
@Suite("LocationManager")
struct LocationManagerTests {
  init() { TestEnvironment.configure() }

  /// A location manager that records what it's asked to do.
  nonisolated final class RecordingLocationUpdater: LocationUpdating, @unchecked Sendable {
    // @unchecked: the tests use it on the main actor only.
    weak var delegate: (any CLLocationManagerDelegate)?
    var desiredAccuracy: CLLocationAccuracy = 0
    var distanceFilter: CLLocationDistance = 0
    var authorizationStatus: CLAuthorizationStatus = .authorized
    private(set) var calls: [String] = []

    func requestWhenInUseAuthorization() { calls.append("requestAuthorization") }
    func startUpdatingLocation() { calls.append("startUpdating") }
    func stopUpdatingLocation() { calls.append("stopUpdating") }
    func startMonitoringSignificantLocationChanges() { calls.append("startMonitoring") }
    func stopMonitoringSignificantLocationChanges() { calls.append("stopMonitoring") }
  }

  /// Preferences in Makkah, with "Use current location" as given.
  static func preferences(_ scratch: ScratchDefaults, useCurrentLocation: Bool) -> Preferences {
    let preferences = Preferences.scratch(scratch)
    preferences.updateLocation(
      latitude: 21.4167, longitude: 39.8167, city: "Makkah", state: "Makkah", country: "SA",
      countryName: "Saudi Arabia", timeZone: "Asia/Riyadh")
    preferences.useCurrentLocation = useCurrentLocation
    return preferences
  }

  /// Applies a fix in Sheikh Zayed, as a reverse geocode resolves it.
  static func applyFix(to manager: LocationManager) {
    manager.applyResolvedLocation(
      latitude: 30.0533, longitude: 31.0191, city: "Sheikh Zayed", state: "Giza",
      country: "EG", countryName: "Egypt", timeZone: "Africa/Cairo")
  }

  @Test func withCurrentLocationOffThePermissionStartsNothing() {
    let scratch = ScratchDefaults()
    let preferences = Self.preferences(scratch, useCurrentLocation: false)
    let updater = RecordingLocationUpdater()
    let manager = LocationManager(preferences: preferences, manager: updater)

    manager.handleAuthorizationStatus(.authorized)

    #expect(manager.authorizationStatus == .authorized)
    #expect(updater.calls.isEmpty)
    #expect(preferences.useCurrentLocation == false)
  }

  @Test func withCurrentLocationOffAFixKeepsTheChosenPlace() {
    let scratch = ScratchDefaults()
    let preferences = Self.preferences(scratch, useCurrentLocation: false)
    let manager = LocationManager(preferences: preferences, manager: RecordingLocationUpdater())

    Self.applyFix(to: manager)

    #expect(preferences.city == "Makkah")
    #expect(preferences.latitude == 21.4167)
    #expect(preferences.storedTimeZone == "Asia/Riyadh")
  }

  @Test func withCurrentLocationOnThePermissionStartsUpdatesAndAFixMovesThePlace() {
    let scratch = ScratchDefaults()
    let preferences = Self.preferences(scratch, useCurrentLocation: true)
    let updater = RecordingLocationUpdater()
    let manager = LocationManager(preferences: preferences, manager: updater)

    manager.handleAuthorizationStatus(.authorized)
    #expect(updater.calls == ["startUpdating", "startMonitoring"])

    Self.applyFix(to: manager)
    #expect(preferences.city == "Sheikh Zayed")
    #expect(preferences.latitude == 30.0533)
    #expect(preferences.storedTimeZone == "Africa/Cairo")
  }

  /// A denied permission turns "Use current location" off only while it's on; with it
  /// already off, nothing changes.
  @Test func aDeniedPermissionMattersOnlyWhileCurrentLocationIsOn() {
    let scratch = ScratchDefaults()
    let off = Self.preferences(scratch, useCurrentLocation: false)
    let offUpdater = RecordingLocationUpdater()
    LocationManager(preferences: off, manager: offUpdater).handleAuthorizationStatus(.denied)
    #expect(offUpdater.calls.isEmpty)

    let otherScratch = ScratchDefaults()
    let on = Self.preferences(otherScratch, useCurrentLocation: true)
    let onUpdater = RecordingLocationUpdater()
    LocationManager(preferences: on, manager: onUpdater).handleAuthorizationStatus(.denied)
    #expect(on.useCurrentLocation == false)
    #expect(onUpdater.calls == ["stopUpdating", "stopMonitoring"])
  }
}
