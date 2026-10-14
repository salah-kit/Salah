import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import SwiftUI
import Testing

/// A known prayer can play while missing later events make the schedule unavailable.
@Suite("Widget playback during schedule gaps")
struct WidgetPlaybackGapTests {
  init() { TestEnvironment.configure() }

  static func polarPlayback() throws -> SalahDisplay {
    var settings = WidgetTimelineTests.settings
    let zone = try #require(TimeZone(identifier: "Europe/Oslo"))
    settings.location = PrayerLocation(
      latitude: 69.6492, longitude: 18.9553, timeZone: zone, countryCode: "NO", name: "Tromsø")
    var parameters = CalculationMethod.muslimWorldLeague.parameters
    parameters.highLatitudeRule = .middleOfTheNight
    settings.calculation = CalculationSettings(parameters: parameters)
    let day = CivilDay(year: 2026, month: 12, day: 21)
    let dhuhr = try #require(settings.schedule.day(day).day?[.dhuhr])
    let playback = SalahPlayback(event: dhuhr, slot: .alert)
    let timeline = SalahWidgetTimeline.make(
      settings: settings, playback: playback, now: dhuhr.time.addingTimeInterval(60))
    let display = try #require(WidgetTimelineTests.displays(timeline).first?.1)
    try #require(display.prayerState == nil)
    try #require(display.playback == playback)
    try #require(display.playingTitle != nil && display.playingSubtitle != nil)
    return display
  }

  /// Compare the Stop face with the same display given a known state. A countdown's
  /// availability must not change what is rendered while audio plays.
  @Test(arguments: [SalahWidgetSize.small, .medium, .large])
  func activePlaybackRendersStopDuringAPolarGap(size: SalahWidgetSize) throws {
    let polar = try Self.polarPlayback()
    var known = polar
    known.state = WidgetPreviewData.idle(now: polar.date).state
    try #require(known.prayerState != nil)
    let actual = try BaselineRenderer.stablePNG {
      WidgetPreviewContainer(display: polar, size: size).preferredColorScheme(.dark)
    }
    let expected = try BaselineRenderer.stablePNG {
      WidgetPreviewContainer(display: known, size: size).preferredColorScheme(.dark)
    }
    let result = try #require(PixelComparison.compare(actual, to: expected))
    #expect(result.matches, "The unavailable face hid Stop: \(result)")

    var stopped = polar
    stopped.playback = nil
    let unavailable = try BaselineRenderer.stablePNG {
      WidgetPreviewContainer(display: stopped, size: size).preferredColorScheme(.dark)
    }
    #expect(PixelComparison.compare(expected, to: unavailable)?.matches == false)
  }

  /// Every consumer uses this decision; clearing or expiring playback restores the
  /// unavailable face without inventing a known prayer state.
  @Test func stopPriorityEndsWhenPlaybackClearsOrExpires() throws {
    var polar = try Self.polarPlayback()
    #expect(polar.widgetFace == .stop)
    let playback = try #require(polar.playback)
    polar.playback = nil
    #expect(polar.widgetFace == .unavailable)
    #expect(polar.prayerState == nil)

    let expired = SalahWidgetTimeline.make(
      settings: polar.settings, playback: playback,
      now: playback.alertDate.addingTimeInterval(30 * 60))
    let after = try #require(WidgetTimelineTests.displays(expired).first?.1)
    #expect(after.playback == nil)
    #expect(after.prayerState == nil)
    #expect(after.widgetFace == .unavailable)

    var known = WidgetPreviewData.idle(now: polar.date)
    #expect(known.widgetFace == .schedule)
    known.playback = playback
    #expect(known.widgetFace == .stop)
    known.playback = nil
    #expect(known.widgetFace == .schedule)
  }
}
