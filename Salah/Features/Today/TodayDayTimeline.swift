import SalahCore
import SwiftUI

/// A time of day, from the prayer that opens it: dawn from Fajr, day from sunrise, afternoon
/// from Asr, dusk from Maghrib and night from Isha, through midnight to the next Fajr.
nonisolated enum DayPhase: Equatable, Sendable {
  case fajr, dhuhr, asr, maghrib, isha

  /// A stretch of the day in one phase.
  struct Segment: Equatable, Sendable {
    var phase: DayPhase
    var start: Date
    var end: Date
  }

  /// The phase an event opens, if it opens one. Dhuhr opens the day only when the day has
  /// no sunrise to open it.
  private static func opened(by event: PrayerEvent, hasSunrise: Bool) -> DayPhase? {
    switch event.kind {
    case .fajr: .fajr
    case .sunrise: .dhuhr
    case .dhuhr: hasSunrise ? nil : .dhuhr
    case .asr: .asr
    case .maghrib: .maghrib
    case .isha: .isha
    }
  }

  /// The day from `start` to `end` in phases, from the day's events: the phase at `start`,
  /// night unless an event before it opened another (a Fajr before midnight), then each phase
  /// from the event that opens it to the next one.
  static func segments(of events: [PrayerEvent], from start: Date, to end: Date) -> [Segment] {
    guard start < end else { return [] }
    let hasSunrise = events.contains { $0.kind == .sunrise }
    let openings =
      events
      .filter { $0.time > start && $0.time < end }
      .sorted { $0.time < $1.time }
      .compactMap { event in opened(by: event, hasSunrise: hasSunrise).map { (event.time, $0) } }
    var segments: [Segment] = []
    var phase = Self.phase(at: start, events: events)
    var from = start
    for (time, next) in openings {
      if time > from { segments.append(Segment(phase: phase, start: from, end: time)) }
      phase = next
      from = time
    }
    segments.append(Segment(phase: phase, start: from, end: end))
    return segments
  }

  /// The phase at `date`: the last one an event of the day opened before it, or night.
  static func phase(at date: Date, events: [PrayerEvent]) -> DayPhase {
    let hasSunrise = events.contains { $0.kind == .sunrise }
    return
      events
      .filter { $0.time <= date }
      .sorted { $0.time < $1.time }
      .compactMap { opened(by: $0, hasSunrise: hasSunrise) }
      .last ?? .isha
  }
}

extension DayPhase {
  var colors: WindowPalette.Phase {
    switch self {
    case .fajr: WindowPalette.fajr
    case .dhuhr: WindowPalette.dhuhr
    case .asr: WindowPalette.asr
    case .maghrib: WindowPalette.maghrib
    case .isha: WindowPalette.isha
    }
  }
}

/// The day as a 24-hour ribbon in the colors of its times of day, from midnight to
/// midnight in the location's time zone: the past dimmed, and a knob at now. VoiceOver skips
/// it; the rows beside it say the times.
struct TodayDayTimeline: View {
  let day: PrayerDay
  let date: Date

  @Environment(\.layoutDirection) private var layoutDirection

  var body: some View {
    let start = day.day.start(in: day.timeZone)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = day.timeZone
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    let segments = DayPhase.segments(of: day.events, from: start, to: end)
    let length = end.timeIntervalSince(start)
    let now = min(max(date, start), end)

    return GeometryReader { proxy in
      let width = proxy.size.width
      let knob: CGFloat = 12
      let track = max(width - knob, 1)
      let x = { (time: Date) -> CGFloat in
        CGFloat(time.timeIntervalSince(start) / length) * track
      }
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
        .frame(width: track, height: 5, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .offset(x: knob / 2)
        Circle()
          .fill(.background)
          .overlay(Circle().strokeBorder(.primary, lineWidth: 1.5))
          .frame(width: knob, height: knob)
          .offset(x: x(now))
      }
      .frame(width: width, height: proxy.size.height, alignment: .leading)
    }
    .frame(height: 20)
    .environment(\.layoutDirection, .leftToRight)
    .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
    .accessibilityHidden(true)
  }

  private func bar(_ phase: DayPhase, from: CGFloat, to: CGFloat) -> some View {
    Rectangle()
      .fill(phase.colors.tint)
      .frame(width: max(to - from, 0), height: 5)
      .offset(x: from)
  }
}
