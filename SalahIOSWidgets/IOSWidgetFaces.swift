import SalahCore
import SalahUI
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Sizes

/// The widget sizes Salah supports.
nonisolated enum SalahWidgetSize: Sendable, Hashable {
  case small
  case medium
  case large
  case extraLarge
}

nonisolated extension SalahWidgetSize {
  /// The point size of each family on the Home Screen, as measured in the iOS design, for the
  /// previews and the visual baselines; the extension takes its host's actual bounds.
  var previewPointSize: CGSize {
    switch self {
    case .small: CGSize(width: 164, height: 164)
    case .medium: CGSize(width: 344, height: 164)
    case .large: CGSize(width: 344, height: 344)
    // The design's size; an iPad extra-large widget.
    case .extraLarge: CGSize(width: 715, height: 342)
    }
  }

  /// The corner radius the previews and baselines clip each family to, as the design draws
  /// it; on the Home Screen, the system shapes the widget.
  var previewCornerRadius: CGFloat { self == .extraLarge ? 24 : 22 }
}

// MARK: - Styles

/// The widget's colors for its appearance and how WidgetKit renders it. In full color they
/// are Salah's tokens on the time of day's sky; in accented and vibrant rendering the system
/// draws the content from the semantic styles, and the sky goes.
nonisolated struct WidgetStyle {
  let colors: SalahColors
  let isFullColor: Bool

  init(
    phase: SalahPhase, scheme: ColorScheme, contrast: ColorSchemeContrast,
    renderingMode: WidgetRenderingMode
  ) {
    colors = SalahColors(phase: phase, scheme: scheme, contrast: contrast)
    isFullColor = renderingMode == .fullColor
  }

  private func token(_ color: ThemeColor, else system: some ShapeStyle) -> AnyShapeStyle {
    isFullColor ? AnyShapeStyle(color.color) : AnyShapeStyle(system)
  }

  /// `widget/primary`.
  var primary: AnyShapeStyle { token(colors.palette.labelPrimary, else: .primary) }
  /// `widget/secondary`.
  var secondary: AnyShapeStyle { token(colors.palette.labelSecondary, else: .secondary) }
  /// `widget/tertiary`: passed rows.
  var tertiary: AnyShapeStyle { token(colors.palette.labelTertiary, else: .tertiary) }
  /// `label/quaternary`: the sun arc's path still to come.
  var quaternary: AnyShapeStyle { token(colors.palette.labelQuaternary, else: .quaternary) }
  /// `widget/accent`: the one accentable element, the countdown or the next row.
  var accent: AnyShapeStyle { token(colors.palette.accentText, else: .primary) }
  /// `widget/mark`: glyphs, the progress bar, and the prayer one is in: its row, its
  /// count-up and Now.
  var mark: AnyShapeStyle { token(colors.phase.tint, else: .secondary) }
  /// `widget/track`: the progress bar's track and the next row's wash.
  var track: AnyShapeStyle { token(colors.palette.fillSecondary, else: .quaternary) }
  /// `widget/separator`.
  var separator: AnyShapeStyle { token(colors.palette.separator, else: .quaternary) }
  /// `accent/default`: the ring on the sun arc's next prayer.
  var accentMark: AnyShapeStyle { token(colors.palette.accent, else: .primary) }
  /// `bg/grouped-secondary`: inside the sun arc's rings.
  var markerFill: AnyShapeStyle { token(colors.palette.groupedSecondary, else: Color.clear) }
  /// `widget/badge` and `widget/on-badge`: the Now badge.
  var badge: AnyShapeStyle { token(colors.palette.accentFill, else: .quaternary) }
  var onBadge: AnyShapeStyle { token(colors.palette.labelOnAccent, else: .primary) }
}

/// The sky behind a widget face: the time of day's gradient.
nonisolated struct WidgetSky: View {
  let phase: SalahPhase
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    SalahColors(phase: phase, scheme: scheme, contrast: contrast).sky
  }
}

// MARK: - Metrics

