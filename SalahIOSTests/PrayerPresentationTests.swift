import Foundation
import SalahCore
import SalahTimes
import Testing

@Suite("iOS prayer presentation") @MainActor
struct PrayerPresentationTests {
  @Test func heroClockKeepsSecondsAndCountUpDirectionInTheSelectedDigits() {
    let english = SalahText(locale: Locale(identifier: "en_GB"), timeZone: .gmt)
    #expect(IOSPrayerPresentation.clock(8_160, countingUp: false, text: english) == "2:16:00")
    #expect(IOSPrayerPresentation.clock(240, countingUp: true, text: english) == "+0:04:00")
    #expect(IOSPrayerPresentation.clock(-5, countingUp: false, text: english) == "0:00:00")
    #expect(IOSPrayerPresentation.clock(.infinity, countingUp: false, text: english) == "—")
    let arabic = SalahText(locale: Locale(identifier: "ar_SA"), timeZone: .gmt)
    #expect(IOSPrayerPresentation.clock(240, countingUp: true, text: arabic) == "+٠:٠٤:٠٠")
  }

  @Test func sunriseHasACountdownButNeverThePrayerApproachTreatment() throws {
    let settings = try Self.settings()
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let sunrise = try #require(settings.schedule.day(day).day?[.sunrise])
    let display = SalahDisplay(
      date: sunrise.time.addingTimeInterval(-5 * 60), settings: settings,
      schedule: settings.schedule)
    let presentation = IOSPrayerPresentation(display: display)
    #expect(presentation.event?.kind == .sunrise)
    #expect(!presentation.isApproaching)
    #expect(!presentation.isCountingUp)
    #expect(presentation.countdown == "0:05:00")
  }

  @Test func justStartedAndTomorrowUseTheSameScheduleSelectionAsWidgets() throws {
    let settings = try Self.settings()
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let events = try #require(settings.schedule.day(day).day)
    let dhuhr = try #require(events[.dhuhr])
    let current = IOSPrayerPresentation(
      display: SalahDisplay(
        date: dhuhr.time.addingTimeInterval(4 * 60), settings: settings, schedule: settings.schedule
      ))
    #expect(current.isCountingUp)
    #expect(current.eyebrow == "Now")
    #expect(current.countdown == "+0:04:00")
    #expect(current.detail(for: dhuhr) == "4 min ago")
    let isha = try #require(events[.isha])
    let tomorrow = IOSPrayerPresentation(
      display: SalahDisplay(
        date: isha.time.addingTimeInterval(16 * 60), settings: settings, schedule: settings.schedule
      ))
    #expect(tomorrow.event?.kind == .fajr)
    #expect(tomorrow.eyebrow == "Tomorrow")
    #expect(!tomorrow.isCountingUp)
  }

  @Test func polarMissingEventsNeverAcquireAFakeCountdownOrTime() throws {
    var preferences = IOSPreferences()
    preferences.location = PrayerLocation(
      latitude: 69.6492, longitude: 18.9553, timeZone: TimeZone(identifier: "Europe/Oslo")!,
      name: "Tromsø")
    preferences.language = .english
    preferences.method = .preset(.muslimWorldLeague)
    preferences.automaticHighLatitude = false
    preferences.highLatitudeRule = .disabled
    let settings = try #require(preferences.mirror)
    let day = CivilDay(year: 2026, month: 6, day: 21)
    let events = try #require(settings.schedule.day(day).day)
    let asr = try #require(events[.asr])
    let presentation = IOSPrayerPresentation(
      display: SalahDisplay(
        date: asr.time.addingTimeInterval(16 * 60), settings: settings, schedule: settings.schedule)
    )
    #expect(presentation.missing[.maghrib] == .calculationUnavailable)
    #expect(presentation.missing[.isha] == .calculationUnavailable)
    #expect(presentation.event == nil)
    #expect(presentation.countdown == "—")
    #expect(presentation.missingDetail(.calculationUnavailable) == "Can’t be calculated")
    #expect(presentation.hasCalculationGaps)
    #expect(presentation.unavailableExplanation == "Some prayer times can’t be calculated")
    #expect(presentation.display.slots.contains(.event(asr)))
  }

