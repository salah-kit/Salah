import SalahCore
import SalahUI
import SwiftUI
import WidgetKit

// MARK: - Tight label style

/// A `Label` layout with a small, fixed icon-title gap. SwiftUI's default
/// `.titleAndIcon` spacing - plus an SF Symbol's own side bearing - reads as a
/// loose, "floating" gap, most visible in RTL. This pins the gap so the glyph
/// hugs its text. Used for every icon + text pairing in the widget chrome.
nonisolated struct TightLabelStyle: LabelStyle {
  var spacing: CGFloat = 3
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: spacing) {
      configuration.icon
      configuration.title
    }
  }
}

nonisolated extension LabelStyle where Self == TightLabelStyle {
  static var tight: TightLabelStyle { TightLabelStyle() }
}

// MARK: - Top-level idle content

/// The idle "living schedule" - the same hierarchy at three densities. Renders
/// purely from a display, so both the widget extension (idle branch) and the in-app
/// Appearance preview use it unchanged. Setup, expired, unavailable and the
/// playing/stop state are handled by the extension shell (they need `widgetURL` /
/// `Button(intent:)`), with their content below.
///
/// The day's rows are SalahUI's `PrayerTimesList` in Salah's row style, and the focus
/// is SalahUI's `NextPrayerView` in Salah's focus style.
nonisolated struct WidgetContentView: View {
  let display: SalahDisplay
  let size: SalahWidgetSize
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let colors = display.theme.colors(for: scheme)
    switch size {
    case .small: SmallContent(display: display, colors: colors)
    case .medium: MediumContent(display: display, colors: colors)
    case .large: LargeContent(display: display, colors: colors)
    }
  }
}

// MARK: - Header

/// Date + location, on top of every size. `full` shows Hijri day/month/year with
/// the Gregorian date beneath; `compact` drops the year and Gregorian line.
private struct WidgetHeader: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  var compact: Bool = false
  var showLocation: Bool = true

  private var header: SalahHeader { display.header }
  private var silentMode: Bool { display.settings.silentMode }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Image(systemName: silentMode ? "bell.slash.fill" : "moon.stars.fill")
          .font(compact ? .caption : .subheadline)
          .salahInk(silentMode ? SalahWidgetInk.secondary.glyph : SalahWidgetInk.accent.glyph)
          // Optically pull the Hijri date toward the glyph: `moon.stars.fill`
          // carries empty side-bearing that otherwise reads as a stray gap.
          .padding(.trailing, -2)
          .accessibilityHidden(true)
        Text(verbatim: hijriText)
          .font(.system(compact ? .subheadline : .headline, design: .serif, weight: .semibold))
          .salahInk(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Spacer(minLength: 8)
        if showLocation {
          Label {
            Text(verbatim: header.location)
              .lineLimit(1)
              .privacySensitive()
          } icon: {
            Image(systemName: "location.fill")
          }
          .font(.caption)
          .salahInk(.secondary)
          .labelStyle(.tight)
        }
      }
      if !compact {
        Text(verbatim: header.gregorianDate)
          .font(.caption2)
          .salahInk(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var hijriText: String {
    compact
      ? "\(header.hijriDay) \(header.hijriMonth)"
      : "\(header.hijriDay) \(header.hijriMonth) \(header.hijriYear)"
  }
}

// MARK: - Relative countdown / count-up

/// Relative time for the focus timer. At a minute or more it is a **static**,
/// minute-resolution string (SalahCore's `PrayerDurationFormat`) advanced by the
/// timeline - calm, never the per-second churn of `Text(_, style: .relative)` across
/// a whole hour. In the final minute of a countdown, and the first minute of a
/// count-up, it switches to Apple's system timer text, the one widget primitive that
/// ticks per-second on its own (no timeline cost); that renders "0:45", not the menu
/// bar's custom "45s". The timeline has an entry a minute before each prayer and at
/// it, so both live minutes start on an entry. Count-up is prefixed "+".
/// Arabic-Indic digits come from the locale environment the shell installs.
private struct RelativeTime: View {
  /// The prayer time - in the future for a count-down, in the past for a count-up.
  let target: Date
  /// The moment this view represents: the timeline entry's date in the widget,
  /// or "now" in the in-app preview.
  let reference: Date
  let ink: SalahWidgetInk
  let font: Font
  var bold: Bool = false
  var countingUp: Bool = false
  @Environment(\.locale) private var locale

  var body: some View {
    let magnitude = abs(target.timeIntervalSince(reference))
    Group {
      if countingUp ? magnitude < 60 : magnitude <= 60 {
        // The live minute: the system timer text the host ticks per-second for
        // free. `countsDown` is set explicitly (not inferred from past/future)
        // so the direction is exact. Renders "0:45".
        if countingUp {
          HStack(spacing: 0) {
            Text(verbatim: "+")
            Text(
              timerInterval: target...target.addingTimeInterval(3600),
              countsDown: false, showsHours: false)
          }
        } else {
          Text(
            timerInterval: reference...max(reference, target),
            countsDown: true, showsHours: false)
        }
      } else {
        // Otherwise the calm, static, timeline-advanced tier string.
        Text(
          verbatim: PrayerDurationFormat.string(
            magnitude, direction: countingUp ? .elapsed : .remaining, locale: locale))
      }
    }
    .font(bold ? font.weight(.bold) : font)
    .monospacedDigit()
    .salahInk(ink)
    .lineLimit(1)
    .minimumScaleFactor(0.6)
  }
}

// MARK: - Schedule rows

/// Salah's look for one row of SalahUI's `PrayerTimesList`: alert bell + name +
/// time. `full` (large) carries an icon and a state background; `compact` (medium)
/// is a light name+time line. The next prayer is toned, the current (count-up)
/// prayer is green, passed prayers dim. On the large widget the focus row expands in
/// place into the active card.
private struct SalahRowStyle: PrayerRowStyle {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  var compact: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    if let event = configuration.event {
      if !compact, display.focus?.event.id == event.id, let state = display.prayerState {
        FocusView(state: state, display: display, colors: colors, size: .large)
          .layoutPriority(1)
      } else {
        ScheduleRowView(
          name: configuration.name, time: configuration.time ?? Text(verbatim: "–"),
          state: display.rowState(for: event, status: configuration.status),
          icon: .event(isSunrise: event.kind == .sunrise, alert: display.alerts(for: event).alert),
          colors: colors, nowLabel: display.labels.now, compact: compact,
          sinceText: display.sinceText(for: event, status: configuration.status)
        )
        .frame(maxHeight: .infinity)
      }
    } else {
      ScheduleRowView(
        name: configuration.name, time: Text(verbatim: "–"), state: .upcoming,
        icon: .missing, colors: colors, nowLabel: display.labels.now, compact: compact,
        timeAccessibilityLabel: display.labels.notAvailable
      )
      .frame(maxHeight: .infinity)
    }
  }
}

