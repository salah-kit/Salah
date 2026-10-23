import Foundation
import SalahCore
import SalahUI
import SwiftUI

/// The design's coordinates: time runs horizontally and daylight follows a sine curve.
/// It deliberately needs both horizon crossings; unknown times never become invented data.
nonisolated struct IOSSunArcLayout: Equatable, Sendable {
  static let size = CGSize(width: 370, height: 190)
  static let horizon: CGFloat = 120
  static let amplitude: CGFloat = 96
  static let startX: CGFloat = 16
  static let endX: CGFloat = 354

  enum MarkerStyle: Equatable, Sendable { case reached, next, upcoming }
  struct Marker: Equatable, Sendable {
    let event: PrayerEvent
    let point: CGPoint
    let style: MarkerStyle
  }

  let sunriseX: CGFloat
  let maghribX: CGFloat
  let travelledEndX: CGFloat
  let markers: [Marker]
  let sun: CGPoint?

  init?(events: [PrayerEvent], now: Date, nextID: String?) {
    guard let sunrise = events.first(where: { $0.kind == .sunrise })?.time,
      let maghrib = events.first(where: { $0.kind == .maghrib })?.time,
      maghrib > sunrise
    else { return nil }
    let night = maghrib.timeIntervalSince(sunrise) * 0.15
    let start = min(sunrise.addingTimeInterval(-night), events.map(\.time).min() ?? sunrise)
    let end = max(maghrib.addingTimeInterval(night), events.map(\.time).max() ?? maghrib)
    let length = end.timeIntervalSince(start)
    func x(_ time: Date) -> CGFloat {
      Self.startX + CGFloat(time.timeIntervalSince(start) / length) * (Self.endX - Self.startX)
    }
    let rise = x(sunrise)
    let set = x(maghrib)
    sunriseX = rise
    maghribX = set
    let nowX = x(now)
    travelledEndX = min(max(nowX, rise), set)
    markers = events.map { event in
      let markerX = x(event.time)
      let style: MarkerStyle =
        event.time <= now ? .reached : (event.id == nextID ? .next : .upcoming)
      return Marker(
        event: event,
        point: CGPoint(x: markerX, y: Self.y(atX: markerX, sunriseX: rise, maghribX: set)),
        style: style)
    }
    sun =
      nowX >= Self.startX && nowX <= Self.endX
      ? CGPoint(x: nowX, y: Self.y(atX: nowX, sunriseX: rise, maghribX: set)) : nil
  }

  func y(atX x: CGFloat) -> CGFloat {
    Self.y(atX: x, sunriseX: sunriseX, maghribX: maghribX)
  }

  private static func y(atX x: CGFloat, sunriseX: CGFloat, maghribX: CGFloat) -> CGFloat {
    let angle = .pi * (x - sunriseX) / (maghribX - sunriseX)
    if angle >= 0, angle <= .pi { return horizon - amplitude * sin(angle) }
    let past = min(angle < 0 ? -angle : angle - .pi, .pi / 2)
    return horizon + amplitude * min(sin(past), 0.5)
  }

  func curve(from start: CGFloat, to end: CGFloat) -> [CGPoint] {
    guard end > start else { return [] }
    let steps = max(Int((end - start).rounded(.up)), 1)
    return (0...steps).map { step in
      let x = start + (end - start) * CGFloat(step) / CGFloat(steps)
      return CGPoint(x: x, y: y(atX: x))
    }
  }
}

