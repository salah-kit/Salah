import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

// Compiled by both SalahRoundTripTests and SalahUITests (project.yml), so the tests that
// launch the real app place a prayer and set its preferences the same way.

/// A prayer moved to start at a whole minute a little ahead, through Salah's own minute
/// adjustments, so a test can wait for a real alert.
nonisolated struct PlacedPrayer: Sendable {
  /// Why a prayer couldn't be placed: the schedule had no event around the target.
  struct NoEventAround: Error, CustomStringConvertible {
    var target: Date
    var description: String { "No prayer event around \(target)" }
  }

  /// The prayer moved.
  var kind: PrayerKind
  /// The adjustment, in minutes, that puts it at `time`.
  var adjustment: Int
  /// When it starts now.
  var time: Date

  /// The preference key of the kind's adjustment.
  var adjustmentKey: String {
    switch kind {
    case .fajr: "salah.adjustmentFajr"
    case .sunrise: "salah.adjustmentShuruq"
    case .dhuhr: "salah.adjustmentDhuhr"
    case .asr: "salah.adjustmentAsr"
    case .maghrib: "salah.adjustmentMaghrib"
    case .isha: "salah.adjustmentIsha"
    }
  }

  /// Makkah with Salah's default calculation, the app's launch location.
  static var schedule: PrayerSchedule {
    var parameters = CalculationMethod.ummAlQura.parameters
    parameters.highLatitudeRule = .middleOfTheNight
    parameters.ramadanIsha = .interval(minutes: 120, hijriDayOffset: 0)
    let zone = TimeZone(identifier: "Asia/Riyadh") ?? .gmt
    return PrayerSchedule(
      source: CalculationSource(CalculationSettings(parameters: parameters)),
      location: PrayerLocation(latitude: 21.4167, longitude: 39.8167, timeZone: zone))
  }

  /// A prayer starting at the first whole minute at least `lead` from now. Between the
  /// two events around that minute, it moves the earlier one later if it's a prayer,
  /// otherwise the later one earlier, so the day keeps its order.
  static func soon(lead: TimeInterval, now: Date = Date()) throws -> PlacedPrayer {
    let target = Date(
      timeIntervalSinceReferenceDate: (now.addingTimeInterval(lead).timeIntervalSinceReferenceDate
        / 60).rounded(.up) * 60)
    let events = schedule.events(
      from: target.addingTimeInterval(-2 * 86_400), through: target.addingTimeInterval(2 * 86_400)
    ).events
    guard let before = events.last(where: { $0.time <= target }),
      let after = events.first(where: { $0.time > target })
    else { throw NoEventAround(target: target) }
    let moved = before.kind.isPrayer ? before : after
    let minutes = Int((target.timeIntervalSince(moved.time) / 60).rounded())
    return PlacedPrayer(kind: moved.kind, adjustment: minutes, time: target)
  }
}

/// Launch arguments: Makkah with Salah's default calculation and no adjustment but the
/// given one, no automatic location, no consent prompt of any kind, English, muted, and
/// every alert off but the given ones, in a scratch preferences suite (Debug builds),
/// so none of it reaches this Mac's own Salah preferences.
///
/// Every launch sets each preference the tests depend on, rather than inherit an earlier
/// launch's.
enum Launch {
  static func arguments(alerts: [PrayerKind: [String: Any]] = [:], placed: PlacedPrayer? = nil)
    -> [String]
  {
    var adjustments: [String] = []
    for kind in PrayerKind.allCases {
      let key = PlacedPrayer(kind: kind, adjustment: 0, time: Date()).adjustmentKey
      let minutes = placed?.kind == kind ? placed?.adjustment ?? 0 : 0
      // In property-list form: a bare "-106" would read as the next key.
      adjustments += ["-\(key)", "<integer>\(minutes)</integer>"]
    }
    var settings: [String: [String: Any]] = [:]
    for kind in PrayerKind.allCases {
      settings[kind.rawValue] = alerts[kind] ?? ["alertEnabled": false]
    }
    let json =
      (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]))
      ?? Data()
    let hex = "<" + json.map { String(format: "%02x", $0) }.joined() + ">"
    return [
      "-salah.autoLocation", "NO",
      "-salah.debug.withoutSystemPrompts", "YES",
      "-salah.debug.scratchPreferences", "YES",
      "-salah.notificationSettings", hex,
      "-salah.appLanguage", "english",
      "-AppleLanguages", "(en)",
      "-salah.alertVolume", "0",
      "-salah.duaEnabled", "NO",
      "-salah.silentMode", "NO",
      "-salah.latitude", "21.4167", "-salah.longitude", "39.8167",
      "-salah.timeZone", "Asia/Riyadh", "-salah.city", "Makkah", "-salah.country", "SA",
      "-salah.autoDetectMethod", "NO", "-salah.method", "4", "-salah.madhab", "0",
      "-salah.autoDetectHighLatitudeRule", "NO", "-salah.highLatitudeRule", "0",
      "-salah.delayedIshaInRamadan", "YES", "-salah.hijriOffset", "0",
      "-salah.jumuahOverrideEnabled", "NO",
    ] + adjustments
  }

  /// An at-time alert with an adhan the app plays, Alafasy's.
  static var adhan: [String: Any] {
    ["alertEnabled": true, "alertSound": ["kind": "builtIn", "builtIn": "Adhan-Alafasy"]]
  }

  /// The same alert turned off. Its sound stays the adhan, so turning the alert on in
  /// Settings makes it one the app plays: a prayer whose alert is simply off has the system
  /// sound, which the app leaves to the notification it posts and doesn't play itself.
  static var adhanOff: [String: Any] {
    var alert = adhan
    alert["alertEnabled"] = false
    return alert
  }
}