/// The package supplies known and missing rows as direct children of Salah's stack.
private struct ScheduleRows: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  var compact: Bool = false
  var spacing: CGFloat = 0

  var body: some View {
    VStack(spacing: spacing) {
      if case .available(let day, let coverage) = display.day {
        let missing: [PrayerKind: ScheduleGapReason] = {
          if case .partial(let missing) = coverage { return missing }
          return [:]
        }()
        PrayerTimesList(
          day: day, state: display.prayerState, names: display.names,
          countdown: .staticText, missing: missing
        ).rows
      }
    }
    .prayerRowStyle(SalahRowStyle(display: display, colors: colors, compact: compact))
  }
}

/// One collapsed prayer: alert bell + name + time. `full` (large) carries an icon
/// and a state background; `compact` (medium) is a light name+time line.
private struct ScheduleRowView: View {
  enum Icon {
    case event(isSunrise: Bool, alert: Bool)
    /// A prayer the calculation can't give today.
    case missing
  }

  let name: Text
  let time: Text
  let state: SalahWidgetRowState
  let icon: Icon
  let colors: SalahWidgetColors
  let nowLabel: String
  var compact: Bool = false
  /// The most-recent-passed "since previous prayer" count-up ("+1:30"), shown on
  /// the trailing edge. Its presence also keeps this row un-dimmed - the "you are
  /// here" anchor between passed and upcoming.
  var sinceText: String? = nil
  /// What VoiceOver reads for the time, when the visible time isn't words.
  var timeAccessibilityLabel: String? = nil
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    HStack(spacing: compact ? 6 : 10) {
      if !compact {
        Image(systemName: iconName)
          .font(.subheadline)
          .salahInk(ink(emphasisInk?.glyph ?? SalahWidgetInk.secondary.glyph))
          .frame(width: 20)
          .accessibilityHidden(true)
      }

      name
        .font(.system(compact ? .subheadline : .body, design: .serif).weight(weight))
        .salahInk(ink(emphasisInk ?? (isQuieted ? .secondary : .primary)))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(minWidth: compact ? nil : 62, alignment: .leading)

      if isCurrent {
        InlineBadge(
          text: nowLabel, tint: SalahWidgetTone.prayerColor(colors),
          ink: SalahWidgetInk.tone(.playingPrayerAudio).on(
            .playingPrayerAudio,
            opacity: SalahWidgetTint.stacked(
              SalahWidgetTint.badge, over: compact ? 0 : SalahWidgetTint.currentRow)))
      }

      Spacer(minLength: 6)

      // The "since" count-up floats in the gap (between name and time) rather
      // than after the time, so the time stays in the same right-aligned column
      // as every other row instead of being pushed off when this row carries it.
      if let sinceText {
        Text(verbatim: sinceText)
          .font((compact ? Font.caption : Font.subheadline).monospacedDigit())
          .salahInk(ink(.tone(.playingPrayerAudio)))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .layoutPriority(-1)
        Spacer(minLength: 6)
      }

      time
        .font((compact ? Font.subheadline : Font.body).monospacedDigit())
        .salahInk(ink(timeInk))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(minWidth: compact ? nil : 82, alignment: .trailing)
        .accessibilityLabel(timeAccessibilityLabel.map { Text(verbatim: $0) } ?? time)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, compact ? 0 : 10)
    .padding(.vertical, compact ? 0 : 4)
    .background(compact ? AnyView(Color.clear) : AnyView(rowBackground))
    .accessibilityElement(children: .combine)
  }

  private var isCurrent: Bool { state == .current }

  /// Passed rows step back, except the "you are here" row; so does a prayer the
  /// calculation can't give.
  private var isPassed: Bool {
    if case .missing = icon { return true }
    return state == .passed && sinceText == nil
  }

  /// With Increase Contrast, a passed row draws in the secondary ink, undimmed, so its
  /// text keeps 4.5:1.
  private var isQuieted: Bool { isPassed && contrast == .increased }

  /// Passed rows dim to 50% (55% on large) in standard contrast, as the widget has always
  /// drawn them. That's a documented exception to 4.5:1 (`Design/README.md`, Widgets): on
  /// the presets, medium rows' names measure 2.9-4.0:1 and their times 1.95-2.6:1, large
  /// rows' names and times 3.2-4.8:1 and their bells 2.2-2.9:1. `WidgetInkContrastTests`
  /// holds them to 1.9:1.
  private var dimming: Double {
    guard isPassed, contrast != .increased else { return 1 }
    return compact ? 0.5 : 0.55
  }

  /// The tint under a large row's content, its state fill, and the fill's strongest
  /// opacity.
  private var tint: (tone: SalahWidgetTone, opacity: Double)? {
    guard !compact else { return nil }
    switch state {
    case .next(let tone): return (tone, SalahWidgetTint.nextRow)
    case .active(let tone): return (tone, SalahWidgetTint.activeRow)
    case .current: return (.playingPrayerAudio, SalahWidgetTint.currentRow)
    default: return nil
    }
  }

  /// `ink` on the row's tint, dimmed as the row is.
  private func ink(_ ink: SalahWidgetInk) -> SalahWidgetInk {
    ink.on(tint?.tone, opacity: tint?.opacity ?? 0).dimmed(dimming)
  }

  /// Emphasis ink for the name (and icon, full only): next→tone, active→tone,
  /// current→green; nil means use the default text ink.
  private var emphasisInk: SalahWidgetInk? {
    switch state {
    case .next(let tone), .active(let tone): return .tone(tone)
    case .current: return .tone(.playingPrayerAudio)
    default: return nil
    }
  }

  private var timeInk: SalahWidgetInk {
    switch state {
    case .next(let tone): return .tone(tone)
    case .current: return .tone(.playingPrayerAudio)
    default: return compact || isQuieted ? .secondary : .primary
    }
  }

  private var weight: Font.Weight {
    switch state {
    case .next, .active, .current: return .semibold
    default: return .regular
    }
  }

  private var iconName: String {
    switch state {
    case .active: return "speaker.wave.2.fill"
    // `.forward` auto-mirrors under RTL, unlike `.right`.
    case .next: return "arrowtriangle.forward.fill"
    default:
      switch icon {
      case .missing: return "questionmark.circle"
      case .event(let isSunrise, let alert):
        if isSunrise { return "sunrise.fill" }
        return alert ? "bell.fill" : "bell.slash"
      }
    }
  }

  @ViewBuilder
  private var rowBackground: some View {
    switch state {
    case .next(let tone):
      let c = tone.color(colors)
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              c.opacity(SalahWidgetTint.nextRow), c.opacity(SalahWidgetTint.nextRowTrailing),
            ],
            startPoint: .leading, endPoint: .trailing)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(c.opacity(0.45), lineWidth: 1)
        )
    case .active(let tone):
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(tone.color(colors).opacity(SalahWidgetTint.activeRow))
    case .current:
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(SalahWidgetTone.prayerColor(colors).opacity(SalahWidgetTint.currentRow))
    default:
      Color.clear
    }
  }
}

