import SalahCore
import SwiftUI
import WidgetKit

// MARK: - Layout

/// Where the sun arc draws the day, in the design's 370 × 190 points, left to right. The
/// x axis is time, from 16 to 354: the day from sunrise to Maghrib, with night on each side,
/// 15% of the day's length or as far as Fajr and Isha when they're further out (in Makkah
/// in June, sunrise lands at 55 and Maghrib at 315, as the design draws it). The y axis is
/// the sun's height, `sin(π · (t − sunrise) / (Maghrib − sunrise))` above a horizon at 120,
/// so Dhuhr peaks midway and Fajr and Isha fall below; the night is no deeper than half the
/// day's height, so a long night stays inside the frame.
nonisolated struct SunArcLayout: Equatable {
  static let size = CGSize(width: 370, height: 190)
  static let horizonY: CGFloat = 120
  static let horizonInset: CGFloat = 8
  static let amplitude: CGFloat = 96
  /// The curve's ends.
  static let startX: CGFloat = 16
  static let endX: CGFloat = 354
  /// The night drawn beyond sunrise and Maghrib at least, as a share of the day's length.
  static let nightShare = 0.15
  /// How far below the horizon the night goes at most, as a share of `amplitude`.
  static let nightDepth: CGFloat = 0.5

  /// How a prayer's marker is drawn.
  enum MarkerStyle: Equatable {
    /// Passed, or the prayer one is in: filled in the mark.
    case reached
    /// The next prayer: a ring in the accent.
    case next
    /// Later today: a quiet ring.
    case upcoming
  }

  struct Marker: Equatable {
    let event: PrayerEvent
    let point: CGPoint
    let style: MarkerStyle
  }

  /// Where sunrise and Maghrib fall: the day between them is above the horizon.
  let sunriseX: CGFloat
  let maghribX: CGFloat
  let markers: [Marker]
  /// Where the travelled path ends: now, held between sunrise and Maghrib.
  let travelledEndX: CGFloat
  /// The sun now, or nil when now falls outside the drawn part of the day.
  let sun: CGPoint?

  /// The arc for a day's rows at `now`, or nil without both sunrise and Maghrib.
  init?(rows: [(event: PrayerEvent, role: WidgetTimes.Role)], now: Date) {
    guard let sunrise = rows.first(where: { $0.event.kind == .sunrise })?.event.time,
      let maghrib = rows.first(where: { $0.event.kind == .maghrib })?.event.time,
      maghrib > sunrise
    else { return nil }
    let night = maghrib.timeIntervalSince(sunrise) * Self.nightShare
    let times = rows.map(\.event.time)
    let start = min(sunrise.addingTimeInterval(-night), times.min() ?? sunrise)
    let end = max(maghrib.addingTimeInterval(night), times.max() ?? maghrib)
    let length = end.timeIntervalSince(start)
    func x(_ time: Date) -> CGFloat {
      Self.startX + CGFloat(time.timeIntervalSince(start) / length) * (Self.endX - Self.startX)
    }
    sunriseX = x(sunrise)
    maghribX = x(maghrib)
    let nowX = x(now)
    travelledEndX = min(max(nowX, sunriseX), maghribX)
    let (dayStart, dayEnd) = (sunriseX, maghribX)
    func y(_ x: CGFloat) -> CGFloat { Self.y(atX: x, sunriseX: dayStart, maghribX: dayEnd) }
    markers = rows.map { row in
      let markerX = x(row.event.time)
      let style: MarkerStyle =
        switch row.role {
        case .passed, .current: .reached
        case .next: .next
        case .upcoming: .upcoming
        }
      return Marker(
        event: row.event, point: CGPoint(x: markerX, y: y(markerX)), style: style)
    }
    sun = nowX >= Self.startX && nowX <= Self.endX ? CGPoint(x: nowX, y: y(nowX)) : nil
  }

  /// The curve's height at `x`.
  func y(atX x: CGFloat) -> CGFloat {
    Self.y(atX: x, sunriseX: sunriseX, maghribX: maghribX)
  }

  private static func y(atX x: CGFloat, sunriseX: CGFloat, maghribX: CGFloat) -> CGFloat {
    let angle = .pi * (x - sunriseX) / (maghribX - sunriseX)
    if angle >= 0, angle <= .pi { return horizonY - amplitude * sin(angle) }
    let past = min(angle < 0 ? -angle : angle - .pi, .pi / 2)
    return horizonY + amplitude * min(sin(past), nightDepth)
  }

  /// The curve from `start` to `end`, as points one design point apart.
  func curve(from start: CGFloat, to end: CGFloat) -> [CGPoint] {
    guard end > start else { return [] }
    let steps = max(Int((end - start).rounded(.up)), 1)
    return (0...steps).map { step in
      let x = start + (end - start) * CGFloat(step) / CGFloat(steps)
      return CGPoint(x: x, y: y(atX: x))
    }
  }
}

// MARK: - View

/// The day as the sun's height, for the extra-large face: the night before sunrise and
/// after Maghrib, the path the sun has travelled in the time of day's mark (the accentable
/// element), what remains, a marker and a label for each prayer, and the sun now. It
/// repeats what the hero and the times say, so VoiceOver skips it.
struct WidgetSunArc: View {
  let display: SalahDisplay
  let style: WidgetStyle
  /// The arc's scale from the design's 370 × 190 points.
  var scale: CGFloat = 1
  @Environment(\.layoutDirection) private var direction

