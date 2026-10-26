import Foundation
import Observation
import SalahCore
import SwiftUI

/// The composition root owns side effects. Views and domain state never construct system
/// services.
@MainActor @Observable
final class TVAppRuntime {
  let store: IOSAppStore
  let navigation: TVNavigation
  let location: TVLocationService
  let citySearch: IOSCitySearchService
  let audio: TVAudioService
  private(set) var topShelfError: String?
  /// Whether the screen stays on: while Salah is active and the room display or the adhan
  /// is showing.
  private(set) var keepsScreenOn = false
  @ObservationIgnored let adhan: TVAdhanCoordinator
  @ObservationIgnored private let idleTimer: any TVIdleTimerControlling
  @ObservationIgnored private let topShelf: TVTopShelfPublisher
  @ObservationIgnored private var nextPrayerID: String?
  @ObservationIgnored private var publishedPhase: SalahPhase?
  @ObservationIgnored private var isActive = false

  init(
    configuration: TVLaunchConfiguration = TVLaunchConfiguration(),
    idleTimer: any TVIdleTimerControlling = TVApplicationIdleTimer(),
    topShelf: TVTopShelfPublisher = TVTopShelfPublisher()
  ) {
    let clock = configuration.clock
    store = IOSAppStore(repository: configuration.repository, now: { clock.now() })
    navigation = TVNavigation()
    location = TVLocationService()
    citySearch = IOSCitySearchService()
    audio = TVAudioService()
    adhan = TVAdhanCoordinator(clock: TVAlertClock(clock: clock), defaults: configuration.defaults)
    self.idleTimer = idleTimer
    self.topShelf = topShelf
    connect()
    if let route = configuration.route { navigation.open(route) }
  }

  private func connect() {
    store.onPreferencesChanged = { [weak self] _ in self?.replan(catchingUp: false) }
    store.onStopPlayback = { [weak self] in self?.audio.stop() }
    location.onLocationChanged = { [weak self] location in
      guard let self else { return }
      self.store.updatePreferences {
        $0.location = location
        $0.useCurrentLocation = true
      }
    }
    location.onAuthorizationChanged = { [weak self] status in
      self?.store.setLocationPermission(status)
    }
    adhan.onDue = { [weak self] event in self?.adhanDue(event) }
    audio.onPlaybackChanged = { [weak self] playing in
      guard let self, !playing else { return }
      self.store.setPlayback(nil)
      self.navigation.adhanEnded()
      self.updateKeepsScreenOn()
    }
  }

  func activate() {
    isActive = true
    store.refresh()
    location.refreshAuthorization()
    replan(catchingUp: true)
    adhan.resync()
    // The room display stays presented while Salah is hidden, and doesn't appear again.
    updateKeepsScreenOn()
  }

  /// The adhan plays only while Salah is open, so leaving stops it and plans nothing until
  /// Salah is back.
  func deactivate() {
    isActive = false
    audio.stop()
    adhan.suspend()
    citySearch.cancel()
    location.cancelLocation()
    updateKeepsScreenOn()
  }

  func runClock() async {
    while !Task.isCancelled {
      let previousDay = store.today
      store.tick()
      if previousDay != store.today {
        replan(catchingUp: true)
      } else if store.display?.prayerState?.nextPrayer?.id != nextPrayerID
        || store.display?.phase != publishedPhase
      {
        // Sunrise changes the Today banner's sky but not the next prayer.
        publishTopShelf()
      }
      do { try await Task.sleep(for: .seconds(1)) } catch { return }
    }
  }

  /// The clock or the time zone changed: replan from the new instant.
  func timeContextChanged() {
    store.refresh()
    replan(catchingUp: true)
    adhan.resync()
  }

  // MARK: - Actions from views

  /// Asks for this Apple TV's location once, with When In Use permission.
  func useCurrentLocation() {
    location.requestLocation()
  }

  /// A city chosen from search: it stops following this Apple TV's location.
  func choose(city: PrayerLocation) {
    location.cancelLocation()
    store.select(location: city)
  }

  /// Plays a sound once from Settings, so the person can hear it. It never replaces the
  /// adhan playing for a prayer, which can come due as the sound is chosen.
  func preview(_ sound: IOSSound) {
    guard store.playback == nil else { return }
    audio.play(sound, volume: store.preferences.playbackVolume, locale: store.locale)
  }

  /// Stops a preview. The adhan playing for a prayer plays on: its screen can cover the page
  /// that previewed, which then disappears.
  func stopSound() {
    guard store.playback == nil else { return }
    audio.stop()
  }

  /// Stop, Play/Pause and Back on the adhan all stop it; the screen it covered comes back.
  func stopAdhan() {
    audio.stop()
    store.setPlayback(nil)
    navigation.adhanEnded()
    updateKeepsScreenOn()
  }

  /// The room display keeps the screen on while it's open. When the adhan replaces it, the
  /// screen stays on for the adhan.
  func roomDisplayAppeared() { updateKeepsScreenOn() }
  func roomDisplayDisappeared() { updateKeepsScreenOn() }

  private func updateKeepsScreenOn() {
    let value = isActive && navigation.fullScreen != nil
    guard value != keepsScreenOn else { return }
    keepsScreenOn = value
    idleTimer.keepsScreenOn = value
  }

  // MARK: - Effects

  private func adhanDue(_ event: PrayerEvent) {
    let preferences = store.preferences
    guard !preferences.muteSounds else { return }
    let sound = preferences.tvSound(for: event.kind, observance: event.observance)
    let dua: Bool
    switch sound {
    case .adhan, .fajrAdhan: dua = preferences.duaEnabled && event.kind != .sunrise
    default: dua = false
    }
    guard
      audio.play(sound, volume: preferences.playbackVolume, duaAfter: dua, locale: store.locale)
    else { return }
    store.setPlayback(SalahPlayback(event: event, slot: .alert), hasQueuedDua: audio.hasQueuedDua)
    navigation.showAdhan(for: event)
    updateKeepsScreenOn()
  }

  /// Applies the preferences and plans the adhan. `catchingUp` plays an adhan that began in
  /// the last five minutes: on activation, a new day and a clock change, never for a
  /// settings change.
  private func replan(catchingUp: Bool) {
    if store.preferences.muteSounds { audio.stop() }
    audio.setVolume(store.preferences.playbackVolume)
    adhan.update(
      schedule: store.schedule, preferences: store.preferences, catchingUp: catchingUp)
    publishTopShelf()
  }

  private func publishTopShelf() {
    nextPrayerID = store.display?.prayerState?.nextPrayer?.id
    publishedPhase = store.display?.phase
    do {
      try topShelf.publish(
        store.settings, nextPrayer: nextPrayerID, day: store.today, phase: publishedPhase)
      topShelfError = nil
    } catch {
      topShelfError = String(describing: error)
    }
  }
}
