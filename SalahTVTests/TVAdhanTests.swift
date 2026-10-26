import Foundation
import SalahAlerts
import SalahCore
import SalahWidgets
import Testing

@Suite("The adhan while Salah is open", .serialized)
@MainActor
struct TVAdhanTests {
  private func coordinator(
    at text: String, defaults: UserDefaults = TVFixtures.defaults()
  ) -> (TVAdhanCoordinator, ManualAlertClock) {
    let clock = ManualAlertClock(now: TVFixtures.date(text))
    return (TVAdhanCoordinator(clock: clock, defaults: defaults), clock)
  }

  @Test func plansEachPrayerAtItsTimeAndNotSunrise() {
    let (adhan, _) = coordinator(at: "2026-06-02T13:19:00+03:00")
    let preferences = TVFixtures.preferences()
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    let alerts = adhan.schedule?.alerts ?? []
    #expect(!alerts.isEmpty)
    #expect(alerts.allSatisfy { $0.kind == .atTime })
    #expect(!alerts.contains { $0.event.kind == .sunrise })
    // Asr is the first alert after 1:19 PM; Dhuhr at 12:19 is outside the catch-up window.
    #expect(alerts.first?.event.kind == .asr)
  }

  @Test func plansNothingWhileMuted() {
    let (adhan, _) = coordinator(at: "2026-06-02T13:19:00+03:00")
    let preferences = TVFixtures.preferences { $0.muteSounds = true }
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    #expect(adhan.schedule?.alerts.isEmpty == true)
  }

  @Test func aPrayerTurnedOffIsntPlanned() {
    let (adhan, _) = coordinator(at: "2026-06-02T13:19:00+03:00")
    let preferences = TVFixtures.preferences { $0.setTVSound(.none, for: .maghrib) }
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    let kinds = Set((adhan.schedule?.alerts ?? []).map(\.event.kind))
    #expect(!kinds.contains(.maghrib))
    #expect(kinds.contains(.isha))
  }

  @Test func reportsAnAdhanOnceWhenItComesDue() {
    let (adhan, clock) = coordinator(at: "2026-06-02T18:59:50+03:00")
    var due: [PrayerEvent] = []
    adhan.onDue = { due.append($0) }
    let preferences = TVFixtures.preferences()
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    #expect(due.isEmpty)
    let maghrib = TVFixtures.date("2026-06-02T19:00:00+03:00")
    #expect(clock.wakeDate.map { abs($0.timeIntervalSince(maghrib)) < 1 } == true)
    clock.advance(to: maghrib.addingTimeInterval(0.2))
    #expect(due.map(\.kind) == [.maghrib])
    adhan.resync()
    #expect(due.count == 1)
  }

  @Test func catchesUpAnAdhanMissedByAFewMinutes() {
    let (adhan, _) = coordinator(at: "2026-06-02T19:03:00+03:00")
    var due: [PrayerEvent] = []
    adhan.onDue = { due.append($0) }
    let preferences = TVFixtures.preferences()
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    #expect(due.map(\.kind) == [.maghrib])
  }

