import BackgroundTasks
import Foundation
import Observation
import SalahCore
import SalahWidgets
import SwiftUI
import UIKit
import WidgetKit

/// The order a changed preference reaches the surfaces outside the app.
///
/// The Live Activity is on screen now, so a new language or setting reaches it first. The
/// notifications take longer to schedule and aren't seen until they fire.
@MainActor struct IOSSurfaceRefresh {
  var activity: () async -> Void
  var notifications: () async -> Void

  /// A newer change cancels this one before its notifications are scheduled twice.
  func run() async {
    await activity()
    guard !Task.isCancelled else { return }
    await notifications()
  }
}

/// The composition root owns side effects. Views and domain state never construct system services.
@MainActor @Observable
final class IOSAppRuntime {
  let store: IOSAppStore
  let location: IOSLocationService
  let citySearch: IOSCitySearchService
  let notifications: IOSNotificationService
  let audio: IOSAudioService
  let activities: IOSActivityCoordinator
  let watch: IOSWatchSync
  private(set) var widgetError: String?
  @ObservationIgnored private let widgets = IOSWidgetPublisher()
  @ObservationIgnored private let placeNamer: any IOSPlaceNaming
  @ObservationIgnored private var placeNameTask: Task<Void, Never>?
  @ObservationIgnored private var hadEnabledAlerts: Bool?
  @ObservationIgnored private var unanswered: IOSPlaceQuestion?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var stopObservation: DarwinSignal.Observation?
  @ObservationIgnored private var preferencesObservation: DarwinSignal.Observation?
  @ObservationIgnored private var foreground = false
  /// Whether the next activation follows a launch or a stay in the background, rather than a
  /// moment under Control Center or a system alert.
  @ObservationIgnored private var returning = true
  @ObservationIgnored private let isTesting: Bool
  static let refreshIdentifier = "com.omarkhaled.salah.iOS.refresh"

  init(configuration: IOSLaunchConfiguration = IOSLaunchConfiguration()) {
    store = IOSAppStore(repository: configuration.repository, now: configuration.now)
    location = IOSLocationService()
    citySearch = IOSCitySearchService()
    notifications = IOSNotificationService()
    audio = IOSAudioService()
    activities = IOSActivityCoordinator()
    watch = IOSWatchSync()
    isTesting = configuration.isTesting
    placeNamer = configuration.isTesting ? IOSFixturePlaceNamer() : IOSMapKitPlaceNamer()
    connect()
    // iOS can launch Salah in the background for the watch's request, before any scene.
    watch.send(store.preferences)
  }

  private func connect() {
    store.onPreferencesChanged = { [weak self] _ in self?.preferencesChanged() }
    store.onStopPlayback = { [weak self] in self?.audio.stop() }
    store.onPlayPrayer = { [weak self] event in self?.play(event: event) }
    location.onLocationChanged = { [weak self] location in
      guard let self, self.store.preferences.useCurrentLocation else { return }
      self.store.updatePreferences { $0.location = location }
    }
    location.onAuthorizationChanged = { [weak self] status in
      self?.store.setLocationPermission(status)
    }
    notifications.onAuthorizationChanged = { [weak self] status in
      guard let self else { return }
      let previous = self.store.notificationPermission
      self.store.setNotificationPermission(status)
      if previous != status { self.preferencesChanged() }
    }
    notifications.onOpenURL = { [weak self] url in self?.store.handle(url: url) }
    audio.onPlaybackChanged = { [weak self] playing in
      guard let self else { return }
      if !playing {
        self.store.setPlayback(nil)
      } else if var playback = self.store.playback {
        playback.isDua = self.audio.isPlayingDua
        self.store.setPlayback(playback, hasQueuedDua: self.audio.hasQueuedDua)
      }
      self.publishPlayback()
      Task {
        await self.activities.refresh(settings: self.store.settings, isForeground: self.foreground)
      }
    }
    stopObservation = DarwinSignal.stopAudio.observe { [weak self] in self?.audio.stop() }
    IOSAudioStopper.stopInProcess = { [weak self] in await self?.stopFromIntent() }
    preferencesObservation = DarwinSignal(name: IOSSharedPreferencesStore.changedSignalName).observe
    {
      [weak self] in
      guard let self, !self.isTesting else { return }
      self.store.refresh()
      self.preferencesChanged()
    }
  }

