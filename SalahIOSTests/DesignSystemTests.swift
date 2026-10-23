import Foundation
import SalahCore
import SwiftUI
import Testing
import UIKit

@Suite("iOS sun chart geometry")
struct DesignSystemTests {
  @Test @MainActor
  func sunCardNeverExpandsAParentToTheReferenceChartWidth() throws {
    var preferences = IOSPreferences()
    let zone = try #require(TimeZone(identifier: "Asia/Riyadh"))
    preferences.location = PrayerLocation(
      latitude: 21.4225, longitude: 39.8262, timeZone: zone, name: "Makkah")
    let settings = try #require(preferences.mirror)
    let display = SalahDisplay(
      date: Self.day.start(in: zone).addingTimeInterval(13 * 3_600 + 19 * 60),
      settings: settings, schedule: settings.schedule)
    for width: CGFloat in [280, 320, 402, 834] {
      let host = UIHostingController(
        rootView: VStack(alignment: .leading) {
          IOSCard { IOSSunArc(display: display) }
        }
        .padding(16))
      let measured = host.sizeThatFits(in: CGSize(width: width, height: 1_000))
      #expect(
        abs(measured.width - width) < 0.5,
        "The 370-point drawing must accept a narrow parent before measuring its reference content.")
      #expect(measured.height > 0)
    }
  }

  @Test func horizonCrossingsAndDaylightPeakKeepTheDesignCoordinates() throws {
    let layout = try #require(Self.layout(now: 12))
    #expect(abs(layout.y(atX: layout.sunriseX) - 120) < 0.000_001)
    #expect(abs(layout.y(atX: layout.maghribX) - 120) < 0.000_001)
    let midpoint = (layout.sunriseX + layout.maghribX) / 2
    #expect(abs(layout.y(atX: midpoint) - 24) < 0.000_001)
    #expect(layout.sunriseX < midpoint)
    #expect(midpoint < layout.maghribX)
  }

  @Test func chronologicalEventsStayInOrderAndInsideTheDrawnFrame() throws {
    let layout = try #require(Self.layout(now: 12))
    #expect(layout.markers.map(\.event.kind) == PrayerKind.allCases)
    let xs = layout.markers.map(\.point.x)
    #expect(zip(xs, xs.dropFirst()).allSatisfy { pair in pair.0 < pair.1 })
    #expect(xs.allSatisfy { (16...354).contains($0) })
    #expect(layout.markers.allSatisfy { (24...168).contains($0.point.y) })
  }

  @Test func nightDepthNeverFallsOutsideTheChart() throws {
    let layout = try #require(Self.layout(now: 12))
    #expect(layout.y(atX: layout.sunriseX - 1_000) == 168)
    #expect(layout.y(atX: layout.maghribX + 1_000) == 168)
    #expect(layout.markers.first?.point.y ?? 0 > 120)
    #expect(layout.markers.last?.point.y ?? 0 > 120)
  }

  @Test func travelledDaylightIsClampedAndTheSunLeavesTheDrawnInterval() throws {
    let early = try #require(Self.layout(now: 1))
    #expect(early.travelledEndX == early.sunriseX)
    #expect(early.sun == nil)
    let late = try #require(Self.layout(now: 23))
    #expect(late.travelledEndX == late.maghribX)
    #expect(late.sun == nil)
    let noon = try #require(Self.layout(now: 12))
    let sun = try #require(noon.sun)
    #expect(abs(sun.x - (noon.sunriseX + noon.maghribX) / 2) < 0.000_001)
    #expect(abs(sun.y - 24) < 0.000_001)
    #expect(noon.travelledEndX == sun.x)
  }

  @Test func nextMarkerUsesTheOccurrenceIdentityAndReachedEventsStayReached() throws {
    let events = Self.events()
    let asr = try #require(events.first { $0.kind == .asr })
    let layout = try #require(
      IOSSunArcLayout(events: events, now: Self.time(12), nextID: asr.id))
    #expect(layout.markers.filter { $0.style == .next }.map(\.event.id) == [asr.id])
    #expect(
      layout.markers.filter { $0.style == .reached }.map(\.event.kind) == [.fajr, .sunrise, .dhuhr])
    var anotherOccurrence = asr
    anotherOccurrence.time = asr.time.addingTimeInterval(1)
    let changed = try #require(
      IOSSunArcLayout(events: events, now: Self.time(12), nextID: anotherOccurrence.id))
    #expect(changed.markers.allSatisfy { $0.style != .next })
    let started = try #require(
      IOSSunArcLayout(events: events, now: asr.time, nextID: asr.id))
    #expect(started.markers.first { $0.event.id == asr.id }?.style == .reached)
  }

  @Test func anIshaAfterMidnightStillBelongsInsideItsOwningDayChart() throws {
    var events = Self.events()
    events[5].time = Self.time(25)
    let layout = try #require(
      IOSSunArcLayout(events: events, now: Self.time(23), nextID: events[5].id))
    let isha = try #require(layout.markers.first { $0.event.kind == .isha })
    #expect(isha.event.scheduleDay == Self.day)
    #expect(abs(isha.point.x - 354) < 0.000_001)
    #expect(isha.point.y <= 168)
    #expect(isha.style == .next)
    #expect(layout.sun != nil)
    #expect(layout.travelledEndX == layout.maghribX)
  }

  @Test func missingOrReversedHorizonTimesNeverCreateAnArc() {
    let events = Self.events()
    #expect(IOSSunArcLayout(events: [], now: Self.time(12), nextID: nil) == nil)
    for missing in [PrayerKind.sunrise, .maghrib] {
      #expect(
        IOSSunArcLayout(
          events: events.filter { $0.kind != missing }, now: Self.time(12), nextID: nil) == nil)
    }
    var reversed = events
    reversed[4].time = Self.time(5)
    #expect(IOSSunArcLayout(events: reversed, now: Self.time(12), nextID: nil) == nil)
    reversed[4].time = Self.time(6)
    #expect(IOSSunArcLayout(events: reversed, now: Self.time(12), nextID: nil) == nil)
  }

  @Test func curvesIncludeTheirExactEndpointsAndRejectEmptySpans() throws {
    let layout = try #require(Self.layout(now: 12))
    let curve = layout.curve(from: layout.sunriseX, to: layout.maghribX)
    #expect(abs((curve.first?.x ?? 0) - layout.sunriseX) < 0.000_001)
    #expect(abs((curve.last?.x ?? 0) - layout.maghribX) < 0.000_001)
    #expect(curve.allSatisfy { $0.y >= 24 && $0.y <= 120 })
    #expect(layout.curve(from: 100, to: 100).isEmpty)
    #expect(layout.curve(from: 100, to: 99).isEmpty)
  }

  private static let day = CivilDay(year: 2026, month: 6, day: 2)

  private static func time(_ hour: TimeInterval) -> Date {
    day.start(in: .gmt).addingTimeInterval(hour * 3_600)
  }

  private static func events() -> [PrayerEvent] {
    zip(PrayerKind.allCases, [4.0, 6, 12, 16, 18, 20]).map { kind, hour in
      PrayerEvent(scheduleDay: day, kind: kind, time: time(hour))
    }
  }

  private static func layout(now hour: TimeInterval) -> IOSSunArcLayout? {
    IOSSunArcLayout(events: events(), now: time(hour), nextID: nil)
  }
}
