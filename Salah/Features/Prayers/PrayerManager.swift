import AppKit
import Foundation
import OSLog
import SalahCore
import SalahWidgets
import UserNotifications

/// The running app's prayer state: the schedule the preferences describe, its state now,
/// the menu-bar text, the alerts, and the App Group mirror the widget builds from.
@Observable
final class PrayerManager {
  /// The settings the widget mirror holds, rebuilt from the preferences.
  private(set) var settings: SalahSettings
  /// The schedule the settings describe.
  private(set) var schedule: PrayerSchedule
  /// The schedule's state at the last update.
  private(set) var state: ScheduleState
  /// The listed day at the last update: the owning day that is today's date in the
  /// location's zone, or why the schedule can't give it.
  private(set) var day: PrayerDayAvailability
  /// The last listed day the schedule could give. While today's isn't available the
  /// dropdown shows it marked as last known, never as today's.
  private(set) var lastKnownDay: PrayerDayAvailability?
  var statusBarText: String = ""

  let preferences = Preferences.shared
  let locationManager = LocationManager()
  let reachability = ReachabilityMonitor()
  let audioPlaybackController: AudioPlaybackController

  private let alerts: PrayerAlertCoordinator
  private let mirror: WidgetMirror
  /// The widget's Stop button. Kept for the app's lifetime: releasing it stops delivery.
  private var stopObservation: DarwinSignal.Observation?
  private var timer: Timer?
  /// A lightweight 1-second timer that refreshes ONLY the menu-bar text while it
  /// shows a sub-minute value (the last minute before a prayer, the first minute
  /// of a count-up). It never touches alerts or the widget - those stay on the
  /// aligned 60-second `timer` - and it stops itself once the value is no longer
  /// sub-minute, so the per-second cadence lasts only the ~60s it matters.
  private var secondTimer: Timer?
  private var notificationObservers: [NSObjectProtocol] = []
  private var currentDay: CivilDay
  /// Why today's times aren't available, as last logged.
  private var reportedUnavailable: UnavailableCause?

  init(audioPlaybackController: AudioPlaybackController = AudioPlaybackController()) {
    self.audioPlaybackController = audioPlaybackController
    #if DEBUG
      let center = DebugOptions.notificationCenter() ?? UNUserNotificationCenter.current()
    #else
      let center = UNUserNotificationCenter.current()
    #endif
    alerts = PrayerAlertCoordinator(center: center, audio: audioPlaybackController)
    mirror = WidgetMirror()

    let settings = Preferences.shared.mirroredSettings
    let schedule = settings.schedule
    let now = Date()
    self.settings = settings
    self.schedule = schedule
    day = schedule.day(containing: now)
    state = schedule.state(
      at: now, through: now.addingTimeInterval(SalahDisplay.lookahead), policy: SalahDisplay.policy)
    currentDay = CivilDay(containing: now, in: settings.location.timeZone)

    calculatePrayerTimes()
    // The mirror holds the settings from launch on; nothing plays yet. The explicit
    // reload gives a widget whose timeline ran out ("Open Salah to update") a new one.
    mirror.start(preferences: preferences)
    mirror.publish(playback: currentPlayback)
    mirror.reloadWidgets()
    startTimer()
    observeNotifications()

    stopObservation = DarwinSignal.stopAudio.observe { [weak self] in
      self?.stopFromWidget()
    }

    // When the network returns, re-run any pending reverse-geocode so a stale
    // city label (from a failed geocode while offline) self-heals. Prayer times
    // are unaffected either way - they come from stored coordinates.
    reachability.onBecameSatisfied = { [weak self] in
      self?.locationManager.retryPendingGeocodeOnReconnect()
    }
    reachability.start()

    if preferences.useCurrentLocation {
      locationManager.startUpdating()
    }
  }

