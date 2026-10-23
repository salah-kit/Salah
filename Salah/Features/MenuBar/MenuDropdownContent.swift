import SalahCore
import SalahUI
import SwiftUI

enum MenuDropdownMetrics {
  /// The dropdown width - a touch wider than the old 232pt panel so the serif
  /// schedule and hero read like the large widget, while staying a comfortable
  /// menu-bar popover rather than a desktop widget.
  static let width: CGFloat = 300
}

/// The rendered dropdown for a display - the previewable visual core shared by the
/// live menu bar and the SwiftUI previews. The root `MenuBarDropdownView` builds the
/// display from `PrayerManager` and supplies the action closures; everything visual
/// lives here.
///
/// It keeps every case the schedule can be in visible: a prayer the calculation can't
/// give today is a row with a dash, an unknown next prayer is said in the focus's
/// place, and while today's times aren't available at all, the last day that was is
/// shown marked as last known, never as today's.
struct MenuDropdownContent: View {
  let display: SalahDisplay
  /// The last listed day the schedule could give, shown while the listed day isn't.
  var lastKnownDay: PrayerDayAvailability? = nil
  /// Flip a prayer's alert. The root writes the (Jumu'ah-aware) config; previews pass
  /// a no-op.
  var onToggleAlert: (PrayerEvent) -> Void = { _ in }
  var onToggleSilent: () -> Void = {}
  var onStop: () -> Void = {}
  var onOpenSalah: () -> Void = {}
  var onOpenSettings: () -> Void = {}
  var onQuit: () -> Void = {}

  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let theme = display.theme
    let colors = theme.colors(for: scheme)
    MenuDropdownSurface(display: display, colors: colors) {
      VStack(alignment: .leading, spacing: 10) {
        MenuDropdownHeader(display: display, colors: colors)
        schedule(colors: colors)
        if let notice = FailureReporter.shared.currentNotice, notice.category == .terminal {
          noticeRow(notice)
        }
        Rectangle()
          .fill(colors.accent.opacity(0.15))
          .frame(height: 1)
        MenuDropdownFooter(
          display: display, colors: colors,
          onToggleSilent: onToggleSilent, onOpenSalah: onOpenSalah,
          onOpenSettings: onOpenSettings, onQuit: onQuit)
      }
      .padding(.horizontal, 12)
      .padding(.top, 12)
      .padding(.bottom, 10)
    }
    .frame(width: MenuDropdownMetrics.width)
    .environment(\.locale, display.locale)
    .environment(\.layoutDirection, display.isRightToLeft ? .rightToLeft : .leftToRight)
    .salahColorScheme(theme.forcedColorScheme)
  }

  // MARK: - Living schedule

  /// The rows the dropdown lists: today's, or the last known day's while today's isn't
  /// available.
  private var listed: (display: SalahDisplay, lastKnown: CivilDay?) {
    guard display.listedDay == nil, let lastKnownDay, let day = lastKnownDay.day else {
      return (display, nil)
    }
    var shown = display
    shown.day = lastKnownDay
    return (shown, day.day)
  }

  @ViewBuilder
  private func schedule(colors: SalahWidgetColors) -> some View {
    let (rows, lastKnown) = listed
    let playing = display.playback != nil
    VStack(spacing: 6) {
      // While audio plays, the Stop control leads in the focus position and every
      // prayer drops to a collapsed row.
      if let title = display.playingTitle, let subtitle = display.playingSubtitle,
        let playback = display.playback
      {
        MenuStopCard(
          title: title, subtitle: subtitle, tone: playback.tone, labels: display.labels,
          colors: colors, onStop: onStop)
      }
      if let lastKnown {
        MenuLastKnownCaption(day: lastKnown, display: display)
      }
      if case .available(let day, let coverage) = rows.day {
        let missing: [PrayerKind: ScheduleGapReason] = {
          if case .partial(let missing) = coverage { return missing }
          return [:]
        }()
        PrayerTimesList(
          day: day, state: rows.prayerState, names: display.names,
          countdown: .staticText, missing: missing
        ).rows
      }
      if !playing, lastKnown == nil, display.listedDay != nil,
        display.floatingFocus != nil
          || display.focus == nil
      {
        // End of day: tomorrow's Fajr is not a today row, so it floats beneath. When
        // the next prayer isn't known, the same place says so.
        MenuFocusView(display: display, colors: colors, onToggleAlert: nil)
      }
    }
    .prayerRowStyle(
      MenuRowStyle(
        display: rows, colors: colors, showsFocus: !playing && lastKnown == nil,
        onToggleAlert: onToggleAlert)
    )
    .animation(.smooth(duration: 0.3), value: display.focus?.event.id)
  }

  private func noticeRow(_ notice: FailureNotice) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill").font(.caption)
      Text(verbatim: notice.message)
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .salahInk(.secondary.wrapping)
    .padding(.horizontal, 4)
  }
}

