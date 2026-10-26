import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

/// Settings wording, in the same English and Arabic as the iPhone and iPad app.
nonisolated struct TVSettingsCopy: Sendable {
  let copy: TVCopy
  var locale: Locale { copy.locale }

  init(locale: Locale) { copy = TVCopy(locale: locale) }

  func text(_ english: String, _ arabic: String) -> String { copy(english, arabic) }

  func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }

  func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
  }

  func signedMinutes(_ value: Int) -> String {
    let sign = value > 0 ? "+" : value < 0 ? "−" : ""
    return copy.format("%@ min", "%@ د", sign + number(abs(value)))
  }

  func method(_ preferences: IOSPreferences) -> String {
    switch preferences.method {
    case .automatic:
      text("Automatic", "تلقائي") + " · "
        + IOSCalculationMethod.preset(preferences.resolvedMethod).title(locale: locale)
    case .custom, .preset: preferences.method.title(locale: locale)
    }
  }

  /// The method alone, for a sentence about where times come from.
  func methodName(_ preferences: IOSPreferences) -> String {
    preferences.method == .custom
      ? text("Custom angles", "زوايا مخصصة")
      : IOSCalculationMethod.preset(preferences.resolvedMethod).title(locale: locale)
  }

  func madhab(_ madhab: Madhab) -> String {
    madhab == .hanafi ? text("Hanafi", "حنفي") : text("Shafi’i", "شافعي")
  }

  func highLatitude(_ rule: HighLatitudeRule) -> String {
    switch rule {
    case .recommended: text("Recommended", "الموصى به")
    case .middleOfTheNight: text("Middle of the night", "منتصف الليل")
    case .seventhOfTheNight: text("Seventh of the night", "سُبع الليل")
    case .twilightAngle: text("Twilight angle", "زاوية الشفق")
    case .disabled: text("No adjustment", "بلا تعديل")
    }
  }

  func appearance(_ appearance: SalahAppearance) -> String {
    switch appearance {
    case .system: text("System", "النظام")
    case .light: text("Light", "فاتح")
    case .dark: text("Dark", "داكن")
    }
  }

  func language(_ language: AppLanguage) -> String {
    language == .system ? text("System", "النظام") : language.nativeName
  }

  func sound(_ sound: IOSSound) -> String {
    switch sound {
    case .none: text("Off", "إيقاف")
    default: sound.title(locale: locale)
    }
  }

  func onOff(_ value: Bool) -> String { value ? text("On", "تشغيل") : text("Off", "إيقاف") }

  func hijriOffset(_ value: Int) -> String {
    value == 0
      ? text("No adjustment", "بلا تعديل")
      : copy.format(
        value == 1 || value == -1 ? "%@ day" : "%@ days",
        value == 1 || value == -1 ? "%@ يوم" : "%@ أيام",
        (value > 0 ? "+" : "−") + number(abs(value)))
  }

  func volume(_ value: Double) -> String {
    (value).formatted(.percent.precision(.fractionLength(0)).locale(locale))
  }

  func adjustments(_ adjustments: PrayerAdjustments) -> String {
    let changed = PrayerKind.allCases.filter { adjustments.settingsMinutes(for: $0) != 0 }
    return changed.isEmpty
      ? text("None", "لا يوجد")
      : copy.format("%@ changed", "%@ معدّلة", number(changed.count))
  }
}

extension PrayerAdjustments {
  nonisolated func settingsMinutes(for kind: PrayerKind) -> Int {
    switch kind {
    case .fajr: fajr
    case .sunrise: sunrise
    case .dhuhr: dhuhr
    case .asr: asr
    case .maghrib: maghrib
    case .isha: isha
    }
  }

  nonisolated mutating func setSettingsMinutes(_ value: Int, for kind: PrayerKind) {
    switch kind {
    case .fajr: fajr = value
    case .sunrise: sunrise = value
    case .dhuhr: dhuhr = value
    case .asr: asr = value
    case .maghrib: maghrib = value
    case .isha: isha = value
    }
  }
}
