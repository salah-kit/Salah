import Foundation
import SalahCore
import Testing

/// The extra-large widget's sun arc places the fixture day where the design draws it:
/// Makkah, 2 June 2026, at 13:19 (component "Sun Arc", State=Day).
@Suite("Sun arc layout")
struct SunArcLayoutTests {
  init() { TestEnvironment.configure() }

  private func layout(_ state: SpecState) throws -> SunArcLayout {
    let display = BaselinePipeline.display(for: state, language: .en)
    return try #require(SunArcLayout(rows: WidgetTimes.rows(of: display), now: display.date))
  }

  private func marker(_ kind: PrayerKind, in layout: SunArcLayout) throws -> SunArcLayout.Marker {
    try #require(layout.markers.first { $0.event.kind == kind })
  }

  private func expectNear(_ point: CGPoint?, _ x: CGFloat, _ y: CGFloat) {
    #expect(abs((point?.x ?? .nan) - x) < 0.15, "x \(String(describing: point)) vs \(x)")
    #expect(abs((point?.y ?? .nan) - y) < 0.15, "y \(String(describing: point)) vs \(y)")
  }

  @Test func theDayLandsWhereTheDesignDrawsIt() throws {
    let arc = try layout(.idle)
    // The design's marker centers, in its 370 × 190 points.
    expectNear(try marker(.fajr, in: arc).point, 26.8, 152.1)
    expectNear(try marker(.sunrise, in: arc).point, 55, 120)
    expectNear(try marker(.dhuhr, in: arc).point, 185, 24)
    expectNear(try marker(.asr, in: arc).point, 248.5, 50.9)
    expectNear(try marker(.maghrib, in: arc).point, 315, 120)
    expectNear(try marker(.isha, in: arc).point, 344.2, 153.1)
    expectNear(arc.sun, 204.4, 26.6)
    #expect(abs(arc.travelledEndX - 204.4) < 0.15)
  }

  @Test func markersFollowTheRows() throws {
    let arc = try layout(.idle)
    let styles = try PrayerKind.allCases.map { try marker($0, in: arc).style }
    #expect(styles == [.reached, .reached, .reached, .next, .upcoming, .upcoming])
  }

  /// After Maghrib the whole day is travelled; once the sun is past the night drawn after
  /// Maghrib, it leaves the arc.
  @Test func theSunLeavesTheArcAtNight() throws {
    let dusk = try layout(.playingAdhan)
    #expect(dusk.travelledEndX == SunArcLayout.maghribX)
    #expect(dusk.sun != nil)

    let night = try layout(.endOfDay)
    #expect(night.sun == nil)
  }

  /// Without sunrise or Maghrib there's no day to draw.
  @Test func noArcWithoutSunriseAndMaghrib() {
    let rows = Fixture.day().events
      .filter { $0.kind != .sunrise }
      .map { (event: $0, role: WidgetTimes.Role.upcoming) }
    #expect(SunArcLayout(rows: rows, now: Fixture.date(13, 19)) == nil)
  }
}