  func activate() async {
    foreground = true
    store.refresh()
    if hadEnabledAlerts == nil { hadEnabledAlerts = store.preferences.hasEnabledAlerts }
    location.refreshAuthorization()
    if store.preferences.useCurrentLocation { location.requestLocation() }
    await notifications.refreshAuthorization()
    publishSettings()
    unanswered = nil
    namePlace()
    watch.send(store.preferences)
    // Coming back to Salah shows its activity again, even one the person swiped away. The
    // scene can leave the foreground while this waits.
    let returning = returning && foreground
    if foreground { self.returning = false }
    await activities.refresh(
      settings: store.settings, isForeground: foreground, returning: returning)
    await refreshNotifications()
    submitBackgroundRefresh()
  }

  /// `inBackground` is false while the scene is only inactive, under Control Center or an alert.
  func deactivate(inBackground: Bool = true) {
    foreground = false
    if inBackground { returning = true }
    location.stopHeading()
    citySearch.cancel()
    submitBackgroundRefresh()
  }

  func runClock() async {
    var seconds = 0
    while !Task.isCancelled {
      let previousDay = store.today
      store.tick()
      if previousDay != store.today { preferencesChanged() }
      seconds += 1
      if seconds.isMultiple(of: 30) {
        await activities.refresh(settings: store.settings, isForeground: foreground)
      }
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
    }
  }

  func timeContextChanged() {
    store.refresh()
    preferencesChanged()
  }

