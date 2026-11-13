import Foundation
import SalahCalculation
import SalahCore
import SalahTimes

/// The app-owned choices shared with the iOS extension. A new install has no location.
nonisolated struct IOSPreferences: Codable, Equatable, Sendable {
  var location: PrayerLocation?
  /// The saved place's name in the languages Salah has shown it in.
  var placeNames: IOSPlaceNames?
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
      delayedIshaInRamadan && offersDelayedIsha
      ? .interval(minutes: 120, hijriDayOffset: hijriOffset) : .off
    return CalculationSettings(parameters: parameters)
  }

  /// Whether the delayed Isha in Ramadan applies: only Umm al-Qura's timetables move Isha to
  /// 120 minutes after Maghrib in Ramadan. Qatar's, the other interval Isha, keeps 90.
  var offersDelayedIsha: Bool { method != .custom && resolvedMethod == .ummAlQura }

  /// The language code place names are kept under: the selected language's, or the
  /// device's when Salah follows it.
  var placeLanguageCode: String {
    language.locale.language.languageCode?.identifier ?? "en"
  }

  /// The place's name in the selected language once Salah has looked it up, and as it was
  /// saved until then.
  var placeName: String? {
    guard let location else { return nil }
    return placeNames?.name(of: location, languageCode: placeLanguageCode) ?? location.name
  }

  /// Whether the place still needs a name in the selected language.
  var needsPlaceName: Bool {
    guard let location else { return false }
    return placeNames?.name(of: location, languageCode: placeLanguageCode) == nil
  }

  /// Settles the names when an edit changed the saved place.
  ///
  /// The geocoder named the new place in the device's language, so that name is kept under
  /// that language. A new fix of the place Salah already followed, which the geocoder names
  /// the same, keeps the names looked up before: a fix never lands on the same coordinates
  /// twice, and each one would otherwise ask for every name again.
  mutating func settlePlaceNames(after previous: IOSPreferences, deviceLanguageCode: String?) {
    guard let location, previous.location != location else { return }
    // An edit that brings the new place's names with it, as the iPhone's preferences do on the
    // watch, already settled them.
    if let names = placeNames, names != previous.placeNames, names.belongs(to: location) { return }
    var names = IOSPlaceNames(latitude: location.latitude, longitude: location.longitude)
    if let old = previous.location, let kept = previous.placeNames, kept.belongs(to: old),
      IOSPlaceNames.isSameNamedPlace(old, location)
    {
      names.names = kept.names
    }
    if let deviceLanguageCode, let name = location.name, !name.isEmpty {
      names.names[deviceLanguageCode] = name
    }
    placeNames = names
  }

  /// Files the saved name under the device's language for a place saved before names were
  /// kept, so a language the geocoder already answered in asks for nothing.
  mutating func seedPlaceNames(deviceLanguageCode: String?) {
    guard let location, placeNames?.belongs(to: location) != true, let deviceLanguageCode,
      let name = location.name
    else { return }
    setPlaceName(name, languageCode: deviceLanguageCode, for: location)
  }

  /// Keeps `name` for `location` in a language. A name that arrives after the person chose
  /// another place is dropped, and a new place starts a new set of names.
  mutating func setPlaceName(_ name: String, languageCode: String, for place: PrayerLocation) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let location, IOSPlaceNames.isSamePlace(location, place), !name.isEmpty else { return }
    var names =
      placeNames.flatMap { $0.belongs(to: location) ? $0 : nil }
      ?? IOSPlaceNames(latitude: location.latitude, longitude: location.longitude)
    names.names[languageCode] = name
    placeNames = names
  }

  /// The saved location, named in the selected language for the surfaces outside the app.
  var namedLocation: PrayerLocation? {
    guard var location else { return nil }
    location.name = placeName
    return location
  }

  /// No mirror is published until the user grants a fix or chooses a city.
  var mirror: SalahSettings? {
    guard let location = namedLocation else { return nil }
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
    // Names looked up for a place the person has since left label nothing.
    if let names = result.placeNames, result.location.map(names.belongs(to:)) != true {
      result.placeNames = nil
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
    if before.placeNames != after.placeNames { placeNames = after.placeNames }
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
    case location, placeNames, recentLocations, useCurrentLocation, method
    case automaticFallbackMethod
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
    placeNames = try values.decodeIfPresent(IOSPlaceNames.self, forKey: .placeNames)
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

nonisolated extension IOSPreferences {
  /// The language the device answers geocoding requests in.
  static var deviceLanguageCode: String? {
    Locale.preferredLanguages.first.flatMap {
      Locale(identifier: $0).language.languageCode?.identifier
    }
  }
}

/// One place's names by language code.
///
/// A geocoder names a place in the language it's asked in, and the saved location holds one
/// name. The names carry their place's coordinates, so they never label another place.
nonisolated struct IOSPlaceNames: Codable, Equatable, Sendable {
  var latitude: Double
  var longitude: Double
  var names: [String: String] = [:]

  /// The same saved place, not merely a nearby one.
  static func isSamePlace(_ first: PrayerLocation, _ second: PrayerLocation) -> Bool {
    first.latitude == second.latitude && first.longitude == second.longitude
  }

  /// Two fixes of one place: the geocoder gave both the same name in the same zone, a short
  /// way apart.
  static func isSameNamedPlace(_ first: PrayerLocation, _ second: PrayerLocation) -> Bool {
    guard let name = first.name, !name.isEmpty, name == second.name,
      first.timeZone.identifier == second.timeZone.identifier
    else { return false }
    return abs(first.latitude - second.latitude) < 0.5
      && abs(first.longitude - second.longitude) < 0.5
  }

  func belongs(to location: PrayerLocation) -> Bool {
    latitude == location.latitude && longitude == location.longitude
  }

  func name(of location: PrayerLocation, languageCode: String) -> String? {
    belongs(to: location) ? names[languageCode] : nil
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
/// What happens at each prayer's time, chosen once for every prayer during setup.
nonisolated enum IOSAlertMode: String, CaseIterable, Sendable {
  /// A notification that plays a short adhan clip.
  case adhan
  /// A notification with the system's usual sound.
  case notification
  /// No alerts or reminders at all.
  case silent

  var symbol: String {
    switch self {
    case .adhan: "speaker.wave.2.fill"
    case .notification: "bell.fill"
    case .silent: "bell.slash.fill"
    }
  }
}

nonisolated extension IOSPreferences {
  /// Sets every prayer's alert to `mode`. Adhan and Notification alert at the prayers that do
  /// by default, each with its sound; Silent turns every alert and reminder off. Minutes and
  /// reminder sounds stay as they were, for when the person turns one back on.
  mutating func apply(_ mode: IOSAlertMode) {
    func applied(_ value: IOSPrayerAlertSettings, kind: PrayerKind) -> IOSPrayerAlertSettings {
      var value = value
      let defaults = IOSPrayerAlertSettings.defaults(for: kind)
      switch mode {
      case .adhan:
        value.atTime = defaults.atTime
        value.sound = defaults.sound
      case .notification:
        value.atTime = defaults.atTime
        value.sound = .system
      case .silent:
        value.atTime = false
        value.beforeEnabled = false
        value.afterEnabled = false
      }
      return value
    }
    for kind in PrayerKind.allCases {
      notifications[kind] = applied(alerts(for: kind), kind: kind)
    }
    jumuahAlerts = applied(jumuahAlerts, kind: .dhuhr)
  }

  /// Whether any prayer alerts or reminds, so there's something to ask permission for.
  var hasEnabledAlerts: Bool {
    let all =
      PrayerKind.allCases.map { alerts(for: $0) } + (jumuahOverrideEnabled ? [jumuahAlerts] : [])
    return all.contains { $0.atTime || $0.beforeEnabled || $0.afterEnabled }
  }
}

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
