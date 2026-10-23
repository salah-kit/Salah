import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

/// The app-owned choices shared with the iOS extension. A new install has no location.
nonisolated struct IOSPreferences: Codable, Equatable, Sendable {
  var location: PrayerLocation?
  var recentLocations: [PrayerLocation] = []
  var useCurrentLocation = false
  var method: IOSCalculationMethod = .automatic
  /// The last method explicitly chosen by the user, retained in countries without a suggestion.
  var automaticFallbackMethod: CalculationMethod = .muslimWorldLeague
  var madhab: Madhab = .shafi
  var highLatitudeRule: HighLatitudeRule = .middleOfTheNight
  var automaticHighLatitude = true
  var customFajrAngle = 18.0
  var customIshaAngle = 17.5
  var adjustments: PrayerAdjustments = .zero
  var delayedIshaInRamadan = true
  var hijriOffset = 0
  var language: AppLanguage = .system
  var appearance: SalahAppearance = .system
  var followsTimeOfDay = true
  var muteSounds = false
  var duaEnabled = false
  var playbackVolume = 0.75
  var notifications: [PrayerKind: IOSPrayerAlertSettings] = Dictionary(
    uniqueKeysWithValues: PrayerKind.allCases.map { ($0, IOSPrayerAlertSettings.defaults(for: $0)) }
  )
  var jumuahOverrideEnabled = false
  var jumuahOverrideSeeded = false
  var jumuahAlerts = IOSPrayerAlertSettings()
  var onboardingCompleted = false

  var resolvedMethod: CalculationMethod {
    switch method {
    case .preset(let method): method
    case .automatic:
      location.flatMap { CalculationMethod.suggested(for: $0) } ?? automaticFallbackMethod
    case .custom: .muslimWorldLeague
    }
  }

  var calculation: CalculationSettings {
    var parameters: CalculationParameters
    if method == .custom {
      parameters = CalculationParameters(
        fajr: .angle(customFajrAngle), isha: .angle(customIshaAngle))
    } else {
      parameters = resolvedMethod.parameters
    }
    parameters.madhab = madhab
    parameters.highLatitudeRule =
      automaticHighLatitude
      ? (abs(location?.latitude ?? 0) > 48 ? .seventhOfTheNight : .middleOfTheNight)
      : highLatitudeRule
    parameters.adjustments = adjustments
    parameters.ramadanIsha =
      delayedIshaInRamadan ? .interval(minutes: 120, hijriDayOffset: hijriOffset) : .off
    return CalculationSettings(parameters: parameters)
  }

  /// No mirror is published until the user grants a fix or chooses a city.
  var mirror: SalahSettings? {
    guard let location else { return nil }
    return SalahSettings(
      location: location, calculation: calculation, language: language, appearance: appearance,
      followsTimeOfDay: followsTimeOfDay, silentMode: muteSounds, hijriOffset: hijriOffset,
      alerts: Dictionary(
        uniqueKeysWithValues: PrayerKind.allCases.map { ($0, alerts(for: $0).mirrored) }),
      jumuahAlerts: jumuahOverrideEnabled ? jumuahAlerts.mirrored : nil)
  }

  func alerts(for kind: PrayerKind, observance: PrayerObservance = .ordinary)
    -> IOSPrayerAlertSettings
  {
    if kind == .dhuhr, observance == .jumuah, jumuahOverrideEnabled {
      return jumuahAlerts
    }
    return notifications[kind] ?? .defaults(for: kind)
  }

  /// Keeps persisted values within the same bounds as the controls that edit them.
  func normalized() -> Self {
    var result = self
    if case .preset(let selected) = method { result.automaticFallbackMethod = selected }
    if let location,
      !location.latitude.isFinite || !location.longitude.isFinite
        || !(-90...90).contains(location.latitude) || !(-180...180).contains(location.longitude)
    {
      result.location = nil
      result.onboardingCompleted = false
    }
    result.customFajrAngle = Self.angle(customFajrAngle, fallback: 18)
    result.customIshaAngle = Self.angle(customIshaAngle, fallback: 17.5)
    result.hijriOffset = min(3, max(-3, hijriOffset))
    result.playbackVolume = playbackVolume.isFinite ? min(1, max(0, playbackVolume)) : 0.75
    result.adjustments = PrayerAdjustments(
      fajr: Self.minutes(adjustments.fajr), sunrise: Self.minutes(adjustments.sunrise),
      dhuhr: Self.minutes(adjustments.dhuhr), asr: Self.minutes(adjustments.asr),
      maghrib: Self.minutes(adjustments.maghrib), isha: Self.minutes(adjustments.isha))
    result.notifications = Dictionary(
      uniqueKeysWithValues: PrayerKind.allCases.map {
        ($0, (notifications[$0] ?? .defaults(for: $0)).normalized())
      })
    result.jumuahAlerts = jumuahAlerts.normalized()
    result.recentLocations = Array(
      recentLocations.filter {
        $0.latitude.isFinite && $0.longitude.isFinite
          && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude)
      }.prefix(5))
    return result
  }

  private static func angle(_ value: Double, fallback: Double) -> Double {
    value.isFinite ? min(30, max(1, value)) : fallback
  }

  static let adjustmentMinutes = -60...60
  private static func minutes(_ value: Int) -> Int { min(60, max(-60, value)) }

  /// Applies the fields a user actually edited to a fresh snapshot from another process.
  /// A Control Center mute change therefore survives an unrelated calculation edit.
  mutating func mergeChanges(from before: Self, to after: Self) {
    if before.location != after.location { location = after.location }
    if before.recentLocations != after.recentLocations { recentLocations = after.recentLocations }
    if before.useCurrentLocation != after.useCurrentLocation {
      useCurrentLocation = after.useCurrentLocation
    }
    if before.method != after.method { method = after.method }
    if before.automaticFallbackMethod != after.automaticFallbackMethod {
      automaticFallbackMethod = after.automaticFallbackMethod
    }
    if before.madhab != after.madhab { madhab = after.madhab }
    if before.highLatitudeRule != after.highLatitudeRule {
      highLatitudeRule = after.highLatitudeRule
    }
    if before.automaticHighLatitude != after.automaticHighLatitude {
      automaticHighLatitude = after.automaticHighLatitude
    }
    if before.customFajrAngle != after.customFajrAngle { customFajrAngle = after.customFajrAngle }
    if before.customIshaAngle != after.customIshaAngle { customIshaAngle = after.customIshaAngle }
    if before.adjustments != after.adjustments { adjustments = after.adjustments }
    if before.delayedIshaInRamadan != after.delayedIshaInRamadan {
      delayedIshaInRamadan = after.delayedIshaInRamadan
    }
    if before.hijriOffset != after.hijriOffset { hijriOffset = after.hijriOffset }
    if before.language != after.language { language = after.language }
    if before.appearance != after.appearance { appearance = after.appearance }
    if before.followsTimeOfDay != after.followsTimeOfDay {
      followsTimeOfDay = after.followsTimeOfDay
    }
    if before.muteSounds != after.muteSounds { muteSounds = after.muteSounds }
    if before.duaEnabled != after.duaEnabled { duaEnabled = after.duaEnabled }
    if before.playbackVolume != after.playbackVolume { playbackVolume = after.playbackVolume }
    for kind in PrayerKind.allCases where before.notifications[kind] != after.notifications[kind] {
      notifications[kind] = after.notifications[kind]
    }
    if before.jumuahOverrideEnabled != after.jumuahOverrideEnabled {
      jumuahOverrideEnabled = after.jumuahOverrideEnabled
    }
    if before.jumuahOverrideSeeded != after.jumuahOverrideSeeded {
      jumuahOverrideSeeded = after.jumuahOverrideSeeded
    }
    if before.jumuahAlerts != after.jumuahAlerts { jumuahAlerts = after.jumuahAlerts }
    if before.onboardingCompleted != after.onboardingCompleted {
      onboardingCompleted = after.onboardingCompleted
    }
  }
}

