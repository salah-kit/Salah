import Foundation

/// The schedule has no prayer times today for the current coordinates: SalahCalculation
/// can't give the day, as for coordinates SalahTimes rejects. Terminal: retrying with
/// the same coordinates won't help; the user needs a different location. Surfaced once,
/// never as a modal.
enum PrayerCalcFailure: AppFailure {
  case timesUnavailable(latitude: Double, longitude: Double)

  var category: FailureCategory { .terminal }

  var messageKey: String.LocalizationValue { "prayer.error.timesUnavailable" }

  var logMessage: String {
    switch self {
    case .timesUnavailable(let lat, let lng):
      "No prayer times for (\(lat), \(lng))"
    }
  }
}
