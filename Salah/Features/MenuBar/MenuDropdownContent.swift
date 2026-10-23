import AppKit
import SalahCore
import SalahUI
import SwiftUI

enum MenuDropdownMetrics {
  /// The dropdown's width.
  static let width: CGFloat = 300
}

/// The rendered dropdown for a display: the dates and the place, the next prayer on the
/// time of day's sky, the day's timeline, the day's prayers with their alerts, and the
/// footer. The root `MenuBarDropdownView` builds the display and supplies the actions;
/// previews and the visual tests render this alone.
///
/// It keeps every case the schedule can be in visible: a prayer the calculation can't give
/// today is a row with a dash, an unknown next prayer is said in the hero's place, and
/// while today's times aren't available at all, the last day that was is shown marked as
/// last known, never as today's.
struct MenuDropdownContent: View {
  let display: SalahDisplay
  /// The last listed day the schedule could give, shown while the listed day isn't.
  var lastKnownDay: PrayerDayAvailability? = nil
  /// Flip a prayer's alert. The root writes the (Jumu'ah-aware) config; previews pass a
  /// no-op.
  var onToggleAlert: (PrayerEvent) -> Void = { _ in }
  var onToggleSilent: () -> Void = {}
  var onStop: () -> Void = {}
  var onOpenSalah: () -> Void = {}
  var onOpenSettings: () -> Void = {}
  var onQuit: () -> Void = {}

  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let colors = SalahColors(phase: display.phase, scheme: scheme, contrast: contrast)
    VStack(alignment: .leading, spacing: 10) {
      MenuHeader(display: display, colors: colors)
      if let notice = FailureReporter.shared.currentNotice, notice.category == .terminal {
        MenuAttentionBanner(message: notice.message, colors: colors)
      }
      MenuHero(display: display, colors: colors, onStop: onStop)
      if let day = display.listedDay {
        SalahDayTimeline(
          day: day, date: display.date, followsTimeOfDay: display.settings.followsTimeOfDay)
      }
      schedule(colors: colors)
      MenuDropdownFooter(
        display: display, colors: colors, onToggleSilent: onToggleSilent,
        onOpenSalah: onOpenSalah, onOpenSettings: onOpenSettings, onQuit: onQuit)
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, 10)
    .frame(width: MenuDropdownMetrics.width)
    .background(colors.palette.elevated.color)
    .environment(\.locale, display.locale)
    .environment(\.layoutDirection, display.isRightToLeft ? .rightToLeft : .leftToRight)
  }

  // MARK: - The day's prayers

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
  private func schedule(colors: SalahColors) -> some View {
    let (rows, lastKnown) = listed
    VStack(spacing: 2) {
      if let lastKnown {
        MenuLastKnownCaption(day: lastKnown, display: display, colors: colors)
      }
      if case .available(let day, let coverage) = rows.day {
        let missing: [PrayerKind: ScheduleGapReason] = {
          if case .partial(let missing) = coverage { return missing }
          return [:]
        }()
        PrayerTimesList(
          day: day, state: rows.prayerState, names: display.names, countdown: .staticText,
          missing: missing
        ).rows
      }
    }
    .prayerRowStyle(
      MenuRowStyle(
        display: rows, colors: colors, isLastKnown: lastKnown != nil, onToggleAlert: onToggleAlert)
    )
    .animation(.smooth(duration: 0.5), value: display.focus?.event.id)
    // After Isha: tomorrow's Fajr beneath the day.
    if lastKnown == nil, display.focusIsTomorrow, let fajr = display.focus?.event {
      Text(verbatim: display.labels.tomorrow)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(colors.palette.labelSecondary.color)
        .padding(.horizontal, 8)
      MenuPrayerRow(
        event: fajr, name: Text(verbatim: display.name(of: fajr)),
        time: Text(verbatim: display.timeText(of: fajr)), role: .next, display: display,
        colors: colors, onToggleAlert: { onToggleAlert(fajr) }, day: display.labels.tomorrow)
    }
  }
}

// MARK: - Header