/// A live sun chart. The surrounding list carries its accessible times.
struct IOSSunArc: View {
  let display: SalahDisplay
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.layoutDirection) private var direction
  @State private var availableWidth: CGFloat = 370

  private var scale: CGFloat { min(1, max(0, availableWidth) / IOSSunArcLayout.size.width) }

  var body: some View {
    let colors = SalahColors(phase: display.phase, scheme: scheme, contrast: contrast)
    Group {
      if let layout = IOSSunArcLayout(
        events: display.listedDay?.events ?? [], now: display.date,
        nextID: display.prayerState?.next?.id)
      {
        GeometryReader { proxy in
          ZStack(alignment: .topLeading) {
            chart(layout, colors: colors)
          }
          .frame(
            width: IOSSunArcLayout.size.width * scale, height: IOSSunArcLayout.size.height * scale
          )
          .environment(\.layoutDirection, .leftToRight)
          .frame(
            width: proxy.size.width, alignment: direction == .rightToLeft ? .trailing : .leading)
        }
        .frame(height: IOSSunArcLayout.size.height * scale)
        .accessibilityHidden(true)
        .onGeometryChange(for: CGFloat.self) {
          $0.size.width
        } action: {
          availableWidth = $0
        }
      } else {
        Label(
          IOSL10n.text(
            "Sun path unavailable for this day.", arabic: "مسار الشمس غير متاح لهذا اليوم.",
            locale: display.locale), systemImage: "sun.max.trianglebadge.exclamationmark"
        )
        .font(.footnote)
        .foregroundStyle(IOSTheme.labelSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
      }
    }
  }

  @ViewBuilder
  private func chart(_ layout: IOSSunArcLayout, colors: SalahColors) -> some View {
    stroke(
      [CGPoint(x: 8, y: 120), CGPoint(x: 362, y: 120)],
      color: colors.palette.separator.color, width: 1)
    stroke(
      layout.curve(from: IOSSunArcLayout.startX, to: layout.sunriseX),
      color: colors.palette.labelTertiary.color, width: 2)
    stroke(
      layout.curve(from: layout.maghribX, to: IOSSunArcLayout.endX),
      color: colors.palette.labelTertiary.color, width: 2)
    stroke(
      layout.curve(from: layout.travelledEndX, to: layout.maghribX),
      color: colors.palette.labelQuaternary.color, width: 3)
    stroke(
      layout.curve(from: layout.sunriseX, to: layout.travelledEndX),
      color: colors.phase.tint.color, width: 3)
    ForEach(layout.markers, id: \.event.id) { marker in
      markerView(marker.style, colors: colors).position(place(marker.point))
      markerLabel(marker, colors: colors)
    }
    if let sun = layout.sun {
      Circle().fill(colors.phase.tint.color.opacity(0.22))
        .frame(width: 34 * scale, height: 34 * scale).position(place(sun))
      Circle().fill(colors.phase.tint.color)
        .frame(width: 16 * scale, height: 16 * scale).position(place(sun))
    }
  }

  private func place(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: (direction == .rightToLeft ? IOSSunArcLayout.size.width - point.x : point.x) * scale,
      y: point.y * scale)
  }

  private func stroke(_ points: [CGPoint], color: Color, width: CGFloat) -> some View {
    Path { path in
      guard let first = points.first else { return }
      path.move(to: place(first))
      for point in points.dropFirst() { path.addLine(to: place(point)) }
    }
    .stroke(color, style: StrokeStyle(lineWidth: width * scale, lineCap: .round, lineJoin: .round))
  }

  @ViewBuilder
  private func markerView(_ style: IOSSunArcLayout.MarkerStyle, colors: SalahColors) -> some View {
    switch style {
    case .reached:
      Circle().fill(colors.phase.tint.color).frame(width: 9 * scale, height: 9 * scale)
    case .next:
      Circle().fill(IOSTheme.groupedSecondary)
        .overlay { Circle().strokeBorder(IOSTheme.accent, lineWidth: 2.5 * scale) }
        .frame(width: 9 * scale, height: 9 * scale)
    case .upcoming:
      Circle().fill(IOSTheme.groupedSecondary)
        .overlay { Circle().strokeBorder(IOSTheme.labelTertiary, lineWidth: 1.5 * scale) }
        .frame(width: 9 * scale, height: 9 * scale)
    }
  }

  private func markerLabel(_ marker: IOSSunArcLayout.Marker, colors: SalahColors) -> some View {
    let isNext = marker.style == .next
    let kind = marker.event.kind
    let lineHeight: CGFloat = isNext ? 16 : 13
    let nightTop = max(marker.point.y + 8, 141)
    let point: CGPoint =
      switch kind {
      case .sunrise, .maghrib:
        CGPoint(x: marker.point.x, y: 126 + lineHeight / 2)
      case .fajr:
        CGPoint(x: marker.point.x + 6, y: nightTop + lineHeight / 2)
      case .isha:
        CGPoint(x: marker.point.x - 6, y: nightTop + lineHeight / 2)
      case .dhuhr:
        CGPoint(x: marker.point.x, y: marker.point.y - 22 + lineHeight / 2)
      case .asr:
        CGPoint(x: marker.point.x + 44, y: marker.point.y)
      }
    let name = display.name(of: marker.event)
    let time = display.text.compactTime(marker.event.time)
    let title = isNext || kind == .sunrise || kind == .maghrib ? "\(name) \(time)" : name
    return Text(verbatim: title)
      .font(.system(size: (isNext ? 12 : 11) * scale, weight: isNext ? .semibold : .regular))
      .foregroundStyle(isNext ? IOSTheme.accentText : IOSTheme.labelSecondary)
      .lineLimit(1)
      .fixedSize()
      .frame(height: lineHeight * scale)
      .environment(\.layoutDirection, direction)
      .position(place(point))
  }
}