nonisolated extension IOSPreferences {
  private enum CodingKeys: String, CodingKey {
    case location, recentLocations, useCurrentLocation, method, automaticFallbackMethod
    case madhab, highLatitudeRule
    case automaticHighLatitude, customFajrAngle, customIshaAngle, adjustments
    case delayedIshaInRamadan, hijriOffset, language, appearance, followsTimeOfDay
    case muteSounds, duaEnabled, playbackVolume, notifications, jumuahOverrideEnabled
    case jumuahAlerts, jumuahOverrideSeeded, onboardingCompleted
  }

  /// New optional preferences receive their fresh-install defaults when older data is read.
  init(from decoder: any Decoder) throws {
    self.init()
    let values = try decoder.container(keyedBy: CodingKeys.self)
    location = try values.decodeIfPresent(PrayerLocation.self, forKey: .location)
    recentLocations =
      try values.decodeIfPresent([PrayerLocation].self, forKey: .recentLocations) ?? recentLocations
    useCurrentLocation =
      try values.decodeIfPresent(Bool.self, forKey: .useCurrentLocation) ?? useCurrentLocation
    method = try values.decodeIfPresent(IOSCalculationMethod.self, forKey: .method) ?? method
    automaticFallbackMethod =
      try values.decodeIfPresent(CalculationMethod.self, forKey: .automaticFallbackMethod)
      ?? {
        if case .preset(let selected) = method { return selected }
        return .muslimWorldLeague
      }()
    madhab = try values.decodeIfPresent(Madhab.self, forKey: .madhab) ?? madhab
    highLatitudeRule =
      try values.decodeIfPresent(HighLatitudeRule.self, forKey: .highLatitudeRule)
      ?? highLatitudeRule
    automaticHighLatitude =
      try values.decodeIfPresent(Bool.self, forKey: .automaticHighLatitude) ?? automaticHighLatitude
    customFajrAngle =
      try values.decodeIfPresent(Double.self, forKey: .customFajrAngle) ?? customFajrAngle
    customIshaAngle =
      try values.decodeIfPresent(Double.self, forKey: .customIshaAngle) ?? customIshaAngle
    adjustments =
      try values.decodeIfPresent(PrayerAdjustments.self, forKey: .adjustments) ?? adjustments
    delayedIshaInRamadan =
      try values.decodeIfPresent(Bool.self, forKey: .delayedIshaInRamadan) ?? delayedIshaInRamadan
    hijriOffset = try values.decodeIfPresent(Int.self, forKey: .hijriOffset) ?? hijriOffset
    language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? language
    appearance = try values.decodeIfPresent(SalahAppearance.self, forKey: .appearance) ?? appearance
    followsTimeOfDay =
      try values.decodeIfPresent(Bool.self, forKey: .followsTimeOfDay) ?? followsTimeOfDay
    muteSounds = try values.decodeIfPresent(Bool.self, forKey: .muteSounds) ?? muteSounds
    duaEnabled = try values.decodeIfPresent(Bool.self, forKey: .duaEnabled) ?? duaEnabled
    playbackVolume =
      try values.decodeIfPresent(Double.self, forKey: .playbackVolume) ?? playbackVolume
    notifications =
      try values.decodeIfPresent([PrayerKind: IOSPrayerAlertSettings].self, forKey: .notifications)
      ?? notifications
    jumuahOverrideEnabled =
      try values.decodeIfPresent(Bool.self, forKey: .jumuahOverrideEnabled) ?? jumuahOverrideEnabled
    jumuahAlerts =
      try values.decodeIfPresent(IOSPrayerAlertSettings.self, forKey: .jumuahAlerts) ?? jumuahAlerts
    jumuahOverrideSeeded =
      try values.decodeIfPresent(Bool.self, forKey: .jumuahOverrideSeeded)
      ?? values.contains(.jumuahAlerts)
    onboardingCompleted =
      try values.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? onboardingCompleted
  }
}