// MARK: - Active card (the focus)

/// The focus, SalahUI's `NextPrayerView` in Salah's focus style.
private struct FocusView: View {
  let state: PrayerState
  let display: SalahDisplay
  let colors: SalahWidgetColors
  let size: SalahWidgetSize
  var distribute: Bool = false

  var body: some View {
    NextPrayerView(
      state: state, names: display.names, timeZone: display.settings.location.timeZone,
      countdown: .staticText, selection: .justStartedOrNextEvent
    )
    .nextPrayerStyle(
      SalahFocusStyle(display: display, colors: colors, size: size, distribute: distribute))
  }
}

/// Salah's look for the focus, in one of three modes: count-down (the next event,
/// sunrise included), count-up (green, 15 min after a prayer starts), or tomorrow
/// (end-of-day Fajr). Reuses the hero-card surface so the focus reads as inlaid into
/// the backdrop.
///
/// `NextPrayerView` supplies the selected focus and its localized name and short time.
private struct SalahFocusStyle: NextPrayerStyle {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  let size: SalahWidgetSize
  /// When true (Small), the focus fills the height with the eyebrow pinned to the
  /// top, the name+countdown centered, and the reminder at the bottom - so the
  /// negative space is balanced above and below the focus rather than dumped low.
  var distribute: Bool = false

