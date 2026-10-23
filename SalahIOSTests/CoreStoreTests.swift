import Foundation
import SalahCore
import SalahTimes
import SalahUI
import Testing

@Suite("iOS application state") @MainActor
struct CoreStoreTests {
  @Test func freshInstallDoesNotCalculateForAnInventedPlace() {
    let repository = CoreMemoryPreferences()
    let store = IOSAppStore(repository: repository)
    #expect(store.needsOnboarding)
    #expect(store.preferences.location == nil)
    #expect(store.display == nil)
    #expect(store.schedule == nil)
    store.completeOnboarding()
    #expect(store.onboardingStep == .location)
    #expect(!store.preferences.onboardingCompleted)
  }

  @Test func selectedLocationAndChoicesPersistAcrossConstruction() throws {
    let repository = CoreMemoryPreferences()
    let store = IOSAppStore(repository: repository)
    store.select(location: Self.makkah)
    store.updatePreferences {
      $0.language = .arabic
      $0.appearance = .dark
      $0.method = .preset(.ummAlQura)
      $0.notifications[.fajr]?.beforeEnabled = true
      $0.notifications[.fajr]?.beforeMinutes = 25
    }
    store.completeOnboarding()
    let restored = IOSAppStore(repository: repository)
    #expect(!restored.needsOnboarding)
    #expect(restored.isArabic)
    #expect(restored.preferences.location == Self.makkah)
    #expect(restored.settings?.alerts[.fajr]?.beforeMinutes == 25)
    #expect(restored.settings?.appearance == .dark)
    #expect(restored.schedule != nil)
  }

  @Test func fridayToggleEditsTheSameSettingsTheNamedEventUses() throws {
    let repository = CoreMemoryPreferences()
    let store = IOSAppStore(repository: repository)
    store.select(location: Self.makkah)
    store.updatePreferences {
      $0.jumuahOverrideEnabled = true
      $0.jumuahAlerts.atTime = false
      $0.notifications[.dhuhr]?.atTime = true
    }
    let day = CivilDay(year: 2026, month: 6, day: 5)
    let event = try #require(store.schedule?.day(day).day?[.dhuhr])
    #expect(event.observance == .jumuah)
    #expect(store.settings?.alerts(for: event).alert == false)
    store.toggleAlert(for: event)
    #expect(store.preferences.jumuahAlerts.atTime)
    #expect(store.preferences.notifications[.dhuhr]?.atTime == true)
    store.updatePreferences { $0.jumuahOverrideEnabled = false }
    #expect(store.settings?.alerts(for: event).alert == true)
  }

  @Test func sunriseDoesNotAcquireAPrayerApproachAndAfterIshaShowsTomorrow() throws {
    let repository = CoreMemoryPreferences()
    let store = IOSAppStore(repository: repository)
    store.select(location: Self.makkah)
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let listed = try #require(store.schedule?.day(day).day)
    let sunrise = try #require(listed[.sunrise])
    store.tick(at: sunrise.time.addingTimeInterval(-120))
    #expect(store.display?.focus?.event.kind == .sunrise)
    #expect(store.display?.prayerState?.isApproaching == false)
    let isha = try #require(listed[.isha])
    store.tick(at: isha.time.addingTimeInterval(16 * 60))
    #expect(store.display?.focus?.event.kind == .fajr)
    #expect(store.display?.focusIsTomorrow == true)
  }

  @Test func fridayOverrideSeedsDhuhrOnceAndPreservesItsOwnEdits() {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    store.updatePreferences {
      $0.notifications[.dhuhr]?.beforeEnabled = true
      $0.notifications[.dhuhr]?.beforeMinutes = 20
    }
    store.setJumuahOverrideEnabled(true)
    #expect(store.preferences.jumuahAlerts.beforeMinutes == 20)
    store.updatePreferences { $0.jumuahAlerts.beforeMinutes = 30 }
    store.setJumuahOverrideEnabled(false)
    store.updatePreferences { $0.notifications[.dhuhr]?.beforeMinutes = 15 }
    store.setJumuahOverrideEnabled(true)
    #expect(store.preferences.jumuahAlerts.beforeMinutes == 30)
    #expect(store.preferences.alerts(for: .dhuhr).beforeMinutes == 15)
  }

  @Test func midnightAdvancesTodayButPreservesAnExplicitlySelectedHistoricalDay() {
    let repository = CoreMemoryPreferences()
    let store = IOSAppStore(repository: repository)
    store.select(location: Self.makkah)
    let first = CivilDay(year: 2026, month: 6, day: 2)
    let second = first.adding(days: 1)
    store.tick(at: first.start(in: Self.makkah.timeZone))
    store.selectedDay = first
    store.tick(at: second.start(in: Self.makkah.timeZone))
    #expect(store.selectedDay == second)
    store.selectedDay = first.adding(days: -2)
    store.tick(at: second.adding(days: 1).start(in: Self.makkah.timeZone))
    #expect(store.selectedDay == first.adding(days: -2))
  }

  @Test func deepLinksReachTheRequestedSettingsDestinationAndValidateCalendarDates() {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    store.handle(url: URL(string: "salah://settings/notifications")!)
    #expect(store.selectedTab == .settings)
    #expect(store.settingsPath == [.alerts])
    store.handle(url: URL(string: "salah://location")!)
    #expect(store.settingsPath == [.location])
    store.handle(url: URL(string: "salah://times?date=2026-06-02")!)
    #expect(store.selectedTab == .times)
    #expect(store.selectedDay == CivilDay(year: 2026, month: 6, day: 2))
    store.handle(url: URL(string: "salah://times?date=2026-02-30")!)
    #expect(store.selectedDay == CivilDay(year: 2026, month: 6, day: 2))
    store.handle(url: URL(string: "https://settings/sound")!)
    #expect(store.selectedTab == .times)
  }