nonisolated enum IOSCalculationMethod: Codable, Hashable, Sendable {
  case automatic
  case preset(CalculationMethod)
  case custom

  static var allCases: [Self] {
    [.automatic] + CalculationMethod.allCases.map(Self.preset) + [.custom]
  }

  func title(isArabic: Bool = false) -> String {
    switch self {
    case .automatic: return isArabic ? "تلقائي" : "Automatic"
    case .custom: return isArabic ? "مخصص" : "Custom"
    case .preset(let value):
      switch value {
      case .muslimWorldLeague: return isArabic ? "رابطة العالم الإسلامي" : "Muslim World League"
      case .isna: return isArabic ? "أمريكا الشمالية (ISNA)" : "North America (ISNA)"
      case .egyptian: return isArabic ? "الهيئة المصرية للمساحة" : "Egyptian General Authority"
      case .ummAlQura: return isArabic ? "أم القرى، مكة المكرمة" : "Umm al-Qura, Makkah"
      case .karachi:
        return isArabic
          ? "جامعة العلوم الإسلامية، كراتشي" : "University of Islamic Sciences, Karachi"
      case .tehran: return isArabic ? "معهد الجيوفيزياء، طهران" : "Institute of Geophysics, Tehran"
      case .diyanet: return isArabic ? "رئاسة الشؤون الدينية، تركيا" : "Diyanet, Türkiye"
      case .dubai: return isArabic ? "دبي" : "Dubai"
      case .kuwait: return isArabic ? "الكويت" : "Kuwait"
      case .qatar: return isArabic ? "قطر" : "Qatar"
      case .muis: return isArabic ? "مجلس سنغافورة الإسلامي" : "MUIS, Singapore"
      case .jakim: return isArabic ? "جاكيم، ماليزيا" : "JAKIM, Malaysia"
      case .kemenag: return isArabic ? "وزارة الشؤون الدينية، إندونيسيا" : "Kemenag, Indonesia"
      case .moonsightingCommittee: return isArabic ? "لجنة رؤية الهلال" : "Moonsighting Committee"
      }
    }
  }
}

