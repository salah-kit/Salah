import Foundation
import SalahAlerts
import SalahCore
import SalahUI
import SalahWidgets
import Testing

@Suite("The adhan while Salah is open on the watch", .serialized)
@MainActor
struct WatchAdhanTests {
  private func coordinator(at text: String, defaults: UserDefaults = WatchFixtures.defaults())
    -> (WatchAdhanCoordinator, ManualAlertClock)
  {
    let clock = ManualAlertClock(now: WatchFixtures.date(text))
    return (WatchAdhanCoordinator(clock: clock, defaults: defaults), clock)
  }

  @Test func plansEachPrayerWithASoundAndNotSunrise() {
    let (adhan, _) = coordinator(at: "2026-10-12T12:19:00Z")
    let preferences = WatchFixtures.preferences()
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    let alerts = adhan.schedule?.alerts ?? []
    #expect(alerts.first?.event.kind == .asr)
    #expect(alerts.allSatisfy { $0.kind == .atTime })
    #expect(!alerts.contains { $0.event.kind == .sunrise })
  }

  @Test func followsTheIPhonesAlertsAndMute() {
    let (adhan, _) = coordinator(at: "2026-10-12T12:19:00Z")
    var preferences = WatchFixtures.preferences()
    preferences.notifications[.maghrib]?.atTime = false
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    let kinds = Set((adhan.schedule?.alerts ?? []).map(\.event.kind))
    #expect(!kinds.contains(.maghrib))
    #expect(kinds.contains(.isha))

    preferences.muteSounds = true
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    #expect(adhan.schedule?.alerts.isEmpty == true)
  }

  /// A system sound or an imported recording on the iPhone plays the tone on the watch.
  @Test func playsWhatTheWatchHas() {
    var preferences = WatchFixtures.preferences()
    preferences.notifications[.asr]?.sound = .custom("recording.m4a")
    preferences.notifications[.isha]?.sound = .system
    #expect(preferences.watchSound(for: .asr) == .softTone)
    #expect(preferences.watchSound(for: .isha) == .softTone)
    #expect(preferences.watchSound(for: .fajr) == .fajrAdhan)
    #expect(preferences.watchSound(for: .sunrise) == .none)
  }

  @Test func reportsAnAdhanOnceWhenItComesDue() {
    let (adhan, clock) = coordinator(at: "2026-10-12T17:13:50Z")
    var due: [PrayerEvent] = []
    adhan.onDue = { due.append($0) }
    let preferences = WatchFixtures.preferences()
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    #expect(due.isEmpty)
    clock.advance(to: WatchFixtures.date("2026-10-12T17:14:00.2Z"))
    #expect(due.map(\.kind) == [.maghrib])
    adhan.resync()
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    #expect(due.map(\.kind) == [.maghrib])
  }

  /// Coming back to Salah within five minutes of a prayer plays it once; a relaunch after it
  /// played doesn't play it again.
  @Test func catchesUpOnceAcrossRelaunches() {
    let defaults = WatchFixtures.defaults()
    let preferences = WatchFixtures.preferences()
    var due: [PrayerEvent] = []
    let (first, _) = coordinator(at: "2026-10-12T17:16:00Z", defaults: defaults)
    first.onDue = { due.append($0) }
    first.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    first.resync()
    #expect(due.map(\.kind) == [.maghrib])
    let (relaunched, _) = coordinator(at: "2026-10-12T17:17:00Z", defaults: defaults)
    relaunched.onDue = { due.append($0) }
    relaunched.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    relaunched.resync()
    #expect(due.map(\.kind) == [.maghrib])
  }

  /// Preferences that arrive after a prayer began don't start its adhan.
  @Test func preferencesFromTheIPhoneDontStartABegunPrayer() {
    let (adhan, _) = coordinator(at: "2026-10-12T17:16:00Z")
    var due: [PrayerEvent] = []
    adhan.onDue = { due.append($0) }
    let preferences = WatchFixtures.preferences()
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: false)
    adhan.resync()
    #expect(due.isEmpty)
  }
}

@Suite("The watch app's composition", .serialized)
@MainActor
struct WatchRuntimeTests {
  init() { WatchTestResources.use() }

