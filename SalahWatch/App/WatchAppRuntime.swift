import Foundation
import Observation
import SalahCore
@preconcurrency import UserNotifications

/// The composition root owns side effects. Views and domain state never construct system
/// services.
@MainActor @Observable
final class WatchAppRuntime {
  let store: IOSAppStore
  let navigation: WatchNavigation
  let heading: WatchHeadingService
  let audio: WatchAudioService
  private(set) var complicationError: String?
  @ObservationIgnored let receiver: WatchPreferencesReceiver
  @ObservationIgnored let adhan: WatchAdhanCoordinator
  /// A compass reading a Debug journey fixes, in place of the simulator's missing compass.
  @ObservationIgnored let fixedHeading: WatchHeading?
  @ObservationIgnored private let complications: WatchComplicationPublisher
  @ObservationIgnored private let notifications: WatchNotificationPresenter
  @ObservationIgnored private var isActive = false

  init(
    configuration: WatchLaunchConfiguration = WatchLaunchConfiguration(),
    receiver: WatchPreferencesReceiver? = nil,
    complications: WatchComplicationPublisher = WatchComplicationPublisher(),
    notificationCenter: UNUserNotificationCenter? = .current()
  ) {
    let clock = configuration.clock
    store = IOSAppStore(repository: configuration.repository, now: { clock.now() })
    navigation = WatchNavigation(tab: configuration.tab ?? .now)
    heading = WatchHeadingService()
    audio = WatchAudioService()
    adhan = WatchAdhanCoordinator(
      clock: WatchAlertClock(clock: clock), defaults: configuration.defaults)
    fixedHeading = configuration.heading
    self.receiver = receiver ?? WatchPreferencesReceiver(defaults: configuration.defaults)
    self.complications = complications
    let audio = audio
    notifications = WatchNotificationPresenter(isPlaying: { audio.isPlaying })
    notificationCenter?.delegate = notifications
    connect()
    publishComplications()
  }

  private func connect() {
    store.onPreferencesChanged = { [weak self] _ in self?.preferencesChanged() }
    store.onStopPlayback = { [weak self] in self?.audio.stop() }
    receiver.onPreferences = { [weak self] preferences in self?.received(preferences) ?? false }
    receiver.hasPreferences = { [weak self] in self?.store.settings != nil }
    adhan.onDue = { [weak self] event in self?.adhanDue(event) }
    audio.onPlaybackChanged = { [weak self] playing in
      guard let self else { return }
      if !playing {
        self.store.setPlayback(nil)
      } else if var playback = self.store.playback {
        playback.isDua = self.audio.isPlayingDua
        self.store.setPlayback(playback, hasQueuedDua: self.audio.hasQueuedDua)
      }
    }
  }

  /// Salah is on screen: plan the adhan and catch up with what arrived while it was away.
  func activate() {
    isActive = true
    store.refresh()
    replan(catchingUp: true)
    adhan.resync()
    receiver.sessionActivated()
  }

  /// Salah left the screen: the adhan stops, nothing is planned until it's back, and the
  /// compass rests. With the wrist lowered Salah stays frontmost, so that doesn't call this.
  func deactivate() {
    isActive = false
    audio.stop()
    adhan.suspend()
    heading.stop()
  }

  /// Moves the clock while Salah runs: every second on screen, and at each minute with the
  /// wrist down, when the watch redraws once a minute.
  func runClock(minutely: Bool = false) async {
    while !Task.isCancelled {
      let previousDay = store.today
      store.tick()
      if previousDay != store.today { replan(catchingUp: true) }
      let delay =
        minutely ? 60 - store.now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) : 1
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
    }
  }

  /// The clock or the time zone changed: replan from the new instant.
  func timeContextChanged() {
    store.refresh()
    replan(catchingUp: true)
    adhan.resync()
  }

  /// Stop on the adhan's hero.
  func stopAdhan() {
    audio.stop()
    store.setPlayback(nil)
  }

  /// The system woke Salah in the background to deliver the iPhone's preferences: wait until
  /// they're received.
  func finishPendingTransfers() async {
    await receiver.finishPendingContent()
  }

  // MARK: - Effects

  /// Keeps preferences from the iPhone; returns whether they were stored.
  private func received(_ preferences: IOSPreferences) -> Bool {
    store.updatePreferences { $0 = preferences }
    return !store.persistenceFailed
  }

  private func preferencesChanged() {
    replan(catchingUp: false)
    publishComplications()
  }

  private func adhanDue(_ event: PrayerEvent) {
    let preferences = store.preferences
    guard isActive, !preferences.muteSounds else { return }
    let sound = preferences.watchSound(for: event.kind, observance: event.observance)
    let dua =
      [.adhan, .fajrAdhan].contains(sound) && preferences.duaEnabled && event.kind != .sunrise
    guard audio.play(sound, volume: preferences.playbackVolume, duaAfter: dua) else { return }
    store.setPlayback(SalahPlayback(event: event, slot: .alert), hasQueuedDua: audio.hasQueuedDua)
    navigation.tab = .now
  }

  /// Applies the preferences and plans the adhan. `catchingUp` plays an adhan that began in
  /// the last five minutes: on activation, a new day and a clock change, never for
  /// preferences from the iPhone.
  private func replan(catchingUp: Bool) {
    if store.preferences.muteSounds { stopAdhan() }
    audio.setVolume(store.preferences.playbackVolume)
    guard isActive else { return }
    adhan.update(
      schedule: store.schedule, preferences: store.preferences, catchingUp: catchingUp)
  }

  private func publishComplications() {
    // When the stored preferences can't be read, the published settings are still the
    // person's, so they stay.
    guard !store.storedPreferencesUnreadable else { return }
    do {
      try complications.publish(store.settings)
      complicationError = nil
    } catch {
      complicationError = String(describing: error)
    }
  }
}