/// The design's sizes for what the faces draw, so they match the widget components.
nonisolated enum WidgetMetrics {
  /// A prayer glyph's point size in a box `side` points square: the design draws the
  /// glyph about two-thirds of the box wide.
  static func glyphFontSize(side: CGFloat) -> CGFloat { side * 0.585 }
  /// The Stop symbol's circle in a box `side` points square, as the design draws it.
  static func stopDiameter(side: CGFloat) -> CGFloat { side * 0.83 }
  /// The medium face's hairline between the hero and the times.
  static let mediumHairlineHeight: CGFloat = 128
}

extension View {
  /// One line of text in a box of the design's line height, centered in it as the
  /// design sets it, so the faces' rows land where the components put them.
  func lineBox(_ height: CGFloat) -> some View {
    frame(height: height)
  }

  /// Fills the space it's offered and pins its content to the top leading corner, even
  /// when the content is taller: the design's large face runs 2 points into its bottom
  /// padding, which a centered overflow would shift up instead.
  func topAligned() -> some View {
    frame(
      minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
  }

  /// Lines of `fontSize`-point system text at the design's line `height`: the extra
  /// leading goes between the lines and half of it above the first and below the last.
  func designLineHeight(_ height: CGFloat, fontSize: CGFloat, weight: UIFont.Weight) -> some View {
    let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
    let extra = max(height - (font.ascender - font.descender + font.leading), 0)
    return lineSpacing(extra).padding(.vertical, extra / 2)
  }
}

/// Resolves a widget face's style from the environment.
private struct StyledFace<Content: View>: View {
  let phase: SalahPhase
  @ViewBuilder let content: (WidgetStyle) -> Content
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    content(
      WidgetStyle(
        phase: phase, scheme: scheme, contrast: contrast, renderingMode: renderingMode))
  }
}

// MARK: - Schedule faces

/// The widget's face for a display: the next prayer (or the one that just began, or
/// tomorrow's Fajr), with the day's times in the larger sizes. The extension's shell puts
/// the sky behind it and makes it a link; the in-app preview uses it unchanged.
struct WidgetContentView: View {
  let display: SalahDisplay
  let size: SalahWidgetSize

  var body: some View {
    StyledFace(phase: display.phase) { style in
      let hero = WidgetHero(display: display)
      Group {
        switch size {
        case .small: SmallFace(display: display, hero: hero, style: style)
        case .medium: MediumFace(display: display, hero: hero, style: style)
        case .large: LargeFace(display: display, hero: hero, style: style)
        case .extraLarge: ExtraLargeFace(display: display, hero: hero, style: style)
        }
      }
      .overlay {
        // Approaching: a 2 pt accent rim around the face.
        if hero?.isApproaching == true {
          ContainerRelativeShape()
            .strokeBorder(style.accent, lineWidth: 2)
            .widgetAccentable()
        }
      }
    }
  }
}

/// What the face's hero says, from the display.
nonisolated struct WidgetHero {
  enum Kind { case next, justStarted, tomorrow }

  let kind: Kind
  let event: PrayerEvent
  let name: String
  let eyebrow: String
  let footer: String
  let isApproaching: Bool

  init?(display: SalahDisplay) {
    guard let focus = display.focus else { return nil }
    let labels = display.labels
    event = focus.event
    name = display.name(of: focus.event)
    if focus.isCountUp {
      kind = .justStarted
      eyebrow = labels.now
      if let next = display.prayerState?.nextPrayer {
        footer = labels.nextLine(prayer: display.name(of: next), time: display.timeText(of: next))
      } else {
        footer = ""
      }
    } else {
      kind = display.focusIsTomorrow ? .tomorrow : .next
      eyebrow = display.focusIsTomorrow ? labels.tomorrow : labels.nextPrayer
      footer = labels.atTime(display.timeText(of: focus.event))
    }
    isApproaching =
      !focus.isCountUp && display.prayerState?.isApproaching == true
      && !display.settings.silentMode
  }
}

