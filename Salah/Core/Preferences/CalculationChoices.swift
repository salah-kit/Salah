import Foundation
import SalahCalculation
import SalahTimes

/// The calculation choices Salah's preferences make, as one value, and the SalahTimes
/// parameters they mean.
///
/// `Preferences.calculationChoices` reads it from the preferences. It's a plain value
/// so that the parameters can be checked without the app.
nonisolated struct CalculationChoices: Equatable, Sendable {
  var method: MethodPreference
  var madhab: MadhabPreference
  var highLatitudeRule: HighLatitudeRulePreference
  /// The custom method's angles, used only when `method` is `.custom`.
  var customFajrAngle: Double
  var customIshaAngle: Double
  /// The user's minutes, per prayer and sunrise.
  var adjustments: PrayerAdjustments
  /// Whether an interval Isha is 120 minutes after Maghrib in Ramadan.
  var delayedIshaInRamadan: Bool
  /// The Hijri date's day offset, which also moves Ramadan for the delayed Isha.
  var hijriOffset: Int

  /// SalahTimes' parameters for these choices, passed to SalahCalculation whole.
  ///
  /// A published method keeps its own values (SalahTimes' `METHODS.md`); the custom
  /// method is the user's two angles with SalahTimes' defaults otherwise: Maghrib at
  /// sunset, rounding to the nearest minute, no method minutes. The madhab, the
  /// high-latitude rule and the user's minutes apply to every method. The delayed Isha
  /// is SalahTimes' Ramadan rule: an interval Isha becomes 120 minutes in the month of
  /// Ramadan, read in the Umm al-Qura calendar after the Hijri offset, as the Hijri date
  /// Salah shows; an angle-based Isha doesn't change.
  /// The minutes after Maghrib of an interval Isha in Ramadan, when it's delayed.
  static let ramadanIshaMinutes = 120

  var calculationSettings: CalculationSettings {
    var parameters =
      method.method?.parameters
      ?? CalculationParameters(fajr: .angle(customFajrAngle), isha: .angle(customIshaAngle))
    parameters.madhab = madhab.madhab
    parameters.highLatitudeRule = highLatitudeRule.rule
    parameters.adjustments = adjustments
    parameters.ramadanIsha =
      delayedIshaInRamadan
      ? .interval(minutes: Self.ramadanIshaMinutes, hijriDayOffset: hijriOffset) : .off
    return CalculationSettings(parameters: parameters)
  }
}
