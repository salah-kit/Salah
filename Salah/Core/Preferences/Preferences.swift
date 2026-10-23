import Foundation
import OSLog
import SalahCore

@Observable
final class Preferences {
  /// The store `shared` reads and writes: `.standard` in the app, or a scratch store for
  /// the real-app tests (`DebugOptions.scratchPreferencesKey`). Test seam: the
  /// SalahTests bundle points it at a throwaway suite before anything touches
  /// `shared`, so tests never read or write the real preferences.
  static var sharedDefaults: UserDefaults = launchStore()

  private static func launchStore() -> UserDefaults {
    #if DEBUG
      if let scratch = DebugOptions.scratchPreferences() { return scratch }
    #endif
    return .standard
  }

  static let shared = Preferences(defaults: sharedDefaults)

  let defaults: UserDefaults

  // MARK: - Change propagation

  /// True only while `init` loads stored values, so the didSets below persist
  /// without emitting a refresh before anything is observing.
  @ObservationIgnored private var isLoading = true
  @ObservationIgnored private var batchDepth = 0
  @ObservationIgnored private var batchedEffects: PreferenceRefresh = []

  /// Declares what just-changed state needs downstream. Called from the
  /// state-affecting didSets so the classification lives next to the data (not
  /// in whatever view toggled it). Inside `batchUpdates` the effects accumulate
  /// and fire once; otherwise this posts immediately. No-op while loading.
  func requestRefresh(_ effects: PreferenceRefresh) {
    guard !isLoading else { return }
    if batchDepth > 0 {
      batchedEffects.formUnion(effects)
      return
    }
    NotificationCenter.default.post(
      name: .salahPreferencesDidChange, object: nil,
      userInfo: [PreferenceRefresh.userInfoKey: effects.rawValue])
  }

  /// Groups several preference writes (e.g. applying a picked location's city,
  /// coordinates, and time zone together) into a single coalesced refresh.
  func batchUpdates(_ body: () -> Void) {
    batchDepth += 1
    body()
    batchDepth -= 1
    guard batchDepth == 0, !batchedEffects.isEmpty else { return }
    let effects = batchedEffects
    batchedEffects = []
    requestRefresh(effects)
  }

  // MARK: - Display

  var displayNextPrayer: Bool = true {
    didSet {
      defaults.set(displayNextPrayer, forKey: Key.displayNextPrayer)
      enforceVisibleMenuBarContent()
      requestRefresh(.display)
    }
  }

  var nextPrayerDisplayType: NextPrayerDisplayType = .timeUntil {
    didSet {
      defaults.set(nextPrayerDisplayType.rawValue, forKey: Key.displayNextPrayerType)
      enforceVisibleMenuBarContent()
      requestRefresh(.display)
    }
  }

  var nextPrayerDisplayName: NextPrayerDisplayName = .full {
    didSet {
      defaults.set(nextPrayerDisplayName.rawValue, forKey: Key.displayNextPrayerName)
      enforceVisibleMenuBarContent()
      requestRefresh(.display)
    }
  }

  var displayIcon: Bool = true {
    didSet {
      defaults.set(displayIcon, forKey: Key.displayIcon)
      enforceVisibleMenuBarContent()
      requestRefresh(.display)
    }
  }

  // MARK: - Location

  var useCurrentLocation: Bool = true {
    didSet {
      defaults.set(useCurrentLocation, forKey: Key.autoLocation)
      requestRefresh(.display)
    }
  }

  var city: String = DefaultPlace.city {
    didSet {
      defaults.set(city, forKey: Key.city)
      requestRefresh(.display)
    }
  }

  var state: String = "" {
    didSet {
      defaults.set(state, forKey: Key.state)
      requestRefresh(.display)
    }
  }

  var country: String = "SA" {
    didSet {
      defaults.set(country, forKey: Key.country)
      requestRefresh(.display)
    }
  }

  var countryName: String = DefaultPlace.countryName {
    didSet {
      defaults.set(countryName, forKey: Key.countryName)
      requestRefresh(.display)
    }
  }

  var storedTimeZone: String = "Asia/Riyadh" {
    didSet {
      defaults.set(storedTimeZone, forKey: Key.timeZone)
      requestRefresh(.prayerTimes)
    }
  }

  var latitude: Double = 21.4167 {
    didSet {
      defaults.set(latitude, forKey: Key.latitude)
      requestRefresh(.prayerTimes)
    }
  }

  var longitude: Double = 39.8167 {
    didSet {
      defaults.set(longitude, forKey: Key.longitude)
      requestRefresh(.prayerTimes)
    }
  }

  // MARK: - Calculation

  var methodPreference: MethodPreference = .ummAlQura {
    didSet {
      defaults.set(methodPreference.rawValue, forKey: Key.method)
      requestRefresh(.prayerTimes)
    }
  }