/// The live countdown, or the count-up after a prayer began: `2:16:00`, `+0:04:00`.
private struct WidgetTimer: View {
  let hero: WidgetHero
  let date: Date
  let size: CGFloat
  let style: WidgetStyle
  @Environment(\.salahTimerPause) private var pause
  @Environment(\.locale) private var locale

  var body: some View {
    Group {
      if hero.kind == .justStarted {
        HStack(spacing: 0) {
          Text(verbatim: "+")
          if let pause {
            still(pause.timeIntervalSince(hero.event.time))
          } else {
            Text(
              timerInterval: hero.event.time...hero.event.time.addingTimeInterval(86_400),
              countsDown: false, showsHours: true)
          }
        }
        .foregroundStyle(style.mark)
      } else {
        Group {
          if let pause {
            still(hero.event.time.timeIntervalSince(pause))
          } else {
            Text(
              timerInterval: date...max(date, hero.event.time), countsDown: true,
              showsHours: true)
          }
        }
        .foregroundStyle(style.accent)
        .widgetAccentable()
      }
    }
    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    .lineBox(lineHeight)
  }

  /// The countdown's line height: 34 for the 28-point timer, 28 for the 22-point one.
  private var lineHeight: CGFloat { size >= 28 ? 34 : 28 }

  /// The timer's reading at the pause, as the live timer shows it: `2:16:00`, or `10:00`
  /// under an hour. A paused timer text doesn't render it in a still.
  private func still(_ seconds: TimeInterval) -> Text {
    let seconds = max(seconds, 0).rounded(.down)
    let duration = Duration.seconds(seconds)
    let pattern: Duration.TimeFormatStyle.Pattern =
      seconds >= 3600 ? .hourMinuteSecond(padHourToLength: 1) : .minuteSecond(padMinuteToLength: 1)
    return Text(verbatim: duration.formatted(.time(pattern: pattern).locale(locale)))
  }
}

/// A prayer's glyph in the time of day's mark.
private struct WidgetGlyph: View {
  let kind: PrayerKind
  var observance: PrayerObservance = .ordinary
  let side: CGFloat
  let style: WidgetStyle

  var body: some View {
    PrayerGlyph(kind: kind, observance: observance)
      .font(.system(size: WidgetMetrics.glyphFontSize(side: side)))
      .foregroundStyle(style.mark)
      .frame(width: side, height: side)
      .accessibilityHidden(true)
  }
}

/// Salah's glyph for a prayer or sunrise: a custom symbol from the asset catalog, which
/// sizes with `.font` and tints with the foreground style.
nonisolated struct PrayerGlyph: View {
  let kind: PrayerKind
  var observance: PrayerObservance = .ordinary

  var assetName: String {
    kind == .dhuhr && observance == .jumuah ? "salah.jumuah" : "salah.\(kind.rawValue)"
  }

  var body: some View {
    Image(assetName, bundle: AppResources.bundle)
      .symbolRenderingMode(.hierarchical)
  }
}

/// The eyebrow above the name: "Next prayer", "Tomorrow", or "Now" after a prayer began.
private struct WidgetEyebrow: View {
  let hero: WidgetHero
  let style: WidgetStyle
  /// The small face shows "Now" as a badge; the larger ones as text in the mark.
  var badge = false

  var body: some View {
    if hero.kind == .justStarted, badge {
      Text(verbatim: hero.eyebrow)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(style.onBadge)
        .lineBox(13)
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .background(Capsule().fill(style.badge))
    } else {
      Text(verbatim: hero.eyebrow)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(hero.kind == .justStarted ? style.mark : style.secondary)
        .lineLimit(1)
        .lineBox(13)
    }
  }
}

/// The line under the timer: "at 3:35 PM", or "Next: Asr 3:35 PM" after a prayer began.
private struct WidgetFooter: View {
  let hero: WidgetHero
  let style: WidgetStyle

