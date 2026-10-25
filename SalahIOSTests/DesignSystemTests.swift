import Foundation
import SalahCore
import SwiftUI
import Testing
import UIKit

@Suite("iOS sun chart geometry")
struct DesignSystemTests {
  @Test @MainActor
  func readyArtworkKeepsThePrayerMarkInsideItsOpticalDesignSize() throws {
    let renderer = ImageRenderer(
      content: IOSOnboardingArtwork(
        step: .ready, readyKind: .asr, resourceBundle: Bundle(for: DesignSystemTestResources.self)
      )
      .environment(\.colorScheme, .light))
    renderer.scale = 1
    let image = try #require(renderer.uiImage?.cgImage)
    let mark = try #require(
      Self.drawnBounds(of: image) { red, green, blue, alpha in
        alpha > 0 && red < 150 && Int(green) - Int(red) > 25 && Int(blue) - Int(green) > 15
      })
    #expect(
      (45...65).contains(mark.width),
      "The 84-point symbol slot draws a 58-point prayer mark, not a 102-point mark.")
    #expect(mark.minX >= 70 && mark.maxX <= 150)
  }

  @Test @MainActor
  func onboardingLatticeRendersVisiblePixelsInBothAppearances() throws {
    for scheme in [ColorScheme.light, .dark] {
      let renderer = ImageRenderer(
        content: Image("OnboardingGeometry", bundle: Bundle(for: DesignSystemTestResources.self))
          .resizable()
          .frame(width: 220, height: 220)
          .environment(\.colorScheme, scheme))
      renderer.scale = 1
      let image = try #require(renderer.uiImage?.cgImage)
      let geometry = try #require(Self.drawnBounds(of: image) { _, _, _, alpha in alpha > 0 })
      #expect(
        geometry.width > 120 && geometry.height > 120,
        "The bundled lattice must decode to visible strokes rather than an empty mask.")
    }
  }

  @Test @MainActor
  func welcomeIconDrawsTheAppIconSkyOfEachAppearance() throws {
    for scheme in [ColorScheme.light, .dark] {
      let renderer = ImageRenderer(
        content: IOSOnboardingArtwork(
          step: .welcome, resourceBundle: Bundle(for: DesignSystemTestResources.self)
        )
        .environment(\.colorScheme, scheme))
      renderer.scale = 1
      let image = try #require(renderer.uiImage?.cgImage)
      let pixels = try Self.pixels(of: image)
      // The 112-point icon is centered in the 220-point artwork; this is its sky below the arch.
      let offset = (160 * image.width + 110) * 4
      let (red, blue, alpha) = (Int(pixels[offset]), Int(pixels[offset + 2]), pixels[offset + 3])
      #expect(alpha == 255, "The icon must draw an opaque sky, not an empty image.")
      switch scheme {
      case .dark:
        #expect(
          blue - red > 25 && red < 70,
          "Dark draws Salah.icon's dark night sky, not the light dusk (red \(red), blue \(blue)).")
      default:
        #expect(
          red - blue > 30 && red > 150,
          "Light draws Salah.icon's dusk at the horizon (red \(red), blue \(blue)).")
      }
    }
  }

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

  /// RGBA bytes, top row first.
  @MainActor
  private static func pixels(of image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    try pixels.withUnsafeMutableBytes { bytes in
      let context = try #require(
        CGContext(
          data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return pixels
  }

  @MainActor
  private static func drawnBounds(
    of image: CGImage, matching predicate: (UInt8, UInt8, UInt8, UInt8) -> Bool
  ) throws -> CGRect? {
    let width = image.width
    let height = image.height
    let pixels = try pixels(of: image)
    var left = width
    var top = height
    var right = -1
    var bottom = -1
    for y in 0..<height {
      for x in 0..<width {
        let offset = (y * width + x) * 4
        if predicate(pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3]) {
          left = min(left, x)
          top = min(top, y)
          right = max(right, x)
          bottom = max(bottom, y)
        }
      }
    }
    guard right >= left, bottom >= top else { return nil }
    return CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
  }

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

/// The asset catalog belongs to this unhosted test bundle, not Xcode's xctest agent.
private final class DesignSystemTestResources: NSObject {}
