import BackgroundTasks
import Foundation
import Observation
import SalahCore
import SalahWidgets
import SwiftUI
import UIKit
import WidgetKit

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
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var stopObservation: DarwinSignal.Observation?
  @ObservationIgnored private var preferencesObservation: DarwinSignal.Observation?
  @ObservationIgnored private var foreground = false
  @ObservationIgnored private let isTesting: Bool
  static let refreshIdentifier = "io.github.salah-kit.Salah.iOS.refresh"

  init(configuration: IOSLaunchConfiguration = IOSLaunchConfiguration()) {
    store = IOSAppStore(repository: configuration.repository, now: configuration.now)
    location = IOSLocationService()
    citySearch = IOSCitySearchService()
    notifications = IOSNotificationService()
    audio = IOSAudioService()
    activities = IOSActivityCoordinator()
    watch = IOSWatchSync()
    isTesting = configuration.isTesting
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
    location.refreshAuthorization()
    if store.preferences.useCurrentLocation { location.requestLocation() }
    await notifications.refreshAuthorization()
    publishSettings()
    watch.send(store.preferences)
    await refreshNotifications()
    // The scene can leave the foreground while this waits.
    await activities.refresh(settings: store.settings, isForeground: foreground)
    submitBackgroundRefresh()
  }

  func deactivate() {
    foreground = false
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
    if store.preferences.muteSounds { audio.stop() }
    audio.setVolume(store.preferences.playbackVolume)
    if !store.preferences.useCurrentLocation { location.cancelLocation() }
    publishSettings()
    watch.send(store.preferences)
    refreshTask?.cancel()
    refreshTask = Task { [weak self] in
      guard let self else { return }
      await refreshNotifications()
      guard !Task.isCancelled else { return }
      await activities.refresh(settings: store.settings, isForeground: foreground)
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
      let changed = try SharedValue.settings.save(
        settings, reloading: [SalahWidgetConstants.prayerTimesWidgetKind])
      if changed { ControlCenter.shared.reloadControls(ofKind: IOSControlKind.muteSounds) }
      widgetError = nil
    } catch {
      widgetError = String(describing: error)
    }
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
