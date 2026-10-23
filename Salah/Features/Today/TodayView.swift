import SalahCore
import SalahUI
import SwiftUI

/// Today, the window's first pane: the date and the place, the next prayer with the day's
/// timeline beneath it, today's prayers, and that Salah keeps running in the menu bar, with
/// Quit Salah. Rendered from the running app's schedule at each minute, like the dropdown.
struct TodayView: View {
  var prayerManager: PrayerManager

  var body: some View {
    TimelineView(.everyMinute) { context in
      TodayContent(
        display: prayerManager.display(at: context.date),
        onToggleAlert: { prayerManager.preferences.toggleAlert(for: $0) },
        onQuit: { prayerManager.quitSalah() })
    }
  }
}

/// The rendered Today for a display: the previewable core of `TodayView`.
struct TodayContent: View {
  let display: SalahDisplay
  var onToggleAlert: (PrayerEvent) -> Void = { _ in }
  var onQuit: () -> Void = {}

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        HStack(alignment: .top, spacing: 20) {
          VStack(spacing: 12) {
            TodayHero(display: display)
            if let day = display.listedDay {
              TodayDayTimeline(day: day, date: display.date)
            }
          }
          .frame(maxWidth: .infinity)
          prayers
            .frame(maxWidth: .infinity)
        }
        menuBar
      }
      .padding(.horizontal, 24)
      .padding(.top, 4)
      .padding(.bottom, 24)
    }
    .environment(\.locale, display.locale)
  }

  // MARK: - Header

  private var header: some View {
    let header = display.header
    return HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: "\(header.hijriDay) \(header.hijriMonth) \(header.hijriYear)")
          .font(.headline)
        Text(verbatim: header.gregorianDate)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Label {
        Text(verbatim: header.location).privacySensitive()
      } icon: {
        Image(systemName: "location.fill")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .labelStyle(.titleAndIcon)
      .padding(.top, 2)
    }
    .lineLimit(1)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Prayers

  @ViewBuilder
  private var prayers: some View {
    if case .available(let day, let coverage) = display.day {
      let missing: [PrayerKind: ScheduleGapReason] = {
        if case .partial(let missing) = coverage { return missing }
        return [:]
      }()
      VStack(spacing: 2) {
        PrayerTimesList(
          day: day, state: display.prayerState, names: display.names, countdown: .staticText,
          missing: missing
        ).rows
      }
      .prayerRowStyle(TodayRowStyle(display: display, onToggleAlert: onToggleAlert))
      .padding(6)
      .background(WindowPalette.groupFill, in: RoundedRectangle(cornerRadius: 12))
    } else {
      Label {
        Text(verbatim: display.labels.timesUnavailable)
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "clock.badge.questionmark")
      }
      .font(.callout)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(WindowPalette.groupFill, in: RoundedRectangle(cornerRadius: 12))
    }
  }

  // MARK: - Menu bar

  private var menuBar: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("settings.general.menubar")
        .font(.headline)
        .padding(.leading, 10)
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("today.keepsRunning.title")
            .font(.body)
          Text("today.keepsRunning.detail")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        // A plain push button: the window's gold tint is for its controls, not this one.
        Button(action: onQuit) {
          Text(verbatim: localizedString("menu.quit", locale: display.locale))
        }
        .tint(.primary)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .frame(minHeight: 50)
      .background(WindowPalette.groupFill, in: RoundedRectangle(cornerRadius: 12))
    }
  }
}

/// The next prayer, or the one that just began counting up, on the sky of the time of day.
private struct TodayHero: View {
  let display: SalahDisplay