  // MARK: - Timer

  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.handleTick()
      }
    }
    timer?.tolerance = 5
    alignTimerToNextMinute()
    refreshSecondTimer()
  }

  private func handleTick() {
    if CivilDay(containing: Date(), in: settings.location.timeZone) != currentDay {
      calculatePrayerTimes()
    } else {
      updateCurrentPrayer()
    }
    // A safety net under the engine's own wake-ups, as the old scheduler's minute
    // check was; an alert already reported isn't reported again.
    alerts.resync()
    alignTimerToNextMinute()
    refreshSecondTimer()
  }

  private func alignTimerToNextMinute() {
    let currentSecond = Date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
    let delta = max(0.5, 60.5 - currentSecond)
    timer?.fireDate = Date().addingTimeInterval(delta)
  }

  /// True while the menu-bar status shows a sub-minute value - the last minute
  /// before the next prayer, or the first minute of a count-up - so the seconds
  /// ("45s") need a per-second refresh. False unless the menu bar is showing a
  /// "time until" countdown at all (clock-time / hidden never tick).
  private var needsSecondTick: Bool {
    guard preferences.displayNextPrayer,
      preferences.nextPrayerDisplayType == .timeUntil
    else { return false }
    let now = Date()
    if let countUp = menuBarCountUp, now.timeIntervalSince(countUp.time) < 60 { return true }
    guard let next = state.prayerState?.next, next.kind != .sunrise else { return false }
    let delta = next.time.timeIntervalSince(now)
    return delta > 0 && delta <= 60
  }

  /// Starts or stops the 1-second menu-bar refresh based on `needsSecondTick`.
  /// Driven from each minute tick (and launch). The block refreshes only the
  /// status text and self-invalidates the moment the window closes, so a tinted
  /// label re-rasterizes per second only during that bounded ~60s.
  private func refreshSecondTimer() {
    guard needsSecondTick else {
      secondTimer?.invalidate()
      secondTimer = nil
      return
    }
    guard secondTimer == nil else { return }
    let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.updateStatusBarText()
        if !self.needsSecondTick {
          self.secondTimer?.invalidate()
          self.secondTimer = nil
        }
      }
    }
    tick.tolerance = 0.15
    RunLoop.main.add(tick, forMode: .common)
    secondTimer = tick
  }

  // MARK: - Notifications

  private func observeNotifications() {
    let nc = NotificationCenter.default
    notificationObservers.append(
      nc.addObserver(forName: .locationDidUpdate, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          FailureReporter.shared.clearNotice(.location)
          self?.calculatePrayerTimes()
        }
      })
    notificationObservers.append(
      nc.addObserver(forName: .locationDidFail, object: nil, queue: .main) { note in
        let failure = note.object as? LocationFailure ?? .unavailable
        Task { @MainActor in
          // Routes by the app-wide policy: transient/background stays silent and
          // self-heals; terminal (denied/restricted) surfaces non-modally via the
          // menu-bar badge, the popover, and the Location settings tab.
          FailureReporter.shared.report(failure, waiting: false, domain: .location)
        }
      })
    notificationObservers.append(
      nc.addObserver(forName: .salahPreferencesDidChange, object: nil, queue: .main) {
        [weak self] note in
        let raw = note.userInfo?[PreferenceRefresh.userInfoKey] as? Int ?? 0
        Task { @MainActor in
          self?.applyPreferenceRefresh(PreferenceRefresh(rawValue: raw))
        }
      })
    notificationObservers.append(
      // Scope to this manager's own audio controller so previewing a sound in
      // Settings (a separate controller) never reaches the widget.
      nc.addObserver(
        forName: .salahAudioPlaybackStateDidChange, object: audioPlaybackController,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          guard let self else { return }
          self.mirror.publish(playback: self.currentPlayback)
        }
      })
    notificationObservers.append(
      nc.addObserver(forName: .startLocationUpdate, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          self?.locationManager.startUpdating()
        }
      })
    notificationObservers.append(
      nc.addObserver(forName: .stopLocationUpdate, object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor in
          self?.locationManager.stopUpdating()
        }
      })
    // A clock or time-zone change, becoming active and waking from sleep can each
    // skip past an alert: everything is replanned, then the engine catches up.
    for name in [
      NSNotification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange,
      NSApplication.willBecomeActiveNotification,
    ] {
      notificationObservers.append(
        nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          Task { @MainActor in
            self?.refreshAfterPossibleMissedAlert()
          }
        })
    }
    notificationObservers.append(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.refreshAfterPossibleMissedAlert()
        }
      })
    // Quitting stops the sound: tell the widget at once, before the process ends, or it
    // keeps showing the Stop control. Synchronous, since a task wouldn't run in time.
    notificationObservers.append(
      nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          self?.audioPlaybackController.stop()
          self?.mirror.publish(playback: nil)
        }
      })
  }

  /// Replans from the new time, then catches up on alerts a clock change or sleep
  /// skipped, and gives the widget a new timeline: one that ran out while the Mac slept
  /// shows "Open Salah to update", and opening Salah lands here.
  func refreshAfterPossibleMissedAlert() {
    rebuildSchedule()
    alerts.catchUp(schedule: schedule)
    mirror.reloadWidgets()
  }

  private func applyNotificationRuntimePreferences() {
    let volume = Float(max(0, min(preferences.alertVolume, 100))) / 100.0
    audioPlaybackController.setVolume(volume)

    if preferences.silentMode {
      audioPlaybackController.stop()
      return
    }

    if !preferences.duaEnabled {
      audioPlaybackController.cancelFollowUp()

      if case .playing(let context) = audioPlaybackController.state,
        context.source == .dua
      {
        audioPlaybackController.stop()
      }
    }
  }

  /// The widget's Stop button: stop, then confirm the stopped state in the App Group,
  /// whatever the widget's own optimistic write left there.
  private func stopFromWidget() {
    let wasPlaying = audioPlaybackController.state != .idle
    AppLog.widgets.notice("stop signal received wasPlaying=\(wasPlaying, privacy: .public)")
    audioPlaybackController.stop()
    mirror.publish(playback: currentPlayback)
  }

  // MARK: - Calculation

  /// Rebuilds the schedule from the preferences, updates the state and the menu bar,
  /// and replans every alert.
  func calculatePrayerTimes() {
    rebuildSchedule()
    alerts.update(schedule: schedule)
  }

  /// The schedule, the state and the menu bar, from the preferences; not the alerts.
  private func rebuildSchedule() {
    settings = preferences.mirroredSettings
    schedule = settings.schedule
    currentDay = CivilDay(containing: Date(), in: settings.location.timeZone)
    updateCurrentPrayer()
  }

  private func updateCurrentPrayer() {
    let now = Date()
    day = schedule.day(containing: now)
    state = schedule.state(
      at: now, through: now.addingTimeInterval(SalahDisplay.lookahead), policy: SalahDisplay.policy)
    switch day {
    case .available:
      lastKnownDay = day
      reportedUnavailable = nil
      FailureReporter.shared.clearNotice(.prayerCalc)
    case .unavailable(let reason):
      // Not a time-out to wait on: the same coordinates give the same answer, so it's
      // surfaced once, non-modally, until the place changes. The minute's tick lands
      // here too: report only a new cause, or the same one again once no notice shows
      // (another one took its place and then cleared), never over another notice.
      let location = settings.location
      let cause = UnavailableCause(location: location, reason: reason)
      guard cause != reportedUnavailable || FailureReporter.shared.currentNotice == nil
      else { break }
      reportedUnavailable = cause
      AppLog.prayer.error(
        "No prayer times for (\(location.latitude, privacy: .private), \(location.longitude, privacy: .private)): \(reason.rawValue, privacy: .public)"
      )
      FailureReporter.shared.report(
        PrayerCalcFailure.timesUnavailable(
          latitude: location.latitude, longitude: location.longitude),
        waiting: false, domain: .prayerCalc)
    }
    updateStatusBarText()
  }

  /// What a surface shows at `now`: the current settings, the schedule's state then
  /// and what's playing.
  func display(at now: Date) -> SalahDisplay {
    SalahDisplay(date: now, settings: settings, schedule: schedule, playback: currentPlayback)
  }

  /// What the prayer-alert controller is playing, as the widget shows it.
  var currentPlayback: SalahPlayback? {
    SalahPlayback(audioPlaybackController.state)
  }

  // MARK: - Preference-driven refresh

  /// The single consumer of `.salahPreferencesDidChange` in the app (the widget
  /// mirror listens on its own). Each effect does the minimum work it needs, and the
  /// cheap effects are never gated behind the expensive ones - in particular the
  /// language re-geocode runs detached, so a slow / throttled / offline
  /// reverse-geocode can't stall the visible menu-bar refresh.
  private func applyPreferenceRefresh(_ effects: PreferenceRefresh) {
    if effects.contains(.audioRuntime) {
      applyNotificationRuntimePreferences()
    }
    if effects.contains(.localization) {
      // The AppleLanguages override is applied in `Preferences`; here we only
      // refresh the geocoded city label in the new language. Detached so it
      // never blocks the refresh below. When it returns, the `city` didSet posts
      // its own `.display`, so the label updates on its own.
      let locale = preferences.appLanguage.locale
      Task { await self.locationManager.refreshGeocodedLabels(in: locale) }
    }
    if effects.contains(.prayerTimes) {
      calculatePrayerTimes()
    } else if !effects.isDisjoint(with: [.display, .localization]) {
      refreshDisplayOnly(languageChanged: effects.contains(.localization))
    }
  }

  /// Refreshes the menu bar for a display-only change (menu-bar format, location
  /// label, Hijri offset, widget theme, language). The Hijri offset also moves
  /// Ramadan's delayed Isha, and the language the alerts' wording, so either replans.
  private func refreshDisplayOnly(languageChanged: Bool) {
    let updated = preferences.mirroredSettings
    if updated.calculation != settings.calculation || updated.location != settings.location {
      calculatePrayerTimes()
      return
    }
    settings = updated
    if languageChanged {
      alerts.update(schedule: schedule)
    }
    updateStatusBarText()
  }

  // MARK: - Status Bar

  private func updateStatusBarText() {
    guard preferences.displayNextPrayer else {
      statusBarText = ""
      return
    }

    let now = Date()
    let names = PrayerNames(locale: .app)

    // Iqama count-up: for 15 minutes after a prayer starts, lead with that prayer's
    // elapsed time ("Dhuhr +12m") before handing back to the next prayer's
    // countdown - matching the widgets. Countdown style only; Sunrise excluded (see
    // `menuBarCountUp`).
    if let countUp = menuBarCountUp {
      let name = nameComponent(for: countUp, names: names)
      let elapsed = displayFormatter.countUp(from: countUp.time, to: now)
      statusBarText = joinStatus(name, elapsed)
      return
    }

    // The schedule doesn't know what comes next (a time the calculation can't give
    // here today): say so rather than invent one.
    guard let next = state.prayerState?.next else {
      statusBarText = "–"
      return
    }

    let name = nameComponent(for: next, names: names)
    let timeComponent: String = {
      switch preferences.nextPrayerDisplayType {
      case .timeUntil:
        return displayFormatter.countdown(from: now, to: next.time)
      case .timeOfPrayer:
        return displayFormatter.compactTime(for: next.time)
      case .none:
        return ""
      }
    }()

    statusBarText = joinStatus(name, timeComponent)
  }

  private func nameComponent(for event: PrayerEvent, names: PrayerNames) -> String {
    switch preferences.nextPrayerDisplayName {
    case .full: return names.name(of: event)
    case .abbreviation: return names.abbreviation(of: event)
    case .none: return ""
    }
  }

  private func joinStatus(_ name: String, _ time: String) -> String {
    if name.isEmpty && time.isEmpty { return "" }
    if name.isEmpty { return time }
    if time.isEmpty { return name }
    return "\(name) \(time)"
  }

  // MARK: - Formatting

  func formattedTime(for date: Date) -> String {
    displayFormatter.fullTime(for: date)
  }

  private var displayFormatter: PrayerDisplayFormatter {
    PrayerDisplayFormatter(timeZone: settings.location.timeZone)
  }
}

