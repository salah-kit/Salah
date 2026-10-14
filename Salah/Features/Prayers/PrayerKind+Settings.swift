import Foundation
import SalahCore

extension PrayerKind {
  /// The prayer's name in Settings, in the app's language. Settings names the prayer,
  /// so Dhuhr stays Dhuhr on a Friday; the schedule's events carry Jumu'ah where Salah
  /// declares it.
  var settingsLocalizedName: String {
    PrayerNames(locale: .app).name(of: self)
  }
}