  var body: some View {
    let phase = DayPhase.phase(at: display.date, events: display.listedDay?.events ?? [])
    Group {
      if let focus = display.focus {
        content(focus, phase: phase)
      } else {
        Label {
          Text(verbatim: display.labels.nextUnknown).fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "questionmark.circle")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(
      LinearGradient(
        colors: [phase.colors.skyTop, phase.colors.skyBottom], startPoint: .top,
        endPoint: .bottom),
      in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private func content(_ focus: SalahDisplay.Focus, phase: DayPhase) -> some View {
    let event = focus.event
    let labels = display.labels
    let eyebrow =
      focus.isCountUp ? labels.now : display.focusIsTomorrow ? labels.tomorrow : labels.nextPrayer
    let time = display.timeText(of: event)
    let timeLine = String(
      format: localizedString(
        focus.isCountUp ? "today.began" : "today.begins", locale: display.locale),
      locale: display.locale, time)
    return VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(verbatim: eyebrow)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer(minLength: 6)
        PrayerGlyph(kind: event.kind)
          .font(.system(size: 17))
          .foregroundStyle(phase.colors.tint)
          .frame(width: 24, height: 24)
          .accessibilityHidden(true)
      }
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: display.name(of: event))
          .font(.title)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Spacer(minLength: 6)
        Text(verbatim: timeLine)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .layoutPriority(-1)
      }
      MenuLiveCountdown(
        target: event.time, reference: display.date,
        font: .system(size: 30, weight: .semibold, design: .rounded), countingUp: focus.isCountUp
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: countdownAccessibilityLabel(focus)))
      .accessibilityAddTraits(.isStaticText)
      if !focus.isCountUp, let detail = display.reminderDetail(for: event) {
        Label {
          Text(verbatim: detail).lineLimit(1).minimumScaleFactor(0.7)
        } icon: {
          Image(systemName: "alarm")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// A spelled-out duration for VoiceOver, as the dropdown's hero says it.
  private func countdownAccessibilityLabel(_ focus: SalahDisplay.Focus) -> String {
    let event = focus.event
    let duration = PrayerDurationFormat.string(
      abs(event.time.timeIntervalSince(display.date)), width: .spoken, locale: display.locale)
    if focus.isCountUp {
      return display.labels.sinceSpoken(prayer: display.name(of: event), time: duration)
    }
    return "\(display.name(of: event)) · \(duration) \(display.labels.remaining)"
  }
}

/// Salah's glyph for a prayer or sunrise: a custom symbol, which sizes with `.font` and
/// tints with the foreground style.
struct PrayerGlyph: View {
  let kind: PrayerKind

  var body: some View {
    Image("salah.\(kind.rawValue)")
      .symbolRenderingMode(.hierarchical)
  }
}

/// A row of Today's prayers: the glyph, the name, how long ago the latest began or how long
/// until the next, the time, and the alert's bell, which toggles it.
private struct TodayRowStyle: PrayerRowStyle {
  let display: SalahDisplay
  let onToggleAlert: (PrayerEvent) -> Void

  func makeBody(configuration: Configuration) -> some View {
    TodayPrayerRow(configuration: configuration, display: display, onToggleAlert: onToggleAlert)
  }
}

private struct TodayPrayerRow: View {
  let configuration: PrayerRowConfiguration
  let display: SalahDisplay
  let onToggleAlert: (PrayerEvent) -> Void

  var body: some View {
    let state = configuration.event.map { display.rowState(for: $0, status: configuration.status) }
    let isFocus: Bool = {
      switch state {
      case .next?, .current?, .active?: true
      default: false
      }
    }()
    let isPassed = state == .passed
    HStack(spacing: 8) {
      PrayerGlyph(kind: configuration.kind)
        .font(.system(size: 13))
        .foregroundStyle(
          isFocus ? AnyShapeStyle(WindowPalette.accentText) : AnyShapeStyle(.secondary)
        )
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
      HStack(spacing: 6) {
        configuration.name
          .font(.body.weight(isFocus ? .semibold : .regular))
          .foregroundStyle(isPassed ? .secondary : .primary)
        if let detail = detail(isFocus: isFocus) {
          Text(verbatim: detail)
            .font(.subheadline)
            .foregroundStyle(
              isFocus ? AnyShapeStyle(WindowPalette.accentText) : AnyShapeStyle(.secondary))
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      Spacer(minLength: 6)
      (configuration.time
        ?? Text(verbatim: "–").accessibilityLabel(Text(verbatim: display.labels.notAvailable)))
        .font(.body.weight(isFocus ? .semibold : .regular).monospacedDigit())
        .foregroundStyle(isPassed ? .secondary : .primary)
        .lineLimit(1)
      bell(isFocus: isFocus)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(minHeight: 28)
    .background {
      if isFocus {
        RoundedRectangle(cornerRadius: 8).fill(WindowPalette.accentSubtle)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// How long until the next event, or how long ago the latest began.
  private func detail(isFocus: Bool) -> String? {
    guard let event = configuration.event else { return nil }
    if isFocus, event.time > display.date {
      let duration = PrayerDurationFormat.string(
        event.time.timeIntervalSince(display.date), direction: .remaining,
        locale: display.locale, bidiIsolated: true)
      return String(
        format: localizedString("today.row.in", locale: display.locale), locale: display.locale,
        duration)
    }
    if isFocus { return display.labels.now }
    guard display.prayerState?.previous?.id == event.id else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = display.locale
    formatter.unitsStyle = .short
    return formatter.localizedString(for: event.time, relativeTo: display.date)
  }

  @ViewBuilder
  private func bell(isFocus: Bool) -> some View {
    if let event = configuration.event, event.kind.isPrayer {
      let isOn = display.alerts(for: event).alert
      let label = "\(display.name(of: event)) · \(localizedString("settings.notif.alert.toggle"))"
      Button {
        onToggleAlert(event)
      } label: {
        Image(systemName: isOn ? "bell.fill" : "bell.slash")
          .font(.system(size: 12))
          .foregroundStyle(
            isOn
              ? (isFocus ? AnyShapeStyle(WindowPalette.accent) : AnyShapeStyle(.secondary))
              : AnyShapeStyle(.tertiary)
          )
          .frame(width: 18, height: 18)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .menuPointerCursor()
      .help(Text(verbatim: label))
      .accessibilityLabel(Text(verbatim: label))
      .accessibilityValue(
        Text(verbatim: isOn ? display.labels.alertOn : display.labels.alertOff))
    } else {
      Image(systemName: "bell.slash")
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
  }
}