/// Notification and foreground sounds are independent. A custom value names a managed file.
nonisolated enum IOSSound: Codable, Hashable, Sendable {
  case adhan
  case fajrAdhan
  case system
  case none
  case softTone
  case custom(String)

  static let builtIn: [Self] = [.fajrAdhan, .adhan, .softTone, .system, .none]

  func title(isArabic: Bool = false) -> String {
    switch self {
    case .adhan: isArabic ? "أذان · أحمد خَلَف" : "Adhan · Ahmed Khalaf"
    case .fajrAdhan: isArabic ? "أذان الفجر · أحمد خَلَف" : "Fajr adhan · Ahmed Khalaf"
    case .system: isArabic ? "صوت النظام" : "System sound"
    case .none: isArabic ? "بلا صوت" : "None"
    case .softTone: isArabic ? "نغمة هادئة" : "Soft tone"
    case .custom(let filename):
      URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    }
  }
}

nonisolated struct IOSPrayerAlertSettings: Codable, Equatable, Sendable {
  var atTime = true
  var sound: IOSSound = .adhan
  var beforeEnabled = false
  var beforeMinutes = 10
  var beforeSound: IOSSound = .softTone
  var afterEnabled = false
  var afterMinutes = 5
  var afterSound: IOSSound = .softTone

  static func defaults(for kind: PrayerKind) -> Self {
    var result = Self()
    result.atTime = kind != .sunrise
    result.sound = kind == .fajr ? .fajrAdhan : (kind == .sunrise ? .softTone : .adhan)
    if kind == .fajr { result.beforeMinutes = 30 }
    return result
  }

  var mirrored: PrayerAlerts {
    PrayerAlerts(
      alert: atTime, beforeMinutes: beforeEnabled ? beforeMinutes : nil,
      afterMinutes: afterEnabled ? afterMinutes : nil)
  }

  func normalized() -> Self {
    var result = self
    result.beforeMinutes = min(120, max(1, beforeMinutes))
    result.afterMinutes = min(120, max(1, afterMinutes))
    return result
  }
}