  @Test func turnInstructionsUseTheShortestArcAcrossNorth() {
    #expect(IOSQiblaPresentation.shortestTurn(from: 359, to: 1) == 2)
    #expect(IOSQiblaPresentation.shortestTurn(from: 1, to: 359) == -2)
    #expect(IOSQiblaPresentation.shortestTurn(from: 93, to: 119) == 26)
    #expect(IOSQiblaPresentation.shortestTurn(from: 145, to: 119) == -26)
    #expect(abs(IOSQiblaPresentation.shortestTurn(from: 0, to: 180)) == 180)
  }

  @Test func reminderCopyComesFromTheEnabledSlotsAndPlayingSlot() throws {
    var settings = try Self.settings()
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let asr = try #require(settings.schedule.day(day).day?[.asr])
    let now = asr.time.addingTimeInterval(-3_600)
    let disabled = IOSPrayerPresentation(
      display: SalahDisplay(date: now, settings: settings, schedule: settings.schedule))
    #expect(disabled.footer == nil)
    settings.alerts[.asr] = PrayerAlerts(alert: true, beforeMinutes: 10, afterMinutes: 5)
    let enabled = IOSPrayerPresentation(
      display: SalahDisplay(date: now, settings: settings, schedule: settings.schedule))
    #expect(enabled.footer == "Reminder 10 min before · 5 min after")
    let reminder = IOSPrayerPresentation(
      display: SalahDisplay(
        date: now, settings: settings, schedule: settings.schedule,
        playback: SalahPlayback(event: asr, slot: .preReminder, offsetMinutes: 10)))
    #expect(reminder.subtitle == "10 min before")
  }

  @Test func manuallyPlayingAPastPrayerNeverChangesItsScheduleStatusToNow() throws {
    let settings = try Self.settings()
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let events = try #require(settings.schedule.day(day).day)
    let fajr = try #require(events[.fajr])
    let asr = try #require(events[.asr])
    let presentation = IOSPrayerPresentation(
      display: SalahDisplay(
        date: asr.time.addingTimeInterval(-3_600), settings: settings, schedule: settings.schedule,
        playback: SalahPlayback(event: fajr, slot: .alert)))
    #expect(presentation.event?.id == fajr.id)
    #expect(presentation.rowStatus(for: fajr) == .passed)
    #expect(presentation.rowStatus(for: asr) == .next(approaching: false))
    #expect(!presentation.isCountingUp)
  }

  @Test func playbackFooterRequiresAnActuallyQueuedDua() throws {
    let settings = try Self.settings()
    let day = CivilDay(year: 2026, month: 6, day: 2)
    let events = try #require(settings.schedule.day(day).day)
    let fajr = try #require(events[.fajr])
    let sunrise = try #require(events[.sunrise])
    func presentation(_ playback: SalahPlayback) -> IOSPrayerPresentation {
      IOSPrayerPresentation(
        display: SalahDisplay(
          date: playback.event.time, settings: settings, schedule: settings.schedule,
          playback: playback))
    }
    let adhan = presentation(SalahPlayback(event: fajr, slot: .alert))
    #expect(adhan.playbackFooter(hasQueuedDua: false) == nil)
    #expect(adhan.playbackFooter(hasQueuedDua: true) == "The du’ā’ after the adhan follows")
    #expect(
      presentation(SalahPlayback(event: sunrise, slot: .alert)).playbackFooter(hasQueuedDua: false)
        == nil)
    #expect(
      presentation(SalahPlayback(event: fajr, slot: .preReminder)).playbackFooter(
        hasQueuedDua: true) == nil)
    #expect(
      presentation(SalahPlayback(event: fajr, slot: .alert, isDua: true)).playbackFooter(
        hasQueuedDua: true) == nil)
  }

  private static func settings() throws -> SalahSettings {
    var preferences = IOSPreferences()
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: TimeZone(identifier: "Asia/Riyadh")!,
      name: "Makkah")
    preferences.method = .preset(.ummAlQura)
    preferences.language = .english
    return try #require(preferences.mirror)
  }
}
