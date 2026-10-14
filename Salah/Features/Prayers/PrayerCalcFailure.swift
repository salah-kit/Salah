import Foundation

/// The schedule has no prayer times today for the current coordinates: SalahCalculation
/// can't give the day, as for coordinates SalahTimes rejects. Terminal: retrying with
/// the same coordinates won't help; the user needs a different location. Surfaced once,
/// never as a modal.
enum PrayerCalcFailure: AppFailure {
  case timesUnavailable(latitude: Double, longitude: Double)

  var category: FailureCategory { .terminal }

  var messageKey: String.LocalizationValue { "prayer.error.timesUnavailable" }

  /// Logged publicly, so without the coordinates: they're the user's location.
  var logMessage: String {
    switch self {
    case .timesUnavailable: "No prayer times for the current location"
    }
  }
}