  var body: some View {
    let rows = WidgetTimes.rows(of: display)
    ZStack(alignment: .topLeading) {
      if let layout = SunArcLayout(rows: rows, now: display.date) {
        arc(layout)
      }
    }
    .frame(
      width: SunArcLayout.size.width * scale, height: SunArcLayout.size.height * scale,
      alignment: .topLeading
    )
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func arc(_ layout: SunArcLayout) -> some View {
    let horizon = [
      CGPoint(x: SunArcLayout.horizonInset, y: SunArcLayout.horizonY),
      CGPoint(x: SunArcLayout.size.width - SunArcLayout.horizonInset, y: SunArcLayout.horizonY),
    ]
    Group {
      stroke(horizon, style.separator, width: 1)
      stroke(layout.curve(from: SunArcLayout.startX, to: layout.sunriseX), style.tertiary, width: 2)
      stroke(layout.curve(from: layout.maghribX, to: SunArcLayout.endX), style.tertiary, width: 2)
      stroke(
        layout.curve(from: layout.travelledEndX, to: layout.maghribX), style.quaternary, width: 3)
      stroke(layout.curve(from: layout.sunriseX, to: layout.travelledEndX), style.mark, width: 3)
        .widgetAccentable()
    }
    // The rings are hollow where the system removes their fill, in accented and vibrant
    // rendering: the horizon and the path stop at them instead of showing through.
    .mask {
      ZStack {
        Rectangle()
        ForEach(layout.markers.filter { $0.style != .reached }, id: \.event.id) { marker in
          Circle()
            .frame(width: 9 * scale, height: 9 * scale)
            .position(place(marker.point))
            .blendMode(.destinationOut)
        }
      }
      .compositingGroup()
    }
    ForEach(layout.markers, id: \.event.id) { marker in
      markerView(marker.style)
        .position(place(marker.point))
    }
    if let sun = layout.sun {
      Circle().fill(style.mark).opacity(0.22)
        .frame(width: 34 * scale, height: 34 * scale)
        .position(place(sun))
      Circle().fill(style.mark)
        .frame(width: 16 * scale, height: 16 * scale)
        .position(place(sun))
    }
    ForEach(layout.markers, id: \.event.id) { marker in
      label(marker)
    }
  }

  /// A design point in the frame: scaled, and mirrored right to left.
  private func place(_ point: CGPoint) -> CGPoint {
    let x = direction == .rightToLeft ? SunArcLayout.size.width - point.x : point.x
    return CGPoint(x: x * scale, y: point.y * scale)
  }

  private func stroke(_ points: [CGPoint], _ color: AnyShapeStyle, width: CGFloat) -> some View {
    Path { path in
      guard let first = points.first else { return }
      path.move(to: place(first))
      for point in points.dropFirst() { path.addLine(to: place(point)) }
    }
    .stroke(color, style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
  }

  @ViewBuilder
  private func markerView(_ markerStyle: SunArcLayout.MarkerStyle) -> some View {
    let side = 9 * scale
    switch markerStyle {
    case .reached:
      Circle().fill(style.mark).frame(width: side, height: side)
    case .next:
      Circle().fill(style.markerFill)
        .overlay { Circle().strokeBorder(style.accentMark, lineWidth: 2.5 * scale) }
        .frame(width: side, height: side)
    case .upcoming:
      Circle().fill(style.markerFill)
        .overlay { Circle().strokeBorder(style.tertiary, lineWidth: 1.5 * scale) }
        .frame(width: side, height: side)
    }
  }

  /// The top of the Sunrise and Maghrib labels, under the horizon.
  private static let horizonLabelTop = SunArcLayout.horizonY + 6

  /// The top of Fajr's or Isha's label: under its marker, and never on the line of the
  /// Sunrise and Maghrib labels when the prayer falls close to them.
  private static func nightLabelTop(_ marker: SunArcLayout.Marker) -> CGFloat {
    max(marker.point.y + 8, horizonLabelTop + 13 + 2)
  }

  /// A prayer's label: Sunrise and Maghrib with their times under the horizon, Fajr and
  /// Isha under their markers and a little toward the day, Dhuhr above its own, Asr beside
  /// it toward the evening. The
  /// next prayer's label carries its time, in the accent.
  @ViewBuilder
  private func label(_ marker: SunArcLayout.Marker) -> some View {
    let isNext = marker.style == .next
    let kind = marker.event.kind
    let name = display.name(of: marker.event)
    let time = display.text.compactTime(marker.event.time)
    let showsTime = isNext || kind == .sunrise || kind == .maghrib
    let lineHeight: CGFloat = isNext ? 16 : 13
    let center: CGPoint =
      switch kind {
      case .sunrise, .maghrib:
        CGPoint(x: marker.point.x, y: Self.horizonLabelTop + lineHeight / 2)
      case .fajr:
        CGPoint(x: marker.point.x + 6, y: Self.nightLabelTop(marker) + lineHeight / 2)
      case .isha:
        CGPoint(x: marker.point.x - 6, y: Self.nightLabelTop(marker) + lineHeight / 2)
      case .dhuhr:
        CGPoint(x: marker.point.x, y: marker.point.y - 22 + lineHeight / 2)
      case .asr:
        CGPoint(x: marker.point.x + 44, y: marker.point.y)
      }
    Text(verbatim: showsTime ? "\(name) \(time)" : name)
      .font(.system(size: (isNext ? 12 : 11) * scale, weight: isNext ? .semibold : .regular))
      .foregroundStyle(isNext ? style.accent : style.secondary)
      .lineLimit(1)
      .fixedSize()
      .frame(height: lineHeight * scale)
      .environment(\.layoutDirection, direction)
      .position(place(center))
  }
}