  @Test func fridayDhuhrFollowsTheJumuahOverride() {
    // Friday 16 October 2026 in Jakarta.
    let (adhan, _) = coordinator(at: "2026-10-16T10:05:00+07:00")
    let preferences = TVFixtures.preferences(TVFixtures.jakarta) {
      $0.jumuahOverrideEnabled = true
      $0.jumuahOverrideSeeded = true
      $0.jumuahAlerts.atTime = false
    }
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    let alerts = adhan.schedule?.alerts ?? []
    let fridayDhuhr = alerts.filter {
      $0.event.kind == .dhuhr && $0.event.scheduleDay == CivilDay(year: 2026, month: 10, day: 16)
    }
    #expect(fridayDhuhr.isEmpty)
    #expect(
      alerts.contains {
        $0.event.kind == .dhuhr && $0.event.scheduleDay == CivilDay(year: 2026, month: 10, day: 17)
      })
  }

  @Test func aSettingsChangeDoesntPlayAPrayerThatHasBegun() {
    let (adhan, _) = coordinator(at: "2026-06-02T19:02:00+03:00")
    var due: [PrayerEvent] = []
    adhan.onDue = { due.append($0) }
    let off = TVFixtures.preferences { $0.setTVSound(.none, for: .maghrib) }
    adhan.update(schedule: off.mirror?.schedule, preferences: off, catchingUp: true)
    let on = TVFixtures.preferences()
    adhan.update(schedule: on.mirror?.schedule, preferences: on, catchingUp: false)
    #expect(due.isEmpty)
    // Passed over, it stays quiet when Salah comes back inside the window.
    adhan.update(schedule: on.mirror?.schedule, preferences: on, catchingUp: true)
    #expect(due.isEmpty)
    #expect((adhan.schedule?.alerts ?? []).first?.event.kind == .isha)
  }

  @Test func aSettingsChangeKeepsAnAdhanAlreadyPlannedThatIsDue() {
    let (adhan, clock) = coordinator(at: "2026-06-02T18:59:50+03:00")
    var due: [PrayerEvent] = []
    adhan.onDue = { due.append($0) }
    let preferences = TVFixtures.preferences()
    adhan.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    // Maghrib has begun, but its wake-up hasn't fired yet.
    clock.now = TVFixtures.date("2026-06-02T19:00:05+03:00")
    let quieter = TVFixtures.preferences { $0.playbackVolume = 0.5 }
    adhan.update(schedule: quieter.mirror?.schedule, preferences: quieter, catchingUp: false)
    #expect(due.map(\.kind) == [.maghrib])
  }

  @Test func aRelaunchDoesntRepeatAnAdhanItReported() {
    let defaults = TVFixtures.defaults()
    let (first, clock) = coordinator(at: "2026-06-02T18:59:50+03:00", defaults: defaults)
    var due: [PrayerEvent] = []
    first.onDue = { due.append($0) }
    let preferences = TVFixtures.preferences()
    first.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    clock.advance(to: TVFixtures.date("2026-06-02T19:00:00+03:00").addingTimeInterval(0.2))
    #expect(due.map(\.kind) == [.maghrib])
    let (relaunched, _) = coordinator(at: "2026-06-02T19:02:00+03:00", defaults: defaults)
    relaunched.onDue = { due.append($0) }
    relaunched.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    #expect(due.count == 1)
    // Without the record, the same moment catches it up.
    let (fresh, _) = coordinator(at: "2026-06-02T19:02:00+03:00")
    fresh.onDue = { due.append($0) }
    fresh.update(
      schedule: preferences.mirror?.schedule, preferences: preferences, catchingUp: true)
    #expect(due.map(\.kind) == [.maghrib, .maghrib])
  }

  // MARK: - The runtime

  private func runtime(
    _ preferences: IOSPreferences, at text: String, idleTimer: RecordingIdleTimer = .init(),
    defaults: UserDefaults = TVFixtures.defaults(),
    reloads: @escaping @MainActor () -> Void = {}
  ) -> TVAppRuntime {
    TVTestResources.use()
    let configuration = TVLaunchConfiguration(
      repository: TVFixtures.repository(preferences), defaults: defaults,
      clock: TVClock(start: TVFixtures.date(text), frozen: true))
    let suite = "io.github.salah-kit.Salah.tvOS.unit." + UUID().uuidString
    return TVAppRuntime(
      configuration: configuration, idleTimer: idleTimer,
      topShelf: TVTopShelfPublisher(
        settings: SharedValue(appGroup: suite, key: "settings"), reload: reloads))
  }

  @Test func aDueAdhanPlaysAndTakesTheScreen() {
    let runtime = runtime(TVFixtures.preferences(), at: "2026-06-02T19:00:00+03:00")
    let maghrib = runtime.store.display!.listedDay!.events.first { $0.kind == .maghrib }!
    runtime.adhan.onDue?(maghrib)
    #expect(runtime.navigation.fullScreen == .adhan(maghrib))
    #expect(runtime.store.playback?.event == maghrib)
    #expect(runtime.audio.isPlaying)
    runtime.stopAdhan()
    #expect(runtime.navigation.fullScreen == nil)
    #expect(runtime.store.playback == nil)
    #expect(!runtime.audio.isPlaying)
  }

  @Test func aMutedAppleTVPlaysNothing() {
    let runtime = runtime(
      TVFixtures.preferences { $0.muteSounds = true }, at: "2026-06-02T19:00:00+03:00")
    let maghrib = runtime.store.display!.listedDay!.events.first { $0.kind == .maghrib }!
    runtime.adhan.onDue?(maghrib)
    #expect(runtime.navigation.fullScreen == nil)
    #expect(!runtime.audio.isPlaying)
  }

  @Test func leavingSalahStopsTheAdhan() {
    let runtime = runtime(TVFixtures.preferences(), at: "2026-06-02T19:00:00+03:00")
    let maghrib = runtime.store.display!.listedDay!.events.first { $0.kind == .maghrib }!
    runtime.adhan.onDue?(maghrib)
    runtime.deactivate()
    #expect(!runtime.audio.isPlaying)
    #expect(runtime.navigation.fullScreen == nil)
  }

  @Test func theRoomDisplayKeepsTheScreenOnOnlyWhileOpen() {
    let idleTimer = RecordingIdleTimer()
    let runtime = runtime(
      TVFixtures.preferences(), at: "2026-06-02T13:19:00+03:00", idleTimer: idleTimer)
    runtime.activate()
    runtime.navigation.showRoomDisplay()
    runtime.roomDisplayAppeared()
    #expect(idleTimer.keepsScreenOn)
    runtime.navigation.dismissFullScreen()
    runtime.roomDisplayDisappeared()
    #expect(!idleTimer.keepsScreenOn)
    runtime.navigation.showRoomDisplay()
    runtime.roomDisplayAppeared()
    runtime.deactivate()
    #expect(idleTimer.changes == [true, false, true, false])
  }

  @Test func theAdhanOverTheRoomDisplayKeepsTheScreenOn() throws {
    let idleTimer = RecordingIdleTimer()
    let runtime = runtime(
      TVFixtures.preferences(), at: "2026-06-02T18:59:00+03:00", idleTimer: idleTimer)
    runtime.activate()
    runtime.navigation.showRoomDisplay()
    runtime.roomDisplayAppeared()
    let maghrib = try #require(
      runtime.store.display?.listedDay?.events.first { $0.kind == .maghrib })
    runtime.adhan.onDue?(maghrib)
    // The adhan's screen replaces the room display's, which disappears under it.
    runtime.roomDisplayDisappeared()
    #expect(runtime.navigation.fullScreen == .adhan(maghrib))
    #expect(idleTimer.keepsScreenOn)
    runtime.stopAdhan()
    runtime.roomDisplayAppeared()
    #expect(runtime.navigation.fullScreen == .roomDisplay)
    #expect(idleTimer.changes == [true])
  }

  @Test func theRoomDisplayKeepsTheScreenOnWhenSalahComesBack() {
    let idleTimer = RecordingIdleTimer()
    let runtime = runtime(
      TVFixtures.preferences(), at: "2026-06-02T13:19:00+03:00", idleTimer: idleTimer)
    runtime.activate()
    runtime.navigation.showRoomDisplay()
    runtime.roomDisplayAppeared()
    runtime.deactivate()
    #expect(!idleTimer.keepsScreenOn)
    runtime.activate()
    #expect(runtime.keepsScreenOn)
    #expect(idleTimer.keepsScreenOn)
  }

  @Test func stoppingAPreviewLeavesTheAdhanPlaying() throws {
    let runtime = runtime(TVFixtures.preferences(), at: "2026-06-02T19:00:30+03:00")
    runtime.activate()
    let maghrib = try #require(runtime.store.playback?.event)
    #expect(maghrib.kind == .maghrib)
    runtime.stopSound()
    #expect(runtime.audio.isPlaying)
    #expect(runtime.navigation.fullScreen == .adhan(maghrib))
    runtime.stopAdhan()
    runtime.preview(.softTone)
    #expect(runtime.audio.isPlaying)
    runtime.stopSound()
    #expect(!runtime.audio.isPlaying)
  }

  @Test func choosingASoundAsTheAdhanComesDueLeavesTheAdhan() throws {
    let runtime = runtime(TVFixtures.preferences(), at: "2026-06-02T19:00:30+03:00")
    runtime.activate()
    let maghrib = try #require(runtime.store.playback?.event)
    // The sound page previews the sound it chose, just after the adhan began.
    runtime.preview(.softTone)
    #expect(runtime.audio.isPlaying)
    #expect(runtime.store.playback?.event == maghrib)
    #expect(runtime.navigation.fullScreen == .adhan(maghrib))
  }

  @Test func turningAPrayerOnAfterItBeganDoesntPlayIt() {
    let runtime = runtime(
      TVFixtures.preferences { $0.setTVSound(.none, for: .maghrib) },
      at: "2026-06-02T19:02:00+03:00")
    runtime.activate()
    runtime.store.updatePreferences { $0.setTVSound(.adhan, for: .maghrib) }
    #expect(!runtime.audio.isPlaying)
    #expect(runtime.store.playback == nil)
    #expect(runtime.navigation.fullScreen == nil)
  }

  @Test func activationCatchesUpAnAdhanThatBeganMinutesAgo() {
    let runtime = runtime(TVFixtures.preferences(), at: "2026-06-02T19:02:00+03:00")
    runtime.activate()
    #expect(runtime.store.playback?.event.kind == .maghrib)
    #expect(runtime.audio.isPlaying)
  }

  @Test func leavingSalahDisarmsTheAdhanAndComingBackDoesntRepeatIt() {
    let runtime = runtime(TVFixtures.preferences(), at: "2026-06-02T19:00:30+03:00")
    runtime.activate()
    #expect(runtime.audio.isPlaying)
    runtime.deactivate()
    #expect(runtime.adhan.schedule?.alerts.isEmpty == true)
    runtime.activate()
    #expect(!runtime.audio.isPlaying)
    #expect(runtime.navigation.fullScreen == nil)
    #expect(runtime.adhan.schedule?.alerts.first?.event.kind == .isha)
  }

  @Test func aRelaunchInsideTheWindowDoesntRepeatTheAdhan() {
    let defaults = TVFixtures.defaults()
    let first = runtime(
      TVFixtures.preferences(), at: "2026-06-02T19:00:30+03:00", defaults: defaults)
    first.activate()
    #expect(first.audio.isPlaying)
    first.deactivate()
    let relaunched = runtime(
      TVFixtures.preferences(), at: "2026-06-02T19:02:00+03:00", defaults: defaults)
    relaunched.activate()
    #expect(!relaunched.audio.isPlaying)
    #expect(relaunched.store.playback == nil)
  }

  @Test func preferenceChangesReplanAndRefreshTheTopShelf() {
    var reloads = 0
    let runtime = runtime(TVFixtures.preferences(), at: "2026-06-02T13:19:00+03:00") {
      reloads += 1
    }
    runtime.activate()
    #expect(reloads == 1)
    // The settings mirror has no volume, so the Top Shelf has nothing new to draw.
    runtime.store.updatePreferences { $0.playbackVolume = 0.5 }
    #expect(reloads == 1)
    runtime.store.updatePreferences { $0.setTVSound(.none, for: .asr) }
    #expect(!(runtime.adhan.schedule?.alerts ?? []).contains { $0.event.kind == .asr })
    runtime.store.updatePreferences { $0.language = .arabic }
    #expect(reloads == 3)
  }
}