/// The dates, and the place; while silent, "Sounds off" in the place's stead.
struct MenuHeader: View {
  let display: SalahDisplay
  let colors: SalahColors

  var body: some View {
    let header = display.header
    let palette = colors.palette
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(verbatim: "\(header.hijriDay) \(header.hijriMonth) \(header.hijriYear)")
          .font(.headline)
          .foregroundStyle(palette.labelPrimary.color)
        Text(verbatim: header.gregorianDate)
          .font(.subheadline)
          .foregroundStyle(palette.labelSecondary.color)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .frame(maxWidth: .infinity, alignment: .leading)
      if display.settings.silentMode {
        Label {
          Text(verbatim: localizedString("menu.soundsOff", locale: display.locale))
        } icon: {
          Image(systemName: "bell.slash.fill")
        }
        .labelStyle(.titleAndIcon)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(palette.labelPrimary.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(palette.fillTertiary.color))
      } else {
        Label {
          Text(verbatim: header.location).privacySensitive()
        } icon: {
          Image(systemName: "location.fill")
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(palette.labelSecondary.color)
        .lineLimit(1)
        .padding(.top, 2)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// Something needs attention, such as location access being off: what, and the way to it.
private struct MenuAttentionBanner: View {
  let message: String
  let colors: SalahColors

  var body: some View {
    let palette = colors.palette
    Button {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
      {
        NSWorkspace.shared.open(url)
      }
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "location.slash.fill")
          .font(.system(size: 18))
          .foregroundStyle(palette.warning.color)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: message)
            .font(.body.weight(.semibold))
            .foregroundStyle(palette.labelPrimary.color)
            .fixedSize(horizontal: false, vertical: true)
          Text("menu.openSettings")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.accentText.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.forward")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(palette.labelTertiary.color)
          .accessibilityHidden(true)
      }
      .padding(12)
      .background(
        palette.formGroup.color, in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .menuPointerCursor()
  }
}

/// Marks the rows beneath as the last day the schedule could give, with its date.
private struct MenuLastKnownCaption: View {
  let day: CivilDay
  let display: SalahDisplay
  let colors: SalahColors

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
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(colors.palette.labelSecondary.color)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 8)
  }
}

// MARK: - Hero

/// The next prayer on the time of day's sky; the one that just began, counting up; tomorrow's
/// Fajr after Isha; or, while the adhan, the du'a or a reminder plays, Stop.
struct MenuHero: View {
  let display: SalahDisplay
  let colors: SalahColors
  var onStop: () -> Void = {}

  private var palette: SalahPalette { colors.palette }

