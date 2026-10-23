import Foundation

extension Preferences {
  func registerDefaults() {
    defaults.register(defaults: [
      Key.displayNextPrayer: true,
      Key.displayNextPrayerType: 0,
      Key.displayNextPrayerName: 0,
      Key.displayIcon: true,
      Key.autoLocation: true,
      Key.city: "Makkah",
      Key.state: "Makkah",
      Key.country: "SA",
      Key.countryName: "Saudi Arabia",
      Key.latitude: 21.4167,
      Key.longitude: 39.8167,
      Key.timeZone: "Asia/Riyadh",
      Key.madhab: 0,
      Key.method: MethodPreference.ummAlQura.rawValue,
      Key.highLatitudeRule: 0,
      Key.autoDetectMethod: true,
      Key.autoDetectHighLatitudeRule: true,
      Key.customFajrAngle: 18.0,
      Key.customIshaAngle: 17.5,
      Key.hijriOffset: 0,
      Key.delayedIshaInRamadan: true,
      Key.alertVolume: 50,
      Key.duaEnabled: true,
      Key.silentMode: false,
      Key.jumuahOverrideEnabled: false,
      Key.appLanguage: AppLanguage.system.rawValue,
      Key.followsTimeOfDay: true,
    ])
  }
}