  var body: some View {
    Text(verbatim: hero.footer)
      .font(.system(size: 12))
      .foregroundStyle(style.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .lineBox(16)
  }
}

/// The medium face's hairline beside the times, as tall as the design draws it.
private struct WidgetHairline: View {
  let style: WidgetStyle

  var body: some View {
    Rectangle()
      .fill(style.separator)
      .frame(width: 1, height: WidgetMetrics.mediumHairlineHeight)
  }
}

private struct SmallFace: View {
  let display: SalahDisplay
  let hero: WidgetHero?
  let style: WidgetStyle

  var body: some View {
    if let hero {
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          WidgetEyebrow(hero: hero, style: style, badge: true)
          Spacer(minLength: 4)
          WidgetGlyph(
            kind: hero.event.kind, observance: hero.event.observance, side: 26, style: style)
        }
        Spacer(minLength: 0)
        Text(verbatim: hero.name)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(style.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .lineBox(28)
        WidgetTimer(hero: hero, date: display.date, size: 22, style: style)
        WidgetFooter(hero: hero, style: style)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 15)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    } else {
      WidgetUnknownFace(display: display, style: style)
    }
  }
}

private struct MediumFace: View {
  let display: SalahDisplay
  let hero: WidgetHero?
  let style: WidgetStyle

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Group {
        if let hero {
          VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
              WidgetGlyph(
                kind: hero.event.kind, observance: hero.event.observance, side: 22, style: style)
              WidgetEyebrow(hero: hero, style: style)
            }
            Text(verbatim: hero.name)
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(style.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
              .lineBox(28)
            WidgetTimer(hero: hero, date: display.date, size: 22, style: style)
            WidgetFooter(hero: hero, style: style)
          }
        } else {
          WidgetUnknownFace(display: display, style: style)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      WidgetHairline(style: style)
      WidgetTimes(display: display, rowHeight: 21, nameSize: 13, style: style)
        .frame(width: 132)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 15)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct LargeFace: View {
  let display: SalahDisplay
  let hero: WidgetHero?
  let style: WidgetStyle

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      WidgetHeader(display: display, style: style)
      if let hero {
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 6) {
            WidgetGlyph(
              kind: hero.event.kind, observance: hero.event.observance, side: 22, style: style)
            WidgetEyebrow(hero: hero, style: style)
          }
          Text(verbatim: hero.name)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(style.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .lineBox(34)
          WidgetTimer(hero: hero, date: display.date, size: 28, style: style)
          WidgetFooter(hero: hero, style: style)
        }
        WidgetProgress(display: display, style: style)
      } else {
        WidgetUnknownFace(display: display, style: style)
      }
      WidgetTimes(display: display, rowHeight: 26, nameSize: 15, style: style)
    }
    .topAligned()
    .padding(.horizontal, 16)
    .padding(.vertical, 15)
  }
}

/// The extra-large face: a column with the date and place, the next prayer and its timer
/// side by side, and the sun arc; a hairline; and the day's times, centered beside it.
private struct ExtraLargeFace: View {
  let display: SalahDisplay
  let hero: WidgetHero?
  let style: WidgetStyle

  var body: some View {
    ExtraLargeLayout(display: display, style: style) {
      if let hero {
        Text(verbatim: hero.eyebrow)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(hero.kind == .justStarted ? style.mark : style.secondary)
          .lineLimit(1)
          .lineBox(16)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text(verbatim: hero.name)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(style.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .lineBox(34)
          WidgetTimer(hero: hero, date: display.date, size: 28, style: style)
            .frame(width: 170, alignment: .leading)
        }
      } else {
        WidgetUnknownFace(display: display, style: style)
      }
    }
  }
}

/// The extra-large design fits inside the host's finite proposal, without unbounded columns.
nonisolated struct ExtraLargeWidgetMetrics {
  let leadingWidth: CGFloat
  let contentHeight: CGFloat
  let separatorHeight: CGFloat
  let arcScale: CGFloat

  init(size: CGSize) {
    leadingWidth = max(0, size.width - 40 - 40 - 1 - 220)
    contentHeight = max(0, size.height - 36)
    separatorHeight = min(300, contentHeight)
    arcScale = min(0.98, leadingWidth / SunArcLayout.size.width)
  }
}

