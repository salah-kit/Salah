import SalahCore
import SalahUI
import SwiftUI

/// The day as a 24-hour ribbon in the colors of its times of day, from midnight to midnight
/// in the location's time zone: the past dimmed, and a knob at now. The dropdown and Today
/// show it. VoiceOver skips it; the rows beside it say the times.
struct SalahDayTimeline: View {
  let day: PrayerDay
  let date: Date
  /// Whether the ribbon takes each time of day's color, or the neutral one throughout.
  var followsTimeOfDay = true

  @Environment(\.layoutDirection) private var layoutDirection
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let start = day.day.start(in: day.timeZone)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = day.timeZone
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    let segments = SalahPhase.segments(of: day.events, from: start, to: end)
    let length = end.timeIntervalSince(start)
    let now = min(max(date, start), end)
    let palette = SalahPalette(isDark: scheme == .dark, increasedContrast: contrast == .increased)

    return GeometryReader { proxy in
      let width = proxy.size.width
      let x = { (time: Date) -> CGFloat in
        CGFloat(time.timeIntervalSince(start) / length) * width
      }
      // The knob stays whole at the day's ends.
      let knobCenter = min(max(x(now), Metrics.knob / 2), width - Metrics.knob / 2)
      ZStack(alignment: .leading) {
        ZStack(alignment: .leading) {
          ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
            let past = min(segment.end, now)
            if past > segment.start {
              bar(segment.phase, from: x(segment.start), to: x(past)).opacity(0.35)
            }
            let future = max(segment.start, now)
            if segment.end > future {
              bar(segment.phase, from: x(future), to: x(segment.end))
            }
          }
        }
        .frame(width: width, height: Metrics.bar, alignment: .leading)
        .clipShape(Capsule())
        Circle()
          .fill(palette.groupedSecondary.color)
          .overlay(Circle().strokeBorder(palette.labelPrimary.color, lineWidth: Metrics.stroke))
          .frame(width: Metrics.knob, height: Metrics.knob)
          .offset(x: knobCenter - Metrics.knob / 2)
      }
      .frame(width: width, height: proxy.size.height, alignment: .leading)
    }
    .frame(height: Metrics.height)
    .environment(\.layoutDirection, .leftToRight)
    .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
    .accessibilityHidden(true)
  }

  /// Figma's Day Timeline: the ribbon across the whole width, and the knob centered on now.
  private enum Metrics {
    static let height: CGFloat = 20.7
    static let bar: CGFloat = 5.175
    static let knob: CGFloat = 12.075
    static let stroke: CGFloat = 1.725
  }

  private func bar(_ phase: SalahPhase, from: CGFloat, to: CGFloat) -> some View {
    let tint = (followsTimeOfDay ? phase : .neutral)
      .colors(isDark: scheme == .dark, increasedContrast: contrast == .increased).tint
    return Rectangle()
      .fill(tint.color)
      .frame(width: max(to - from, 0), height: Metrics.bar)
      .offset(x: from)
  }
}