  var body: some View {
    let approaching = isApproaching
    VStack(alignment: .leading, spacing: 2) {
      if let playback = display.playback {
        playing(playback)
      } else if let focus = display.focus {
        focusContent(focus)
      } else {
        unknown
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(colors.sky, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      if approaching {
        MenuBreathingRim(color: palette.accent)
      }
    }
  }

  private var isApproaching: Bool {
    display.playback == nil && display.focus?.isCountUp == false
      && display.prayerState?.isApproaching == true && !display.focusIsTomorrow
  }

  // MARK: Pieces

  private func top(eyebrow: some View, glyph: PrayerKind?) -> some View {
    HStack(spacing: 6) {
      eyebrow
      Spacer(minLength: 6)
      if let glyph {
        PrayerGlyph(kind: glyph)
          .font(.system(size: 19))
          .foregroundStyle(colors.phase.tint.color)
          .frame(width: 24, height: 24)
          .accessibilityHidden(true)
      }
    }
  }

  private func eyebrowText(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(palette.labelSecondary.color)
  }

  private func nameLine(_ name: String, when: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(verbatim: name)
        .font(.title)
        .foregroundStyle(palette.labelPrimary.color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Spacer(minLength: 6)
      Text(verbatim: when)
        .font(.callout)
        .foregroundStyle(palette.labelSecondary.color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .layoutPriority(-1)
    }
  }

  private func footer(symbol: String, text: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .font(.system(size: 10))
        .accessibilityHidden(true)
      Text(verbatim: text)
        .font(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Spacer(minLength: 0)
    }
    .foregroundStyle(palette.labelSecondary.color)
    .padding(.top, 4)
  }

  private func time(_ event: PrayerEvent) -> String { display.timeText(of: event) }

  private func format(_ key: String.LocalizationValue, _ arguments: CVarArg...) -> String {
    String(
      format: localizedString(key, locale: display.locale), locale: display.locale,
      arguments: arguments)
  }

  // MARK: States

  @ViewBuilder
  private func focusContent(_ focus: SalahDisplay.Focus) -> some View {
    let event = focus.event
    let labels = display.labels
    if focus.isCountUp {
      top(
        eyebrow: Text(verbatim: labels.now)
          .font(.caption.weight(.semibold))
          .foregroundStyle(palette.labelOnAccent.color)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(Capsule().fill(palette.accentFill.color)),
        glyph: event.kind)
      nameLine(display.name(of: event), when: format("today.began", time(event)))
      countdown(event, countingUp: true, color: colors.phase.text)
      if let next = display.prayerState?.nextPrayer {
        footer(
          symbol: "clock",
          text: format("menu.hero.nextAt", display.name(of: next), time(next)))
      }
    } else {
      let tomorrow = display.focusIsTomorrow
      top(
        eyebrow: eyebrowText(tomorrow ? labels.tomorrow : labels.nextPrayer), glyph: event.kind)
      nameLine(display.name(of: event), when: format("today.begins", time(event)))
      countdown(
        event, countingUp: false, color: isApproaching ? palette.accentText : palette.labelPrimary)
      let alerts = display.alerts(for: event)
      // In silent mode nothing sounds, so the hero promises no adhan or reminder.
      if display.settings.silentMode {
        EmptyView()
      } else if isApproaching, alerts.alert {
        footer(symbol: "bell.fill", text: format("menu.hero.adhanAt", time(event)))
      } else if let before = alerts.beforeMinutes, !isApproaching {
        footer(
          symbol: "alarm", text: format("menu.hero.reminderBefore", reminderLength(before)))
      } else if alerts.alert, event.kind.isPrayer {
        footer(symbol: "bell.fill", text: format("menu.hero.adhanAt", time(event)))
      }
    }
  }

  /// A reminder's lead: "10 min", "1 hr, 30 min".
  private func reminderLength(_ minutes: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .short
    formatter.allowedUnits = [.hour, .minute]
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = display.locale
    formatter.calendar = calendar
    return formatter.string(from: TimeInterval(minutes * 60)) ?? ""
  }

  private func countdown(_ event: PrayerEvent, countingUp: Bool, color: ThemeColor) -> some View {
    MenuLiveCountdown(
      target: event.time, reference: display.date,
      font: .system(size: 30, weight: .semibold, design: .rounded), countingUp: countingUp
    )
    .foregroundStyle(color.color)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: spokenCountdown(event, countingUp: countingUp)))
    .accessibilityAddTraits(.isStaticText)
    .accessibilityIdentifier("menu.hero.duration")
  }

  /// A spelled-out duration for VoiceOver; the visible timer is the abbreviated "1:24".
  private func spokenCountdown(_ event: PrayerEvent, countingUp: Bool) -> String {
    let duration = PrayerDurationFormat.string(
      abs(event.time.timeIntervalSince(display.date)), width: .spoken, locale: display.locale)
    if countingUp {
      return display.labels.sinceSpoken(prayer: display.name(of: event), time: duration)
    }
    return "\(display.name(of: event)) · \(duration) \(display.labels.remaining)"
  }

  @ViewBuilder
  private func playing(_ playback: SalahPlayback) -> some View {
    let event = playback.event
    top(
      eyebrow: Label {
        Text(verbatim: display.playingTitle ?? "")
      } icon: {
        Image(systemName: "speaker.wave.2.fill")
      }
      .labelStyle(.titleAndIcon)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(colors.phase.text.color),
      glyph: event.kind)
    nameLine(display.name(of: event), when: time(event))
    Button(action: onStop) {
      Text(verbatim: display.labels.stopShort)
        .font(.body.weight(.medium))
        .foregroundStyle(palette.labelOnAccent.color)
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(Capsule().fill(palette.accentFill.color))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .keyboardShortcut(.defaultAction)
    .menuPointerCursor()
    .padding(.vertical, 4)
    .accessibilityLabel(Text(verbatim: display.labels.stopAudio))
    // The adhan, not yet its du'a: the du'a follows it when it's on.
    if playback.slot == .alert, !playback.isDua, Preferences.shared.duaEnabled {
      footer(
        symbol: "speaker.wave.2.fill",
        text: localizedString("menu.hero.duaFollows", locale: display.locale))
    }
  }

  private var unknown: some View {
    VStack(alignment: .leading, spacing: 2) {
      eyebrowText(display.labels.nextPrayer)
      Text(verbatim: display.labels.nextUnknown)
        .font(.body.weight(.semibold))
        .foregroundStyle(palette.labelPrimary.color)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// The approaching card's rim, breathing in the accent. Each approach inserts a new rim,
/// whose own state starts the breath again.
private struct MenuBreathingRim: View {
  let color: ThemeColor
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var breathing = false

  var body: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .strokeBorder(
        color.color.opacity(reduceMotion ? 1 : (breathing ? 1 : 0.45)), lineWidth: 1.5
      )
      .animation(
        reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
        value: breathing
      )
      .onAppear { breathing = true }
      .allowsHitTesting(false)
  }
}

// MARK: - Rows

/// A prayer's role in the list, which sets its look.
enum MenuRowRole { case passed, current, next, upcoming }

/// Salah's dropdown row for SalahUI's `PrayerTimesList`.
struct MenuRowStyle: PrayerRowStyle {
  let display: SalahDisplay
  let colors: SalahColors
  let isLastKnown: Bool
  let onToggleAlert: (PrayerEvent) -> Void

  func makeBody(configuration: Configuration) -> some View {
    if let event = configuration.event {
      MenuPrayerRow(
        event: event, name: configuration.name, time: configuration.time ?? Text(verbatim: "–"),
        role: isLastKnown ? .passed : role(of: event, status: configuration.status),
        display: display, colors: colors, onToggleAlert: { onToggleAlert(event) })
    } else {
      MenuMissingRow(name: configuration.name, display: display, colors: colors)
    }
  }

  private func role(of event: PrayerEvent, status: PrayerEventStatus?) -> MenuRowRole {
    if display.playingPrayer?.id == event.id { return .current }
    switch status {
    case .justStarted?: return .current
    case .next?: return display.focusIsTomorrow ? .upcoming : .next
    case .upcoming?: return .upcoming
    case .passed?: return .passed
    case nil: return event.time <= display.date ? .passed : .upcoming
    }
  }
}

struct MenuPrayerRow: View {
  let event: PrayerEvent
  let name: Text
  let time: Text
  let role: MenuRowRole
  let display: SalahDisplay
  let colors: SalahColors
  let onToggleAlert: () -> Void
  /// The day the row belongs to when it isn't the listed one, "Tomorrow", which names its
  /// alert toggle apart from the same prayer's today.
  var day: String? = nil

  @State private var hovering = false

  private var palette: SalahPalette { colors.palette }

  var body: some View {
    HStack(spacing: 8) {
      PrayerGlyph(kind: event.kind)
        .font(.system(size: 14))
        .foregroundStyle(glyphColor.color)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
      HStack(spacing: 6) {
        name
          .font(.body.weight(isStrong ? .semibold : .regular))
          .foregroundStyle((role == .passed ? palette.labelSecondary : palette.labelPrimary).color)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        if let detail {
          Text(verbatim: detail)
            .font(.subheadline)
            .foregroundStyle(detailColor.color)
            .lineLimit(1)
            .layoutPriority(-1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if role == .current {
        Text(verbatim: display.labels.now)
          .font(.caption.weight(.semibold))
          .foregroundStyle(palette.labelOnAccent.color)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(Capsule().fill(palette.accentFill.color))
      }
      time
        .font(.body.weight(isStrong ? .semibold : .regular).monospacedDigit())
        .foregroundStyle((role == .passed ? palette.labelSecondary : palette.labelPrimary).color)
        .lineLimit(1)
      bell
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(minHeight: 28)
    .background {
      RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background)
    }
    .onHover { hovering = $0 }
  }

  private var isStrong: Bool { role == .current || role == .next }

  private var background: Color {
    switch role {
    case .current: colors.phase.tintSubtle.color
    case .next: palette.accentSubtle.color
    case .passed, .upcoming: hovering ? palette.fillQuaternary.color : .clear
    }
  }

  private var glyphColor: ThemeColor {
    switch role {
    case .passed: palette.labelTertiary
    case .current: colors.phase.tint
    case .next: palette.accent
    case .upcoming: palette.labelSecondary
    }
  }

  private var detailColor: ThemeColor {
    switch role {
    case .current: colors.phase.text
    case .next: palette.accentText
    case .passed, .upcoming: palette.labelSecondary
    }
  }

  /// How long until the next prayer; how long ago the current or latest one began.
  private var detail: String? {
    switch role {
    case .next:
      let duration = MenuDuration.string(
        event.time.timeIntervalSince(display.date), locale: display.locale)
      return String(
        format: localizedString("today.row.in", locale: display.locale), locale: display.locale,
        duration.bidiIsolated)
    case .current, .passed:
      guard role == .current || display.prayerState?.previous?.id == event.id else { return nil }
      let formatter = RelativeDateTimeFormatter()
      formatter.locale = display.locale
      formatter.unitsStyle = .short
      return formatter.localizedString(for: event.time, relativeTo: display.date)
    case .upcoming:
      return nil
    }
  }

  @ViewBuilder
  private var bell: some View {
    if event.kind.isPrayer {
      // Silent mode draws every bell off: nothing sounds.
      let isOn = display.alerts(for: event).alert && !display.settings.silentMode
      let label =
        ([day, display.name(of: event)].compactMap { $0 } + [
          localizedString("settings.notif.alert.toggle")
        ]).joined(separator: " · ")
      Button(action: onToggleAlert) {
        Image(systemName: isOn ? "bell.fill" : "bell.slash")
          .font(.system(size: 12))
          .foregroundStyle(bellColor(isOn: isOn).color)
          .frame(width: 18, height: 18)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      // In silent mode the bells draw off and turn nothing on or off.
      .disabled(display.settings.silentMode)
      .menuPointerCursor()
      .help(Text(verbatim: label))
      .accessibilityLabel(Text(verbatim: label))
      .accessibilityValue(
        Text(
          verbatim: display.alerts(for: event).alert
            ? display.labels.alertOn : display.labels.alertOff))
    } else {
      Image(systemName: "bell.slash")
        .font(.system(size: 12))
        .foregroundStyle(palette.labelTertiary.color)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
  }

  private func bellColor(isOn: Bool) -> ThemeColor {
    guard isOn else { return palette.labelTertiary }
    return isStrong ? palette.accent : palette.labelSecondary
  }
}

/// A row for a prayer the calculation can't give today: its name and a dash.
struct MenuMissingRow: View {
  let name: Text
  let display: SalahDisplay
  let colors: SalahColors

  var body: some View {
    let palette = colors.palette
    HStack(spacing: 8) {
      Image(systemName: "questionmark.circle")
        .font(.system(size: 13))
        .foregroundStyle(palette.labelTertiary.color)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
      HStack(spacing: 6) {
        name.font(.body)
        Text("menu.row.missing").font(.subheadline)
      }
      .foregroundStyle(palette.labelSecondary.color)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      Text(verbatim: "—")
        .font(.body.monospacedDigit())
        .foregroundStyle(palette.labelSecondary.color)
        .accessibilityLabel(Text(verbatim: display.labels.notAvailable))
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(minHeight: 28)
    .accessibilityElement(children: .combine)
  }
}