  func makeBody(configuration: Configuration) -> some View {
    if let focus = configuration.focus {
      ActiveCardView(
        focus: focus, name: configuration.name, time: configuration.time,
        display: display, colors: colors, size: size, distribute: distribute)
    } else {
      NextUnknownView(display: display, colors: colors, size: size)
    }
  }
}

private struct ActiveCardView: View {
  let focus: SalahDisplay.Focus
  let name: Text?
  let time: Text?
  let display: SalahDisplay
  let colors: SalahWidgetColors
  let size: SalahWidgetSize
  var distribute: Bool = false

  private var labels: SalahWidgetLabels { display.labels }
  private var event: PrayerEvent { focus.event }
  private var date: Date { display.date }

  private var tone: SalahWidgetTone {
    switch focus {
    case .countUp: return .playingPrayerAudio  // green
    case .countdown: return display.focusIsTomorrow ? .normal : display.tone
    }
  }
  private var toneColor: Color { tone.color(colors) }
  /// The large focus card's tint, under all its text.
  private var cardTint: SalahWidgetTone? { size == .large ? tone : nil }
  /// `ink` on the large focus card's tint.
  private func onCard(_ ink: SalahWidgetInk) -> SalahWidgetInk {
    ink.on(cardTint, opacity: SalahWidgetTint.card)
  }
  private var isImminent: Bool {
    if case .countdown = focus { return tone == .imminent }
    return false
  }
  private var isCountUp: Bool { focus.isCountUp }

  // Per-size type scale.
  private var nameFont: Font {
    switch size {
    case .small: .system(.title3, design: .serif, weight: .semibold)
    case .medium: .system(.headline, design: .serif, weight: .semibold)
    case .large: .system(.title2, design: .serif, weight: .bold)
    }
  }
  private var timerFont: Font {
    switch size {
    case .small: .title3
    case .medium: .title3
    case .large: .title2
    }
  }