  private func preferencesChanged() {
    askForNotificationsIfAnAlertWasTurnedOn()
    if store.preferences.muteSounds { audio.stop() }
    audio.setVolume(store.preferences.playbackVolume)
    if !store.preferences.useCurrentLocation { location.cancelLocation() }
    publishSettings()
    namePlace()
    watch.send(store.preferences)
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      guard let self else { return }
      await IOSSurfaceRefresh(
        activity: {
          await self.activities.refresh(
            settings: self.store.settings, isForeground: self.foreground)
        },
        notifications: { await self.refreshNotifications() }
      ).run()
    }
  }

  /// Looks the saved place's name up in Salah's language when no name is kept for it yet,
  /// once for each place and language. Offline, the saved name stays until another place or
  /// language, or a return to the app, asks again.
  private func namePlace() {
    var seeded = store.preferences
    seeded.seedPlaceNames(deviceLanguageCode: IOSPreferences.deviceLanguageCode)
    if seeded != store.preferences {
      // Saving the names comes back here through the store's change.
      store.updatePreferences { $0.placeNames = seeded.placeNames }
      return
    }
    let preferences = store.preferences
    guard let location = preferences.location, preferences.needsPlaceName else { return }
    let languageCode = preferences.placeLanguageCode
    // A place the geocoder has no name for is asked about once for each return to the app.
    let asked = IOSPlaceQuestion(location: location, languageCode: languageCode)
    guard asked != unanswered else { return }
    let locale = preferences.language.locale
    placeNameTask?.cancel()
    placeNameTask = Task { [weak self] in
      guard let self else { return }
      let name = await self.placeNamer.name(of: location, in: locale)
      guard !Task.isCancelled else { return }
      guard let name else {
        self.unanswered = asked
        return
      }
      self.store.updatePreferences {
        $0.setPlaceName(name, languageCode: languageCode, for: location)
      }
    }
  }

  private func refreshNotifications() async {
    await notifications.refresh(schedule: store.schedule, preferences: store.preferences)
  }

  private func publishSettings() {
    // Without a location there are no settings to publish. Before setup the widgets have none,
    // and when the stored settings can't be read, the published ones are still the user's.
    guard let settings = store.settings else { return }
    do {
      try widgets.publish(settings)
      widgetError = nil
    } catch {
      widgetError = String(describing: error)
    }
  }

  /// A person who chose Silent during setup was never asked about notifications. Turning the
  /// first alert on is when the question means something.
  private func askForNotificationsIfAnAlertWasTurnedOn() {
    let enabled = store.preferences.hasEnabledAlerts
    defer { hadEnabledAlerts = enabled }
    guard
      IOSAlertPermissionPolicy.asks(
        hadEnabledAlerts: hadEnabledAlerts, hasEnabledAlerts: enabled,
        status: store.notificationPermission, isSetUp: !store.needsOnboarding)
    else { return }
    Task { await notifications.requestAuthorization() }
  }

  /// Stop on the Live Activity or in Control Center: the audio stops and the activity shows
  /// it before the intent returns.
  private func stopFromIntent() async {
    audio.stop()
    store.setPlayback(nil)
    publishPlayback()
    await activities.refresh(settings: store.settings, isForeground: foreground)
  }

  private func publishPlayback() {
    do {
      try SharedValue.playback.save(
        store.playback, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
      let session: IOSPlaybackSession?
      if let playback = store.playback, let start = audio.playbackStartedAt,
        let end = audio.expectedPlaybackEnd
      {
        session = IOSPlaybackSession(
          playback: playback, startedAt: start, duration: end.timeIntervalSince(start))
      } else {
        session = nil
      }
      try SharedValue.iosPlayback.save(
        session, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
      ControlCenter.shared.reloadControls(ofKind: IOSControlKind.stopAudio)
    } catch {
      widgetError = String(describing: error)
    }
  }

  private func play(event: PrayerEvent) {
    guard !store.preferences.muteSounds else { return }
    let sound = store.preferences.alerts(for: event.kind, observance: event.observance).sound
    let dua: Bool
    switch sound {
    case .adhan, .fajrAdhan, .custom:
      dua = store.preferences.duaEnabled && event.kind != .sunrise
    case .none, .system, .softTone:
      dua = false
    }
    audio.play(sound, volume: store.preferences.playbackVolume, duaAfter: dua, locale: store.locale)
    guard audio.isPlaying else { return }
    store.setPlayback(
      SalahPlayback(event: event, slot: .alert), hasQueuedDua: audio.hasQueuedDua)
    publishPlayback()
    guard let settings = store.settings else { return }
    Task { await activities.start(settings: settings) }
  }

  func registerBackgroundRefresh() {
    guard !isTesting else { return }
    BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshIdentifier, using: .main) {
      [weak self] task in
      Task { @MainActor [weak self] in
        guard let self else {
          task.setTaskCompleted(success: false)
          return
        }
        let work = Task { @MainActor in
          self.store.refresh()
          // Ends an activity whose prayer has passed; a background wake never starts one.
          // Without settings (preferences it couldn't read) it leaves the activity alone.
          if let settings = self.store.settings {
            await self.activities.refresh(settings: settings, isForeground: false)
          }
          await self.refreshNotifications()
          self.publishSettings()
          self.watch.send(self.store.preferences)
          self.submitBackgroundRefresh()
          // An expired task was completed by its expiration handler.
          guard !Task.isCancelled else { return }
          task.setTaskCompleted(success: true)
        }
        // iOS expects the task to end promptly once it expires, not after the work finishes.
        task.expirationHandler = {
          work.cancel()
          task.setTaskCompleted(success: false)
        }
      }
    }
  }

  private func submitBackgroundRefresh() {
    // Unreadable preferences keep the refresh, so a later read can still recover them.
    guard !isTesting, store.preferences.location != nil || store.storedPreferencesUnreadable
    else { return }
    let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
    request.earliestBeginDate = Date().addingTimeInterval(6 * 60 * 60)
    // iOS decides when refresh runs. Existing scheduled notifications remain valid if it declines.
    try? BGTaskScheduler.shared.submit(request)
  }
}