/// Measures the intrinsic menu before drawing it, so its inks see the actual sky
/// and their positions in the same render pass, including in ImageRenderer.
private struct MenuDropdownSurface<Content: View>: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  @ViewBuilder let content: Content
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let isSolid = contrast == .increased
    ZStack {
      SalahWidgetBackground(tone: display.backgroundTone, colors: colors, isSolid: isSolid)
      content
        .environment(\.salahWidgetInkProbe, nil)
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .overlay {
          GeometryReader { proxy in
            content
              .environment(
                \.salahWidgetBackdrop,
                SalahWidgetBackdrop(
                  colors: colors, tone: display.backgroundTone, size: proxy.size,
                  isRightToLeft: display.isRightToLeft, isSolid: isSolid)
              )
              .frame(width: proxy.size.width, height: proxy.size.height)
          }
        }
    }
    .coordinateSpace(.named(SalahWidgetBackdrop.coordinateSpace))
  }
}

/// Salah's look for one dropdown row of SalahUI's `PrayerTimesList`: the collapsed
/// row, or the focus hero card. The package supplies times and missing-kind configurations.
private struct MenuRowStyle: PrayerRowStyle {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  /// Whether the focus expands into the hero card; not while audio plays (the Stop
  /// card leads) or while the rows are the last known day's.
  let showsFocus: Bool
  let onToggleAlert: (PrayerEvent) -> Void

  func makeBody(configuration: Configuration) -> some View {
    if let event = configuration.event {
      if showsFocus, display.focus?.event.id == event.id {
        MenuFocusView(display: display, colors: colors, onToggleAlert: toggle(event))
      } else {
        MenuScheduleRow(
          name: configuration.name, time: configuration.time ?? Text(verbatim: "–"),
          state: display.rowState(for: event, status: configuration.status),
          isSunrise: event.kind == .sunrise, alertEnabled: display.alerts(for: event).alert,
          colors: colors, labels: display.labels,
          sinceText: display.sinceText(for: event, status: configuration.status),
          onToggleAlert: toggle(event))
      }
    } else {
      MenuMissingRow(name: configuration.name, labels: display.labels)
    }
  }

  /// The per-row alert toggle, or nil for Sunrise (never alerted).
  private func toggle(_ event: PrayerEvent) -> (() -> Void)? {
    guard event.kind.isPrayer else { return nil }
    return { onToggleAlert(event) }
  }
}

/// The hero, SalahUI's `NextPrayerView` in Salah's menu focus style.
struct MenuFocusView: View {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  var onToggleAlert: (() -> Void)?

  var body: some View {
    if let state = display.prayerState {
      NextPrayerView(
        state: state, names: display.names, timeZone: display.settings.location.timeZone,
        countdown: .staticText, selection: .justStartedOrNextEvent
      )
      .nextPrayerStyle(
        MenuFocusStyle(display: display, colors: colors, onToggleAlert: onToggleAlert))
    } else {
      MenuNoticeCard(text: display.labels.nextUnknown, colors: colors)
    }
  }
}

/// Salah's hero card for the package-selected focus.
private struct MenuFocusStyle: NextPrayerStyle {
  let display: SalahDisplay
  let colors: SalahWidgetColors
  let onToggleAlert: (() -> Void)?

  func makeBody(configuration: Configuration) -> some View {
    if let focus = configuration.focus {
      MenuHeroCard(
        focus: focus, name: configuration.name, time: configuration.time,
        display: display, colors: colors,
        onToggleAlert: display.focusIsTomorrow ? nil : onToggleAlert)
    } else {
      MenuNoticeCard(text: display.labels.nextUnknown, colors: colors)
    }
  }
}

/// A row for a prayer the calculation can't give today: its name and a dash.
private struct MenuMissingRow: View {
  let name: Text
  let labels: SalahWidgetLabels

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "questionmark.circle")
        .font(.footnote)
        .salahInk(.secondary.glyph)
        .frame(width: 18)
        .accessibilityHidden(true)
      name
        .font(Font.system(.subheadline, design: .serif))
        .salahInk(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(minWidth: 56, alignment: .leading)
      Spacer(minLength: 6)
      Text(verbatim: "–")
        .font(Font.subheadline.monospacedDigit())
        .salahInk(.secondary)
        .frame(minWidth: 70, alignment: .trailing)
        .accessibilityLabel(Text(verbatim: labels.notAvailable))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// Marks the rows beneath as the last day the schedule could give, with its date.
private struct MenuLastKnownCaption: View {
  let day: CivilDay
  let display: SalahDisplay

  var body: some View {
    let formatter = DateFormatter()
    formatter.locale = display.locale
    formatter.timeZone = display.settings.location.timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    let date = formatter.string(from: day.start(in: display.settings.location.timeZone))
    return Label {
      Text(
        verbatim: String(
          format: localizedString("menu.lastKnown", locale: display.locale),
          locale: display.locale, date.bidiIsolated))
    } icon: {
      Image(systemName: "clock.badge.questionmark")
    }
    .font(.caption.weight(.medium))
    .salahInk(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 4)
  }
}

/// A notice in the focus's place: the schedule doesn't know the next prayer.
private struct MenuNoticeCard: View {
  let text: String
  let colors: SalahWidgetColors

  var body: some View {
    Label {
      Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: "questionmark.circle")
    }
    .font(.subheadline)
    .salahInk(.secondary.on(.normal, opacity: SalahWidgetTint.card).wrapping)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .salahHeroCard(toneColor: colors.primary, accent: colors.accent)
  }
}