  var madhabPreference: MadhabPreference = .shafi {
    didSet {
      defaults.set(madhabPreference.rawValue, forKey: Key.madhab)
      requestRefresh(.prayerTimes)
    }
  }

  var autoDetectMethod: Bool = true {
    didSet {
      defaults.set(autoDetectMethod, forKey: Key.autoDetectMethod)
      requestRefresh(.prayerTimes)
    }
  }

  var autoDetectHighLatitudeRule: Bool = true {
    didSet {
      defaults.set(autoDetectHighLatitudeRule, forKey: Key.autoDetectHighLatitudeRule)
      requestRefresh(.prayerTimes)
    }
  }

  var highLatitudeRulePreference: HighLatitudeRulePreference = .middleOfTheNight {
    didSet {
      defaults.set(highLatitudeRulePreference.rawValue, forKey: Key.highLatitudeRule)
      requestRefresh(.prayerTimes)
    }
  }

  /// The twilight angles SalahTimes calculates with; outside them every day would be
  /// unavailable.
  static let twilightAngles: ClosedRange<Double> = 1...30
  /// The minute adjustments SalahTimes accepts, a day either way.
  static let adjustmentMinutes: ClosedRange<Int> = -1_440...1_440

  var customFajrAngle: Double = 18.0 {
    didSet {
      // An angle SalahTimes can't calculate with snaps back to the previous value, as
      // non-positive input always did.
      guard Self.twilightAngles.contains(customFajrAngle) else {
        customFajrAngle = Self.twilightAngles.contains(oldValue) ? oldValue : 18.0
        return
      }
      defaults.set(customFajrAngle, forKey: Key.customFajrAngle)
      requestRefresh(.prayerTimes)
    }
  }

  var customIshaAngle: Double = 17.5 {
    didSet {
      guard Self.twilightAngles.contains(customIshaAngle) else {
        customIshaAngle = Self.twilightAngles.contains(oldValue) ? oldValue : 17.5
        return
      }
      defaults.set(customIshaAngle, forKey: Key.customIshaAngle)
      requestRefresh(.prayerTimes)
    }
  }

  // MARK: - Adjustments

  var fajrAdjustment: Int = 0 {
    didSet {
      // Assigning re-enters the observed setter: clamp only what's out of range.
      guard Self.adjustmentMinutes.contains(fajrAdjustment) else {
        fajrAdjustment = fajrAdjustment.clamped(to: Self.adjustmentMinutes)
        return
      }
      defaults.set(fajrAdjustment, forKey: Key.adjustmentFajr)
      requestRefresh(.prayerTimes)
    }
  }

  var shuruqAdjustment: Int = 0 {
    didSet {
      guard Self.adjustmentMinutes.contains(shuruqAdjustment) else {
        shuruqAdjustment = shuruqAdjustment.clamped(to: Self.adjustmentMinutes)
        return
      }
      defaults.set(shuruqAdjustment, forKey: Key.adjustmentShuruq)
      requestRefresh(.prayerTimes)
    }
  }

  var dhuhrAdjustment: Int = 0 {
    didSet {
      guard Self.adjustmentMinutes.contains(dhuhrAdjustment) else {
        dhuhrAdjustment = dhuhrAdjustment.clamped(to: Self.adjustmentMinutes)
        return
      }
      defaults.set(dhuhrAdjustment, forKey: Key.adjustmentDhuhr)
      requestRefresh(.prayerTimes)
    }
  }

  var asrAdjustment: Int = 0 {
    didSet {
      guard Self.adjustmentMinutes.contains(asrAdjustment) else {
        asrAdjustment = asrAdjustment.clamped(to: Self.adjustmentMinutes)
        return
      }
      defaults.set(asrAdjustment, forKey: Key.adjustmentAsr)
      requestRefresh(.prayerTimes)
    }
  }

  var maghribAdjustment: Int = 0 {
    didSet {
      guard Self.adjustmentMinutes.contains(maghribAdjustment) else {
        maghribAdjustment = maghribAdjustment.clamped(to: Self.adjustmentMinutes)
        return
      }
      defaults.set(maghribAdjustment, forKey: Key.adjustmentMaghrib)
      requestRefresh(.prayerTimes)
    }
  }

  var ishaAdjustment: Int = 0 {
    didSet {
      guard Self.adjustmentMinutes.contains(ishaAdjustment) else {
        ishaAdjustment = ishaAdjustment.clamped(to: Self.adjustmentMinutes)
        return
      }
      defaults.set(ishaAdjustment, forKey: Key.adjustmentIsha)
      requestRefresh(.prayerTimes)
    }
  }

  // MARK: - Advanced

  var hijriOffset: Int = 0 {
    didSet {
      defaults.set(hijriOffset, forKey: Key.hijriOffset)
      requestRefresh(.display)
    }
  }