  private func runtime(
    _ preferences: IOSPreferences?, at text: String, reloads: RecordingReloads = .init(),
    value: SharedValue<SalahSettings>? = nil
  ) -> WatchAppRuntime {
    let configuration = WatchLaunchConfiguration(
      repository: WatchFixtures.repository(preferences),
      clock: WatchClock(start: WatchFixtures.date(text), frozen: true))
    return WatchAppRuntime(
      configuration: configuration,
      receiver: WatchPreferencesReceiver(session: nil, defaults: WatchFixtures.defaults()),
      complications: WatchComplicationPublisher(value: value ?? reloads.value()),
      notificationCenter: nil)
  }

  @Test func waitsForTheIPhoneOnAFreshInstall() {
    let reloads = RecordingReloads()
    let runtime = runtime(nil, at: "2026-10-12T12:19:00Z", reloads: reloads)
    #expect(runtime.store.display == nil)
    #expect(reloads.reloads.isEmpty)
  }

  @Test func preferencesFromTheIPhoneReachTheScreensAndTheComplications() {
    let reloads = RecordingReloads()
    let value = reloads.value()
    let runtime = runtime(nil, at: "2026-10-12T12:19:00Z", reloads: reloads, value: value)
    runtime.activate()
    runtime.receiver.receive(
      WatchFixtures.context(WatchFixtures.preferences(), sentAt: "2026-10-12T12:00:00Z"))
    #expect(runtime.store.display?.focus?.event.kind == .asr)
    #expect(value.load()?.location.name == "London")
    #expect(reloads.reloads == [[WatchComplicationKind.prayer]])
    // The same preferences again change nothing and reload nothing.
    runtime.receiver.receive(
      WatchFixtures.context(WatchFixtures.preferences(), sentAt: "2026-10-12T12:05:00Z"))
    #expect(reloads.reloads.count == 1)
  }

  @Test func aDueAdhanPlaysOnTheFirstPage() throws {
    let runtime = runtime(WatchFixtures.preferences(), at: "2026-10-12T17:14:00Z")
    runtime.activate()
    runtime.navigation.tab = .qibla
    let maghrib = try #require(
      runtime.store.display?.listedDay?.events.first { $0.kind == .maghrib })
    runtime.adhan.onDue?(maghrib)
    #expect(runtime.store.playback?.event == maghrib)
    #expect(runtime.audio.isPlaying)
    #expect(runtime.navigation.tab == .now)
    runtime.stopAdhan()
    #expect(runtime.store.playback == nil)
    #expect(!runtime.audio.isPlaying)
  }

  @Test func leavingSalahStopsTheAdhanAndPlansNothing() throws {
    let runtime = runtime(WatchFixtures.preferences(), at: "2026-10-12T17:14:00Z")
    runtime.activate()
    let maghrib = try #require(
      runtime.store.display?.listedDay?.events.first { $0.kind == .maghrib })
    runtime.adhan.onDue?(maghrib)
    runtime.deactivate()
    #expect(!runtime.audio.isPlaying)
    #expect(runtime.store.playback == nil)
    #expect(runtime.adhan.schedule?.alerts.isEmpty == true)
    // Nothing plays while Salah is away, even if the engine reported a prayer.
    runtime.adhan.onDue?(maghrib)
    #expect(!runtime.audio.isPlaying)
  }

  @Test func muteFromTheIPhoneStopsTheAdhan() throws {
    let runtime = runtime(WatchFixtures.preferences(), at: "2026-10-12T17:14:00Z")
    runtime.activate()
    let maghrib = try #require(
      runtime.store.display?.listedDay?.events.first { $0.kind == .maghrib })
    runtime.adhan.onDue?(maghrib)
    runtime.receiver.receive(
      WatchFixtures.context(
        WatchFixtures.preferences { $0.muteSounds = true }, sentAt: "2026-10-12T17:14:10Z"))
    #expect(!runtime.audio.isPlaying)
    #expect(runtime.store.playback == nil)
  }

  @Test func complicationLinksOpenTheirPage() {
    let navigation = WatchNavigation()
    navigation.open(URL(string: "salah://qibla")!)
    #expect(navigation.tab == .qibla)
    navigation.open(URL(string: "salah://now")!)
    #expect(navigation.tab == .now)
    navigation.open(URL(string: "other://today")!)
    navigation.open(URL(string: "salah://settings")!)
    #expect(navigation.tab == .now)
  }
}