  @Test func regularWidthSettingsSelectCalculationOnlyWhenNoCategoryIsSelected() {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    #expect(store.selectedSettingsDestination == nil)
    store.prepareSettingsForRegularWidth()
    #expect(store.settingsPath == [.calculation])
    store.handle(url: URL(string: "salah://settings/sound")!)
    store.prepareSettingsForRegularWidth()
    #expect(store.selectedSettingsDestination == .sound)
    store.handle(url: URL(string: "salah://location")!)
    store.prepareSettingsForRegularWidth()
    #expect(store.settingsPath == [.location])
  }

  @Test func settingsSidebarSelectionReplacesAndClearsTheCompactNavigationPath() {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    store.settingsPath = [.location, .sound]
    #expect(store.selectedSettingsDestination == .location)
    store.selectedSettingsDestination = .language
    #expect(store.settingsPath == [.language])
    store.selectedSettingsDestination = nil
    #expect(store.settingsPath.isEmpty)
  }

  @Test func eachSettingsCategoryResolvesThroughItsTypedDeepLink() throws {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    for destination in IOSSettingsDestination.allCases {
      let url = try #require(URL(string: "salah://settings/\(destination.rawValue)"))
      store.handle(url: url)
      #expect(store.selectedTab == .settings)
      #expect(store.selectedSettingsDestination == destination)
    }
  }

  @Test func selectingCitiesKeepsFiveDistinctRecentPlaces() {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    for index in 0..<7 {
      var place = Self.makkah
      place.latitude += Double(index)
      place.name = "City \(index)"
      store.select(location: place)
    }
    #expect(store.preferences.recentLocations.count == 5)
    #expect(store.preferences.recentLocations.first?.name == "City 6")
    if let place = store.preferences.location { store.select(location: place) }
    #expect(store.preferences.recentLocations.count == 5)
  }

  @Test func weekNavigationUsesTheDesignedMondayToSundayCivilDays() {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    store.selectedDay = CivilDay(year: 2026, month: 10, day: 16)
    #expect(store.weekDays.first == CivilDay(year: 2026, month: 10, day: 12))
    #expect(store.weekDays.last == CivilDay(year: 2026, month: 10, day: 18))
    store.selectedDay = CivilDay(year: 2026, month: 10, day: 18)
    #expect(store.weekDays.first == CivilDay(year: 2026, month: 10, day: 12))
  }

  @Test func staleUIChangesDoNotUndoAControlCenterMute() {
    let repository = CoreMemoryPreferences()
    let store = IOSAppStore(repository: repository)
    repository.value = IOSPreferences()
    repository.value?.muteSounds = true
    store.updatePreferences { $0.appearance = .dark }
    #expect(store.preferences.muteSounds)
    #expect(store.preferences.appearance == .dark)
    #expect(repository.value?.muteSounds == true)
  }

  @Test func automaticMethodFollowsKnownRegionsAndKeepsTheLastManualChoiceElsewhere() {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    store.select(location: Self.makkah)
    store.updatePreferences { $0.method = .preset(.egyptian) }
    store.updatePreferences { $0.method = .automatic }
    #expect(store.preferences.resolvedMethod == .ummAlQura)
    var unsupported = Self.makkah
    unsupported.countryCode = nil
    store.select(location: unsupported)
    #expect(store.preferences.resolvedMethod == .egyptian)
    #expect(store.preferences.automaticFallbackMethod == .egyptian)
    store.select(location: Self.makkah)
    #expect(store.preferences.resolvedMethod == .ummAlQura)
    #expect(store.preferences.automaticFallbackMethod == .egyptian)
  }

  @Test func unsavedEditsAreRetriedWithoutLosingInterveningControlChanges() {
    let repository = CoreMemoryPreferences()
    let store = IOSAppStore(repository: repository)
    repository.failWrites = true
    store.updatePreferences { $0.appearance = .dark }
    #expect(store.persistenceFailed)
    #expect(store.preferences.appearance == .dark)
    repository.value = IOSPreferences()
    repository.value?.muteSounds = true
    repository.failWrites = false
    store.refresh()
    #expect(!store.persistenceFailed)
    #expect(store.preferences.appearance == .dark)
    #expect(store.preferences.muteSounds)
    #expect(repository.value?.appearance == .dark)
  }

  @Test func qiblaUsesTheConfiguredPlaceAndHasNoDirectionAtTheKaaba() throws {
    let store = IOSAppStore(repository: CoreMemoryPreferences())
    #expect(store.qiblaBearing == nil)
    store.select(location: Self.makkah)
    #expect(store.qiblaBearing == nil)
    #expect(store.qiblaDistanceKilometers == 0)
    let zone = try #require(TimeZone(identifier: "Europe/London"))
    store.select(location: PrayerLocation(latitude: 51.5072, longitude: -0.1276, timeZone: zone))
    let bearing = try #require(store.qiblaBearing)
    #expect((118...120).contains(bearing))
    let distance = try #require(store.qiblaDistanceKilometers)
    #expect((4_700...4_900).contains(distance))
  }

  static var makkah: PrayerLocation {
    PrayerLocation(
      latitude: Qibla.kaaba.latitude, longitude: Qibla.kaaba.longitude,
      timeZone: TimeZone(identifier: "Asia/Riyadh")!, countryCode: "SA", name: "Makkah")
  }
}

@MainActor
private final class CoreMemoryPreferences: IOSPreferencesRepository {
  var value: IOSPreferences?
  var failWrites = false
  func load() throws -> IOSPreferences? { value }
  func save(_ preferences: IOSPreferences) throws {
    if failWrites { throw CocoaError(.fileWriteOutOfSpace) }
    value = preferences
  }
}