  var delayedIshaInRamadan: Bool = true {
    didSet {
      defaults.set(delayedIshaInRamadan, forKey: Key.delayedIshaInRamadan)
      requestRefresh(.prayerTimes)
    }
  }

  var alertVolume: Int = 50 {
    didSet {
      let clamped = max(0, min(alertVolume, 100))
      if alertVolume != clamped {
        alertVolume = clamped
        return
      }

      defaults.set(alertVolume, forKey: Key.alertVolume)
      requestRefresh(.audioRuntime)
    }
  }

  /// Whether the first launch's welcome is behind us. Until then, Salah asks for neither
  /// location nor notifications by itself: the welcome asks, each on its own page.
  var onboardingCompleted: Bool = false {
    didSet { defaults.set(onboardingCompleted, forKey: Key.onboardingCompleted) }
  }

  /// Whether the welcome's Not Now put off the notification prompt. Salah then doesn't ask
  /// when it schedules alerts; the Notifications pane asks when it's opened.
  var notificationPromptDeferred: Bool = false {
    didSet {
      defaults.set(notificationPromptDeferred, forKey: Key.notificationPromptDeferred)
    }
  }

  var duaEnabled: Bool = true {
    didSet {
      defaults.set(duaEnabled, forKey: Key.duaEnabled)
      requestRefresh(.audioRuntime)
    }
  }

  var silentMode: Bool = false {
    didSet {
      defaults.set(silentMode, forKey: Key.silentMode)
      // `.prayerTimes` (not just `.display`) because the scheduled notifications'
      // sound is decided at schedule time from `silentMode` - toggling it has to
      // reschedule, not only restyle. `.audioRuntime` stops any playing audio.
      requestRefresh([.prayerTimes, .audioRuntime])
    }
  }

  // MARK: - Notifications

  var jumuahOverrideEnabled: Bool = false {
    didSet {
      defaults.set(jumuahOverrideEnabled, forKey: Key.jumuahOverrideEnabled)
      if jumuahOverrideEnabled {
        seedJumuahConfigIfNeeded()
      }
      requestRefresh(.prayerTimes)
    }
  }

  var notificationSettings: [String: PrayerNotificationConfig] = [:] {
    didSet {
      do {
        let data = try JSONEncoder().encode(notificationSettings)
        defaults.set(data, forKey: Key.notificationSettings)
      } catch {
        AppLog.preferences.error(
          "Failed to encode notificationSettings: \(error.localizedDescription, privacy: .public)")
      }
      requestRefresh(.prayerTimes)
    }
  }

  // MARK: - Localization

  var appLanguage: AppLanguage = .system {
    didSet {
      defaults.set(appLanguage.rawValue, forKey: Key.appLanguage)
      applyAppleLanguagesOverride()
      requestRefresh(.localization)
    }
  }

  /// Mirrors `appLanguage` into the `AppleLanguages` UserDefaults so
  /// `Bundle.main.preferredLocalizations` matches our in-app choice, and into
  /// `AppleTextDirection` so AppKit lays out in its direction. Drives
  /// system-rendered chrome like the app menu's items (built from
  /// `CFBundleDisplayName`). Takes effect on next launch.
  func applyAppleLanguagesOverride() {
    if let override = appLanguage.appleLanguagesOverride {
      defaults.set(override, forKey: "AppleLanguages")
    } else {
      defaults.removeObject(forKey: "AppleLanguages")
    }
    if let rightToLeft = appLanguage.appleTextDirectionOverride {
      defaults.set(rightToLeft, forKey: "AppleTextDirection")
    } else {
      defaults.removeObject(forKey: "AppleTextDirection")
    }
    // Force the change through CFPreferences immediately so any reader that
    // queries the preferences chain on the same run loop sees the new state.
    defaults.synchronize()
  }

  // MARK: - Appearance

  /// Light, dark, or the system's appearance, for Salah's window, dropdown and widgets.
  var appearance: SalahAppearance = .system {
    didSet {
      defaults.set(appearance.rawValue, forKey: Key.appearance)
      requestRefresh(.display)
    }
  }

  /// Whether the sky follows the time of day; the neutral sky when it doesn't.
  var followsTimeOfDay: Bool = true {
    didSet {
      defaults.set(followsTimeOfDay, forKey: Key.followsTimeOfDay)
      requestRefresh(.display)
    }
  }