  var body: some View {
    // The hero-card surface (border + tint) only marks the inline expansion on
    // Large. On Small/Medium the focus fills its space directly - no nested box.
    Group {
      if size == .large {
        arranged.padding(12).salahHeroCard(toneColor: toneColor, accent: colors.accent)
      } else {
        arranged
      }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var arranged: some View {
    if distribute {
      VStack(alignment: .leading, spacing: 0) {
        statusLine
        Spacer(minLength: 6)
        VStack(alignment: .leading, spacing: 4) {
          nameRow
          timerRow
        }
        Spacer(minLength: 6)
        reminderRow
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: size == .small ? 3 : 5) {
        statusLine
        nameRow
        timerRow
        reminderRow
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: Pieces

  /// Leading indicator: the green "Now" badge (count-up) or the eyebrow.
  @ViewBuilder
  private var statusLine: some View {
    if isCountUp {
      InlineBadge(
        text: labels.now, tint: SalahWidgetTone.prayerColor(colors),
        ink: SalahWidgetInk.tone(.playingPrayerAudio).on(
          .playingPrayerAudio,
          opacity: SalahWidgetTint.stacked(
            SalahWidgetTint.badge, over: size == .large ? SalahWidgetTint.card : 0)))
    } else {
      EyebrowLabel(
        text: display.focusIsTomorrow ? labels.tomorrow : labels.nextPrayer,
        accent: colors.accentText, ink: onCard(.primary))
    }
  }

  /// Name + (on medium/large) the clock time on its trailing edge. Small drops
  /// the clock: at the focus name size there isn't room for both, and the
  /// countdown already conveys the timing - the absolute time lives on the bigger
  /// sizes and the menu bar. The name leads every size, so it is the face's one
  /// accentable element.
  private var nameRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      (name ?? Text(verbatim: "–"))
        .font(nameFont)
        .salahInk(onCard(.primary))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .widgetAccentable()
      if size != .small {
        Spacer(minLength: 6)
        Label {
          (time ?? Text(verbatim: "–"))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } icon: {
          Image(systemName: "clock")
        }
        .font(.caption)
        .salahInk(onCard(.secondary))
        .labelStyle(.tight)
        .layoutPriority(-1)
      }
    }
  }

  /// The big relative timer (count-down or count-up), tone-colored.
  private var timerRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      if isImminent {
        Image(systemName: "exclamationmark.circle.fill")
          .font(timerFont)
          .salahInk(onCard(SalahWidgetInk.tone(tone).glyph))
          .accessibilityHidden(true)
      }
      RelativeTime(
        target: event.time, reference: date, ink: onCard(.tone(tone)),
        font: timerFont, bold: isImminent, countingUp: isCountUp)
    }
  }

  /// The card's subtitle. Small (no schedule) carries the "since previous prayer"
  /// count-up here, in place of the pre/post reminder. Medium/Large keep the
  /// pre/post reminder detail - those sizes show the since count-up on the
  /// schedule row instead (see `ScheduleRowView.sinceText`).
  @ViewBuilder
  private var reminderRow: some View {
    if size == .small {
      if let sinceLine = display.sinceLine {
        Label {
          Text(verbatim: sinceLine).lineLimit(1).minimumScaleFactor(0.7)
        } icon: {
          Image(systemName: "clock.arrow.circlepath")
        }
        .font(.footnote)
        .salahInk(.secondary)
        .labelStyle(.tight)
      }
    } else if !isCountUp, let detail = display.reminderDetail(for: event) {
      Label {
        Text(verbatim: detail).lineLimit(1).minimumScaleFactor(0.7)
      } icon: {
        Image(systemName: "alarm")
      }
      .font(.caption)
      .salahInk(onCard(.secondary))
      .labelStyle(.tight)
    }
  }
}

/// The focus's place when the schedule doesn't know the next prayer: Salah's wording,
/// never a time or a countdown of its own.
private struct NextUnknownView: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  let size: SalahWidgetSize

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      EyebrowLabel(text: display.labels.nextPrayer, accent: colors.accentText, ink: .primary)
      Label {
        Text(verbatim: display.labels.nextUnknown)
          .lineLimit(2)
          .minimumScaleFactor(0.7)
      } icon: {
        Image(systemName: "questionmark.circle")
      }
      .font(size == .small ? .footnote : .caption)
      .salahInk(SalahWidgetInk.secondary.wrapping)
      .labelStyle(.tight)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(size == .large ? 12 : 0)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Small

/// The focus, alone, on a compact header (no room for a schedule).
private struct SmallContent: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      WidgetHeader(display: display, colors: colors, compact: true, showLocation: false)
      if let state = display.prayerState {
        // Distributed: eyebrow up, name+countdown centered, reminder down.
        FocusView(state: state, display: display, colors: colors, size: .small, distribute: true)
      } else {
        Spacer(minLength: 0)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// MARK: - Medium

/// Focus beside the day: a full-width header on top, then the active card (left)
/// next to the day's schedule (right), split by the accent hairline.
private struct MediumContent: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      WidgetHeader(display: display, colors: colors, compact: true)
      HStack(alignment: .top, spacing: 12) {
        if let state = display.prayerState {
          // Distribute to fill the pane height, matching the schedule beside it.
          FocusView(
            state: state, display: display, colors: colors, size: .medium, distribute: true
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        SalahHairline(accent: colors.accent)
        ScheduleRows(display: display, colors: colors, compact: true)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// MARK: - Large

/// The day, with the focus inside it: a single vertical living schedule where the
/// next prayer's row expands in place into the active card. End-of-day floats the
/// Tomorrow card beneath the (dimmed) day.
private struct LargeContent: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      WidgetHeader(display: display, colors: colors)
      VStack(spacing: 6) {
        // Collapsed rows share the leftover height evenly, so the slack is
        // distributed as breathing room between every row instead of dumped
        // beneath the day - which read as a lopsided bottom gap when the
        // focus is the last prayer (Isha). Under the end-of-day overflow they
        // still compress first (priority 0) beneath the priority-1 cards.
        ScheduleRows(display: display, colors: colors, spacing: 6)
        // End of day: the focus is tomorrow's Fajr, which is not a today row.
        // The full six-row day plus this card slightly overflows the fixed height;
        // the priority lets the hero keep its natural height while the dimmed,
        // passed rows absorb the deficit (instead of the hero compressing). When the
        // next prayer isn't known, the same place says so.
        if let state = display.prayerState, display.focus == nil || display.floatingFocus != nil {
          FocusView(state: state, display: display, colors: colors, size: .large)
            .layoutPriority(1)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

// MARK: - Message (setup / expired / unavailable) content

/// Centered icon + message used when there is no settings mirror yet (setup), the
/// timeline ran out (expired) or the schedule has nothing to show (unavailable). The
/// extension shell adds the `widgetURL` to Settings.
nonisolated struct WidgetMessageContent: View {
  let systemImage: String
  let message: Text

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.title)
        .salahInk(SalahWidgetInk.accent.glyph)
        .accessibilityHidden(true)
      message
        .font(.callout.weight(.medium))
        .salahInk(SalahWidgetInk.primary.wrapping)
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.8)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Stop control content

/// Shown while an adhan/reminder plays. The whole widget is wrapped in a Stop
/// intent button by the shell, so this presents the playing state as one large
/// "tap to stop" control, sized for the family.
nonisolated struct WidgetStopContent: View {
  let title: String
  let subtitle: String
  let tone: SalahWidgetTone
  let labels: SalahWidgetLabels
  let size: SalahWidgetSize

  private var isSmall: Bool { size == .small }

  var body: some View {
    VStack(spacing: isSmall ? 6 : 10) {
      Spacer(minLength: 0)
      Image(systemName: "stop.circle.fill")
        .font(.system(size: isSmall ? 44 : 58))
        .salahInk(SalahWidgetInk.tone(tone).glyph)
        .accessibilityHidden(true)
      VStack(spacing: 3) {
        Text(verbatim: title)
          .font(.system(isSmall ? .subheadline : .title3, design: .serif, weight: .semibold))
          .salahInk(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(verbatim: subtitle)
          .font(.caption2)
          .salahInk(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      Text(verbatim: labels.tapToStop)
        .font(.caption2.weight(.bold))
        .textCase(.uppercase)
        .salahInk(.tone(tone))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .multilineTextAlignment(.center)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(verbatim: "\(title). \(labels.tapToStop)"))
  }
}

extension WidgetStopContent {
  /// The stop control for what a display is playing; `nil` when nothing plays.
  init?(display: SalahDisplay, size: SalahWidgetSize) {
    guard let playback = display.playback, let title = display.playingTitle,
      let subtitle = display.playingSubtitle
    else { return nil }
    self.init(
      title: title, subtitle: subtitle, tone: playback.tone, labels: display.labels, size: size)
  }
}