/// The extra-large frame both its faces share; `hero` goes between the header and the arc.
private struct ExtraLargeLayout<Hero: View>: View {
  let display: SalahDisplay
  let style: WidgetStyle
  @ViewBuilder let hero: () -> Hero

  var body: some View {
    GeometryReader { proxy in
      let metrics = ExtraLargeWidgetMetrics(size: proxy.size)
      HStack(alignment: .top, spacing: 20) {
        VStack(alignment: .leading, spacing: 2) {
          ExtraLargeHeader(display: display, style: style)
          hero()
          WidgetSunArc(display: display, style: style, scale: metrics.arcScale)
        }
        .frame(width: metrics.leadingWidth, height: metrics.contentHeight, alignment: .topLeading)
        Rectangle()
          .fill(style.separator)
          .frame(width: 1, height: metrics.separatorHeight)
        WidgetTimes(display: display, rowHeight: 38, nameSize: 17, style: style, isExtraLarge: true)
          .frame(width: 220, height: metrics.contentHeight)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 18)
    }
  }
}

/// The extra-large face's header: "16 Dhuʻl-Hijjah 1447 · Makkah".
private struct ExtraLargeHeader: View {
  let display: SalahDisplay
  let style: WidgetStyle

  var body: some View {
    let header = display.header
    let year = header.hijriYear
    // One line that scales as one, as the design sets it; a redacted widget hides it whole.
    Text(
      verbatim: "\(header.hijriDay) \(header.hijriMonth) \(year) · \(header.location)"
    )
    .font(.system(size: 15, weight: .semibold))
    .foregroundStyle(style.primary)
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .lineBox(20)
    .privacySensitive()
  }
}

/// The large face's header: the Hijri date, and the place.
private struct WidgetHeader: View {
  let display: SalahDisplay
  let style: WidgetStyle

  var body: some View {
    let header = display.header
    let year = header.hijriYear
    HStack(spacing: 6) {
      Text(verbatim: "\(header.hijriDay) \(header.hijriMonth) \(year)")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(style.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .lineBox(20)
      Spacer(minLength: 6)
      Image(systemName: "location.fill")
        .font(.system(size: 10))
        .foregroundStyle(style.secondary)
        .accessibilityHidden(true)
      Text(verbatim: header.location)
        .font(.system(size: 12))
        .foregroundStyle(style.secondary)
        .lineLimit(1)
        .lineBox(16)
        .privacySensitive()
    }
    .accessibilityElement(children: .combine)
  }
}

/// Progress from the previous prayer to the next, in the time of day's mark.
private struct WidgetProgress: View {
  let display: SalahDisplay
  let style: WidgetStyle

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Capsule().fill(style.track)
        Capsule().fill(style.mark)
          .frame(width: proxy.size.width * fraction)
      }
    }
    .frame(height: 4)
    .accessibilityHidden(true)
  }

  /// From the prayer one is in to the next. While a prayer plays, from that prayer to the
  /// listed one after it, so Stop looks the same when later times are unavailable.
  private var fraction: CGFloat {
    let start: Date
    let end: Date
    if let playing = display.playingPrayer {
      guard let next = display.listedDay?.events.first(where: { $0.time > playing.time })
      else { return 0 }
      (start, end) = (playing.time, next.time)
    } else {
      guard let state = display.prayerState, let next = state.next else { return 0 }
      (start, end) = (state.previous?.time ?? display.date, next.time)
    }
    let span = end.timeIntervalSince(start)
    guard span > 0 else { return 0 }
    return CGFloat(min(max(display.date.timeIntervalSince(start) / span, 0), 1))
  }
}