  /// The stored appearance, or the one the retired widget themes pinned (Always Dark or
  /// Always Light) before there was one.
  private static func loadAppearance(from defaults: UserDefaults) -> SalahAppearance {
    if let raw = defaults.string(forKey: Key.appearance),
      let stored = SalahAppearance(rawValue: raw)
    {
      return stored
    }
    // The presets followed the system; only the custom theme drew a pinned appearance.
    guard defaults.string(forKey: Key.retiredWidgetThemeID) == "custom" else { return .system }
    switch defaults.string(forKey: Key.retiredWidgetAppearance) {
    case "alwaysDark": return .dark
    case "alwaysLight": return .light
    default: return .system
    }
  }

  // MARK: - Init

  /// Loads every preference from `defaults`. The app uses `shared`; tests build
  /// their own instances over throwaway suites.
  init(defaults: UserDefaults) {
    self.defaults = defaults
    registerDefaults()

    displayNextPrayer = defaults.bool(forKey: Key.displayNextPrayer)
    nextPrayerDisplayType =
      NextPrayerDisplayType(rawValue: defaults.integer(forKey: Key.displayNextPrayerType))
      ?? .timeUntil
    nextPrayerDisplayName =
      NextPrayerDisplayName(rawValue: defaults.integer(forKey: Key.displayNextPrayerName)) ?? .full
    displayIcon = defaults.bool(forKey: Key.displayIcon)

    useCurrentLocation = defaults.bool(forKey: Key.autoLocation)
    city = defaults.string(forKey: Key.city) ?? DefaultPlace.city
    state = defaults.string(forKey: Key.state) ?? ""
    country = defaults.string(forKey: Key.country) ?? "SA"
    countryName = defaults.string(forKey: Key.countryName) ?? DefaultPlace.countryName
    storedTimeZone = defaults.string(forKey: Key.timeZone) ?? "Asia/Riyadh"
    latitude = defaults.double(forKey: Key.latitude)
    longitude = defaults.double(forKey: Key.longitude)

    methodPreference =
      MethodPreference(rawValue: defaults.integer(forKey: Key.method)) ?? .ummAlQura
    madhabPreference = MadhabPreference(rawValue: defaults.integer(forKey: Key.madhab)) ?? .shafi
    autoDetectMethod = defaults.bool(forKey: Key.autoDetectMethod)
    autoDetectHighLatitudeRule = defaults.bool(forKey: Key.autoDetectHighLatitudeRule)
    highLatitudeRulePreference =
      HighLatitudeRulePreference(rawValue: defaults.integer(forKey: Key.highLatitudeRule))
      ?? .middleOfTheNight
    customFajrAngle = defaults.double(forKey: Key.customFajrAngle)
    customIshaAngle = defaults.double(forKey: Key.customIshaAngle)

    fajrAdjustment = defaults.integer(forKey: Key.adjustmentFajr)
    shuruqAdjustment = defaults.integer(forKey: Key.adjustmentShuruq)
    dhuhrAdjustment = defaults.integer(forKey: Key.adjustmentDhuhr)
    asrAdjustment = defaults.integer(forKey: Key.adjustmentAsr)
    maghribAdjustment = defaults.integer(forKey: Key.adjustmentMaghrib)
    ishaAdjustment = defaults.integer(forKey: Key.adjustmentIsha)

    hijriOffset = defaults.integer(forKey: Key.hijriOffset)
    delayedIshaInRamadan = defaults.bool(forKey: Key.delayedIshaInRamadan)
    alertVolume = defaults.integer(forKey: Key.alertVolume)
    duaEnabled = defaults.bool(forKey: Key.duaEnabled)
    silentMode = defaults.bool(forKey: Key.silentMode)

    if let data = defaults.data(forKey: Key.notificationSettings),
      let decoded = try? JSONDecoder().decode([String: PrayerNotificationConfig].self, from: data)
    {
      var resolved = decoded.mapValues { $0.sanitized() }

      for prayer in PrayerKind.allCases where resolved[prayer.settingsKey] == nil {
        resolved[prayer.settingsKey] = PrayerNotificationConfig.defaultConfig(for: prayer)
      }

      notificationSettings = resolved
    } else {
      notificationSettings = PrayerNotificationConfig.initialSettings
    }

    jumuahOverrideEnabled = defaults.bool(forKey: Key.jumuahOverrideEnabled)
    if jumuahOverrideEnabled {
      seedJumuahConfigIfNeeded()
    }

    appLanguage =
      AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage) ?? "")
      ?? .system
    applyAppleLanguagesOverride()

    appearance = Self.loadAppearance(from: defaults)
    followsTimeOfDay = defaults.bool(forKey: Key.followsTimeOfDay)
    onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted)
    notificationPromptDeferred = defaults.bool(forKey: Key.notificationPromptDeferred)
    Key.retiredWidgetTheme.forEach(defaults.removeObject(forKey:))

    enforceVisibleMenuBarContent()

    // Stored values are loaded; from here, didSets emit refreshes.
    isLoading = false
  }
}

extension Comparable {
  /// The value, moved into `range` if it's outside.
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
