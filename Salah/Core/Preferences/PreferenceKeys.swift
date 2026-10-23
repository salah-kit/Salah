import Foundation

extension Preferences {
  enum Key {
    static let displayNextPrayer = "salah.displayNextPrayer"
    static let displayNextPrayerType = "salah.displayNextPrayerType"
    static let displayNextPrayerName = "salah.displayNextPrayerName"
    static let displayIcon = "salah.displayIcon"
    static let autoLocation = "salah.autoLocation"
    static let city = "salah.city"
    static let state = "salah.state"
    static let country = "salah.country"
    static let countryName = "salah.countryName"
    static let latitude = "salah.latitude"
    static let longitude = "salah.longitude"
    static let timeZone = "salah.timeZone"
    static let madhab = "salah.madhab"
    static let method = "salah.method"
    static let highLatitudeRule = "salah.highLatitudeRule"
    static let autoDetectMethod = "salah.autoDetectMethod"
    static let autoDetectHighLatitudeRule = "salah.autoDetectHighLatitudeRule"
    static let customFajrAngle = "salah.customFajrAngle"
    static let customIshaAngle = "salah.customIshaAngle"
    static let adjustmentFajr = "salah.adjustmentFajr"
    static let adjustmentShuruq = "salah.adjustmentShuruq"
    static let adjustmentDhuhr = "salah.adjustmentDhuhr"
    static let adjustmentAsr = "salah.adjustmentAsr"
    static let adjustmentMaghrib = "salah.adjustmentMaghrib"
    static let adjustmentIsha = "salah.adjustmentIsha"
    static let hijriOffset = "salah.hijriOffset"
    static let delayedIshaInRamadan = "salah.delayedIshaInRamadan"
    static let alertVolume = "salah.alertVolume"
    static let duaEnabled = "salah.duaEnabled"
    static let silentMode = "salah.silentMode"
    static let notificationSettings = "salah.notificationSettings"
    static let jumuahOverrideEnabled = "salah.jumuahOverrideEnabled"
    static let appLanguage = "salah.appLanguage"
    static let appearance = "salah.appearance"
    static let followsTimeOfDay = "salah.followsTimeOfDay"
    /// The retired widget theme's appearance, read once to carry an Always Dark or Always
    /// Light choice over to `appearance`.
    static let retiredWidgetAppearance = "salah.widgetAppearance"
    /// The retired widget theme's keys, removed at launch.
    static let retiredWidgetTheme = [
      "salah.widgetThemeID", "salah.widgetCustomAccent", "salah.widgetCustomPrimary",
      "salah.widgetCustomBase", retiredWidgetAppearance,
    ]
  }
}
