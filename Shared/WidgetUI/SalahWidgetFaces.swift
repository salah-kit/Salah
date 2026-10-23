import SalahCore
import SalahUI
import SwiftUI
import WidgetKit

// MARK: - Sizes

/// The widget sizes Salah supports.
nonisolated enum SalahWidgetSize: Sendable, Hashable {
  case small
  case medium
  case large
}

nonisolated extension SalahWidgetSize {
  /// The point size of each family on the desktop, as measured on macOS 27.0.1, for the
  /// previews and the visual baselines; the extension takes its host's actual bounds.
  var desktopPointSize: CGSize {
    switch self {
    case .small: CGSize(width: 164, height: 164)
    case .medium: CGSize(width: 344, height: 164)
    case .large: CGSize(width: 344, height: 344)
    }
  }
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
  /// `widget/accent`: the one accentable element, the countdown or the next row.
  var accent: AnyShapeStyle { token(colors.palette.accentText, else: .primary) }
  /// `widget/mark`: glyphs, the progress bar, the prayer one is in.
  var mark: AnyShapeStyle { token(colors.phase.tint, else: .secondary) }
  /// `widget/track`: the progress bar's track and the next row's wash.
  var track: AnyShapeStyle { token(colors.palette.fillSecondary, else: .quaternary) }
  /// `widget/separator`.
  var separator: AnyShapeStyle { token(colors.palette.separator, else: .quaternary) }
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
  }

  /// The timer's reading at the pause, as the live timer shows it: `2:16:00`. A paused
  /// timer text doesn't render it in a still.
  private func still(_ seconds: TimeInterval) -> Text {
    let duration = Duration.seconds(max(seconds, 0).rounded(.down))
    return Text(
      verbatim: duration.formatted(
        .time(pattern: .hourMinuteSecond(padHourToLength: 1)).locale(locale)))
  }
}

/// A prayer's glyph in the time of day's mark.
private struct WidgetGlyph: View {
  let kind: PrayerKind
  let side: CGFloat
  let style: WidgetStyle

  var body: some View {
    PrayerGlyph(kind: kind)
      .font(.system(size: side * 0.8))
      .foregroundStyle(style.mark)
      .frame(width: side, height: side)
      .accessibilityHidden(true)
  }
}

/// Salah's glyph for a prayer or sunrise: a custom symbol from the asset catalog, which
/// sizes with `.font` and tints with the foreground style.
nonisolated struct PrayerGlyph: View {
  let kind: PrayerKind

  var body: some View {
    Image("salah.\(kind.rawValue)", bundle: AppResources.bundle)
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
        .padding(.horizontal, 7)
        .padding(.vertical, 1)
        .background(Capsule().fill(style.badge))
    } else {
      Text(verbatim: hero.eyebrow)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(hero.kind == .justStarted ? style.mark : style.secondary)
        .lineLimit(1)
    }
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
          WidgetGlyph(kind: hero.event.kind, side: 26, style: style)
        }
        Spacer(minLength: 0)
        Text(verbatim: hero.name)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(style.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        WidgetTimer(hero: hero, date: display.date, size: 22, style: style)
        Text(verbatim: hero.footer)
          .font(.system(size: 12))
          .foregroundStyle(style.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
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
              WidgetGlyph(kind: hero.event.kind, side: 22, style: style)
              WidgetEyebrow(hero: hero, style: style)
            }
            Text(verbatim: hero.name)
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(style.primary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
            WidgetTimer(hero: hero, date: display.date, size: 22, style: style)
            Text(verbatim: hero.footer)
              .font(.system(size: 12))
              .foregroundStyle(style.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        } else {
          WidgetUnknownFace(display: display, style: style)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Rectangle()
        .fill(style.separator)
        .frame(width: 1)
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
            WidgetGlyph(kind: hero.event.kind, side: 22, style: style)
            WidgetEyebrow(hero: hero, style: style)
          }
          Text(verbatim: hero.name)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(style.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          WidgetTimer(hero: hero, date: display.date, size: 28, style: style)
          Text(verbatim: hero.footer)
            .font(.system(size: 12))
            .foregroundStyle(style.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        WidgetProgress(display: display, style: style)
      } else {
        WidgetUnknownFace(display: display, style: style)
      }
      WidgetTimes(display: display, rowHeight: 26, nameSize: 15, style: style)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 15)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

/// The large face's header: the Hijri date, and the place.
private struct WidgetHeader: View {
  let display: SalahDisplay
  let style: WidgetStyle

  var body: some View {
    let header = display.header
    HStack(spacing: 6) {
      Text(verbatim: "\(header.hijriDay) \(header.hijriMonth) \(header.hijriYear)")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(style.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Spacer(minLength: 6)
      Image(systemName: "location.fill")
        .font(.system(size: 10))
        .foregroundStyle(style.secondary)
        .accessibilityHidden(true)
      Text(verbatim: header.location)
        .font(.system(size: 12))
        .foregroundStyle(style.secondary)
        .lineLimit(1)
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
    if let playing = display.playback?.event {
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

  enum Role { case passed, current, next, upcoming }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(rows, id: \.event.id) { row in
        HStack(spacing: 6) {
          Text(verbatim: display.name(of: row.event))
            .font(.system(size: nameSize, weight: isStrong(row.role) ? .semibold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(verbatim: display.text.compactTime(row.event.time))
            .font(.system(size: 13).monospacedDigit())
            .lineLimit(1)
        }
        .foregroundStyle(color(row.role))
        .padding(.horizontal, 6)
        .frame(height: rowHeight)
        .background {
          if row.role == .next {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(style.track)
          }
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  private func isStrong(_ role: Role) -> Bool { role == .current || role == .next }

  private func color(_ role: Role) -> AnyShapeStyle {
    switch role {
    case .passed: style.tertiary
    case .current: style.mark
    case .next: style.accent
    case .upcoming: style.primary
    }
  }

  /// The listed day's events with their roles, or tomorrow's while its Fajr is next.
  private var rows: [(event: PrayerEvent, role: Role)] {
    if display.focusIsTomorrow, let tomorrow = display.nextDay {
      return tomorrow.events.map { ($0, $0.id == display.focus?.event.id ? .next : .upcoming) }
    }
    guard let day = display.listedDay else { return [] }
    if let playing = display.playback?.event {
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
          .accessibilityHidden(true)
        message
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(style.primary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 140)
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
          Rectangle().fill(style.separator).frame(width: 1)
          WidgetTimes(display: display, rowHeight: 21, nameSize: 13, style: style)
            .frame(width: 132)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      case .large:
        VStack(alignment: .leading, spacing: 9) {
          WidgetHeader(display: display, style: style)
          hero(side: 40, titleSize: 20, style: style)
          WidgetProgress(display: display, style: style)
          WidgetTimes(display: display, rowHeight: 26, nameSize: 15, style: style)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        if let kind = display.playback?.event.kind {
          WidgetGlyph(kind: kind, side: 22, style: style)
        }
        Text(verbatim: display.playingTitle ?? "")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(style.secondary)
          .lineLimit(1)
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
    Image(systemName: "stop.circle.fill")
      .resizable()
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
  }

  private func tapToStop(style: WidgetStyle) -> some View {
    Text(verbatim: display.labels.tapToStop)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(style.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
  }
}
