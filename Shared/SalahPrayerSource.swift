import Foundation
import SalahCalculation
import SalahCore

/// Salah's prayer source: SalahTimes' calculation, with every Friday's Dhuhr declared as
/// Jumu'ah.
///
/// SalahKit never infers Jumu'ah from the date; naming Friday's Dhuhr Jumu'ah is Salah's
/// own policy, so this source declares it. Prayer names then read "Jumuah" on Fridays,
/// and the alert planner hands Friday's Dhuhr to the Jumu'ah settings when the user turned
/// the override on (`SalahSettings.alerts(for:)`, `Preferences.alertSettings(for:)`).
/// Everything else is the calculation's, unchanged: the same events, coverage and gaps,
/// and the wrapped source's `expectedKinds` and `maximumLead`, as SalahCore's source
/// contract asks of a wrapper.
nonisolated struct SalahPrayerSource: PrayerSource, Hashable {
  /// The calculation underneath.
  var calculation: CalculationSource

  init(_ settings: CalculationSettings) {
    calculation = CalculationSource(settings)
  }

  var expectedKinds: Set<PrayerKind> { calculation.expectedKinds }

  var maximumLead: Duration { calculation.maximumLead }

  func prayerDay(_ day: CivilDay, at location: PrayerLocation) -> PrayerDayAvailability {
    let availability = calculation.prayerDay(day, at: location)
    guard day.weekday == 6, case .available(let prayerDay, let coverage) = availability else {
      return availability
    }
    var events = prayerDay.events
    for index in events.indices where events[index].kind == .dhuhr {
      events[index].observance = .jumuah
    }
    return .available(
      PrayerDay(day: prayerDay.day, timeZone: prayerDay.timeZone, events: events),
      coverage: coverage)
  }
}