/// The day's six times (tomorrow's after Isha): passed ones step back, the prayer one is
/// in carries the mark, and the next one the accent on a wash.
nonisolated struct WidgetTimes: View {
  let display: SalahDisplay
  let rowHeight: CGFloat
  let nameSize: CGFloat
  let style: WidgetStyle
  /// The extra-large face's rows: 17-point full times ("4:11 AM"), wider insets and
  /// corners, and the next row's time in semibold too.
  var isExtraLarge = false

  enum Role { case passed, current, next, upcoming }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(rows, id: \.event.id) { row in
        HStack(spacing: isExtraLarge ? 8 : 6) {
          Text(verbatim: display.name(of: row.event))
            .font(.system(size: nameSize, weight: isStrong(row.role) ? .semibold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(verbatim: timeText(row.event.time))
            .font(
              .system(
                size: isExtraLarge ? 17 : 13,
                weight: isExtraLarge && isStrong(row.role) ? .semibold : .regular
              )
              .monospacedDigit()
            )
            .lineLimit(1)
            // The smaller faces drop the day period; VoiceOver says it: "5:03 AM".
            .accessibilityLabel(
              Text(verbatim: display.text.timeFormatter().string(from: row.event.time)))
        }
        .foregroundStyle(color(row.role))
        .padding(.horizontal, isExtraLarge ? 10 : 6)
        .frame(height: rowHeight)
        .background {
          if row.role == .next {
            RoundedRectangle(cornerRadius: isExtraLarge ? 10 : 7, style: .continuous)
              .fill(style.track)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func isStrong(_ role: Role) -> Bool { role == .current || role == .next }

  /// "4:11" in the rows, or "4:11 AM" in the extra-large face's.
  private func timeText(_ time: Date) -> String {
    isExtraLarge
      ? display.text.timeFormatter().string(from: time) : display.text.compactTime(time)
  }

  private func color(_ role: Role) -> AnyShapeStyle {
    switch role {
    case .passed: style.tertiary
    case .current: style.mark
    case .next: style.accent
    case .upcoming: style.primary
    }
  }

  private var rows: [(event: PrayerEvent, role: Role)] { Self.rows(of: display) }

  /// The listed day's events with their roles, or tomorrow's while its Fajr is next and
  /// none of today's prayers plays.
  static func rows(of display: SalahDisplay) -> [(event: PrayerEvent, role: Role)] {
    let day = display.listedDay
    let playing = display.playingPrayer.flatMap { event in
      day?.events.contains { $0.id == event.id } == true ? event : nil
    }
    // Tomorrow's times after Isha, unless one of today's prayers still plays.
    if playing == nil, display.focusIsTomorrow, let tomorrow = display.nextDay {
      return tomorrow.events.map { ($0, $0.id == display.focus?.event.id ? .next : .upcoming) }
    }
    guard let day else { return [] }
    if let playing {
      // While a prayer plays, the roles follow it, whatever the countdown knows.
      let next = day.events.first { $0.time > playing.time }
      return day.events.map { event in
        if event.id == playing.id { return (event, .current) }
        if event.id == next?.id { return (event, .next) }
        return (event, event.time < playing.time ? .passed : .upcoming)
      }
    }
    let state = display.prayerState
    return day.events.map { event in
      switch state?.status(of: event) {
      case .justStarted?: return (event, .current)
      case .next?: return (event, .next)
      case .upcoming?: return (event, .upcoming)
      case .passed?: return (event, .passed)
      case nil: return (event, event.time <= display.date ? .passed : .upcoming)
      }
    }
  }
}

/// In the hero's place when the next prayer's time isn't known.
private struct WidgetUnknownFace: View {
  let display: SalahDisplay
  let style: WidgetStyle

  var body: some View {
    Label {
      Text(verbatim: display.labels.nextUnknown).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: "questionmark.circle")
    }
    .font(.system(size: 13, weight: .semibold))
    .foregroundStyle(style.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Message

/// The face for setup, an expired timeline, or times that aren't available: a symbol and
/// what to do. The shell links it to Salah.
struct WidgetMessageContent: View {
  let systemImage: String
  let message: Text
  var phase: SalahPhase = .neutral

  var body: some View {
    StyledFace(phase: phase) { style in
      VStack(spacing: 8) {
        Image(systemName: systemImage)
          .font(.system(size: 26))
          .foregroundStyle(style.accent)
          .widgetAccentable()
          .frame(width: 30, height: 30)
          .accessibilityHidden(true)
        message
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(style.primary)
          .multilineTextAlignment(.center)
          .designLineHeight(18, fontSize: 13, weight: .semibold)
          .frame(width: 132)
          .minimumScaleFactor(0.8)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 15)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

// MARK: - Stop

/// While the adhan, the du'a or a reminder plays, every face becomes Stop. The shell makes
/// the whole widget the Stop button. The small face is Stop alone; the larger ones keep the
/// day's times beside or beneath it.
struct WidgetStopContent: View {
  let display: SalahDisplay
  let size: SalahWidgetSize

  init?(display: SalahDisplay, size: SalahWidgetSize) {
    guard display.playback != nil else { return nil }
    self.display = display
    self.size = size
  }

  var body: some View {
    StyledFace(phase: display.phase) { style in
      switch size {
      case .small:
        VStack(spacing: 4) {
          stopSymbol(side: 50, style: style)
          title(size: 17, style: style)
          tapToStop(style: style)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .medium:
        HStack(alignment: .top, spacing: 14) {
          hero(side: 34, titleSize: 17, style: style)
            .frame(maxWidth: .infinity, alignment: .leading)
          WidgetHairline(style: style)
          WidgetTimes(display: display, rowHeight: 21, nameSize: 13, style: style)
            .frame(width: 132)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      case .extraLarge:
        // No design of its own: the extra-large layout, with the Stop control in the
        // place of the next prayer.
        ExtraLargeLayout(display: display, style: style) {
          hero(side: 40, titleSize: 20, style: style)
        }
      case .large:
        VStack(alignment: .leading, spacing: 9) {
          WidgetHeader(display: display, style: style)
          hero(side: 40, titleSize: 20, style: style)
          WidgetProgress(display: display, style: style)
          WidgetTimes(display: display, rowHeight: 26, nameSize: 15, style: style)
        }
        .topAligned()
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: "\(prayerName). \(display.labels.tapToStop)"))
  }

  private var prayerName: String {
    display.playback.map { display.name(of: $0.event) } ?? ""
  }

  /// The eyebrow and the Stop control: "Playing adhan", then Stop with the prayer's name.
  private func hero(side: CGFloat, titleSize: CGFloat, style: WidgetStyle) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 6) {
        if let event = display.playback?.event {
          WidgetGlyph(kind: event.kind, observance: event.observance, side: 22, style: style)
        }
        Text(verbatim: display.playingTitle ?? "")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(style.secondary)
          .lineLimit(1)
          .lineBox(13)
      }
      HStack(spacing: 6) {
        stopSymbol(side: side, style: style)
        VStack(alignment: .leading, spacing: 0) {
          title(size: titleSize, style: style)
          tapToStop(style: style)
        }
      }
      .padding(.top, 6)
    }
  }

  private func stopSymbol(side: CGFloat, style: WidgetStyle) -> some View {
    let diameter = WidgetMetrics.stopDiameter(side: side)
    return Image(systemName: "stop.circle.fill")
      .resizable()
      .frame(width: diameter, height: diameter)
      .frame(width: side, height: side)
      .foregroundStyle(style.accent)
      .widgetAccentable()
      .accessibilityHidden(true)
  }

  private func title(size: CGFloat, style: WidgetStyle) -> some View {
    Text(verbatim: prayerName)
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(style.primary)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      // The design's line heights: 22 for the 17-point title, 25 for the 20-point one.
      .lineBox(size >= 20 ? 25 : 22)
  }

  private func tapToStop(style: WidgetStyle) -> some View {
    Text(verbatim: display.labels.tapToStop)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(style.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .lineBox(16)
  }
}