enum MenuBarStatusTone {
  case normal
  case imminent
  case playingPreReminderAudio
  case playingPrayerAudio
  case playingPostReminderAudio
}

extension PrayerManager {
  var menuBarStatusTone: MenuBarStatusTone {
    if case .playing(let context) = audioPlaybackController.state {
      switch context.slot {
      case .preReminder:
        return .playingPreReminderAudio
      case .alert:
        return .playingPrayerAudio
      case .postReminder:
        return .playingPostReminderAudio
      case nil:
        return .playingPrayerAudio
      }
    }

    // Iqama count-up window: green, reusing the playing-adhan tone so the menu
    // bar matches the widget. Countdown style only (see `menuBarCountUp`).
    if menuBarCountUp != nil { return .playingPrayerAudio }

    // Imminent red in the 15 min before the next prayer - never before Sunrise,
    // which is not one.
    return state.prayerState?.isApproaching == true ? .imminent : .normal
  }

  /// The prayer that just started, leading the 15-minute count-up, or nil. Countdown
  /// style only (clock-time style is unaffected); Sunrise is never one, since it isn't
  /// a prayer.
  var menuBarCountUp: PrayerEvent? {
    guard preferences.nextPrayerDisplayType == .timeUntil else { return nil }
    return state.prayerState?.justStarted
  }
}

/// Where and why the schedule couldn't give today: one log line and notice per cause.
private struct UnavailableCause: Equatable {
  var location: PrayerLocation
  var reason: ScheduleGapReason
}
