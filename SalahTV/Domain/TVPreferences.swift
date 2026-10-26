import Foundation
import SalahCore

/// The choices Apple TV offers on top of the shared preferences. A prayer has one sound at
/// its time, or none; reminders before and after a prayer aren't played on Apple TV.
nonisolated extension IOSPreferences {
  /// The sound a prayer plays at its time while Salah is open, or `.none` when it's off.
  /// Friday's Dhuhr takes the Jumu'ah settings while the override is on.
  func tvSound(for kind: PrayerKind, observance: PrayerObservance = .ordinary) -> IOSSound {
    let alerts = alerts(for: kind, observance: observance)
    return alerts.atTime ? alerts.sound : .none
  }

  /// Sets the sound a prayer plays at its time; `.none` turns its alert off and keeps the
  /// sound it had for when it's turned on again.
  mutating func setTVSound(
    _ sound: IOSSound, for kind: PrayerKind, observance: PrayerObservance = .ordinary
  ) {
    let jumuah = kind == .dhuhr && observance == .jumuah && jumuahOverrideEnabled
    var value = jumuah ? jumuahAlerts : alerts(for: kind)
    value.atTime = sound != .none
    if sound != .none { value.sound = sound }
    if jumuah {
      jumuahAlerts = value
    } else {
      notifications[kind] = value
    }
  }

  /// How many prayers, sunrise included, play a sound at their time.
  var tvSoundsOn: Int {
    PrayerKind.allCases.filter { tvSound(for: $0) != .none }.count
  }
}
