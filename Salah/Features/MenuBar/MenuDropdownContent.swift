import AppKit
import SalahCore
import SalahUI
import SwiftUI

enum MenuDropdownMetrics {
  /// The dropdown's width.
  static let width: CGFloat = 300
  /// The rim's corner radius and width.
  static let radius: CGFloat = 16
  static let rim: CGFloat = 1
  /// The content's inset inside the rim.
  static let padding = EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12)
  /// The width the rows take: the dropdown's, less the rim and the padding.
  static var contentWidth: CGFloat { width - 2 * rim - padding.leading - padding.trailing }
  /// Figma draws the day's timeline 2 pt wider than the rows, past their trailing edge.
  static var timelineWidth: CGFloat { contentWidth + 2 }
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
  /// What needs attention, such as location access being off: the banner's title.
  var attention: String? = nil
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
      if let attention {
        MenuAttentionBanner(title: attention, locale: display.locale, colors: colors)
      }
      MenuHero(display: display, colors: colors, onStop: onStop)
      if let day = display.listedDay {
        SalahDayTimeline(
          day: day, date: display.date, followsTimeOfDay: display.settings.followsTimeOfDay
        )
        .frame(width: MenuDropdownMetrics.timelineWidth)
        .frame(width: MenuDropdownMetrics.contentWidth, alignment: .leading)
      }
      schedule(colors: colors)
      MenuDropdownFooter(
        display: display, colors: colors, onToggleSilent: onToggleSilent,
        onOpenSalah: onOpenSalah, onOpenSettings: onOpenSettings, onQuit: onQuit)
    }
    // The menu-bar window sizes itself to the content's smallest height, which text that
    // may shrink to fit (`minimumScaleFactor`) would lower: keep every line at full size.
    .fixedSize(horizontal: false, vertical: true)
    .padding(MenuDropdownMetrics.padding)
    .padding(MenuDropdownMetrics.rim)
    .frame(width: MenuDropdownMetrics.width)
    .background {
      // The rim: `glass/stroke` inside the edge of the `bg/elevated` panel.
      let shape = RoundedRectangle(cornerRadius: MenuDropdownMetrics.radius, style: .continuous)
      shape.fill(colors.palette.elevated.color)
        .overlay(
          shape.strokeBorder(colors.palette.glassStroke.color, lineWidth: MenuDropdownMetrics.rim))
    }
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
        // The Sounds off chip: Figma's status chip, 13 semibold on `fill/tertiary`.
        HStack(spacing: 5) {
          Image(systemName: "bell.slash.fill")
            .font(.system(size: 12))
            .foregroundStyle(palette.labelSecondary.color)
            .frame(width: 14, height: 14)
          Text(verbatim: localizedString("menu.soundsOff", locale: display.locale))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.labelPrimary.color)
            .frame(height: 18)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(palette.fillTertiary.color))
        .padding(.top, 2)
      } else {
        HStack(spacing: 4) {
          Image(systemName: "location.fill")
            .font(.caption)
            .frame(width: 11, height: 11)
          Text(verbatim: header.location).privacySensitive()
            .font(.caption)
        }
        .foregroundStyle(palette.labelSecondary.color)
        .lineLimit(1)
        .padding(.top, 2)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// Something needs attention, such as location access being off: what, and the way to it.
/// Figma's banner: a 22 pt symbol in `status/warning`, the title at 17 semibold, the action
/// at 13 semibold, and a chevron, on `bg/grouped-secondary`.
private struct MenuAttentionBanner: View {
  let title: String
  let locale: Locale
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
          .font(.system(size: 19))
          .foregroundStyle(palette.warning.color)
          .frame(width: 22, height: 22)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: title)
            .font(.system(size: 17, weight: .semibold))
            .lineSpacing(2)
            .padding(.vertical, 1)
            .foregroundStyle(palette.labelPrimary.color)
            .fixedSize(horizontal: false, vertical: true)
          Text(verbatim: localizedString("menu.openSettings", locale: locale))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.accentText.color)
            .frame(height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.forward")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(palette.labelTertiary.color)
          .frame(width: 14, height: 14)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(
        palette.groupedSecondary.color,
        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
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
    // The approaching rim lies inside the card's edge, and the content inside the rim.
    .padding(approaching ? MenuBreathingRim.width : 0)
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

  /// The "Now" badge: 12 semibold `label/on-accent` in a 20 pt `accent/fill` capsule.
  static func nowBadge(_ text: String, palette: SalahPalette) -> some View {
    Text(verbatim: text)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(palette.labelOnAccent.color)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .frame(height: 20)
      .background(Capsule().fill(palette.accentFill.color))
  }

  // MARK: Pieces

  private func top(eyebrow: some View, glyph: PrayerKind?) -> some View {
    HStack(spacing: 6) {
      eyebrow
      Spacer(minLength: 6)
      if let glyph {
        PrayerGlyph(kind: glyph)
          .font(.system(size: MenuGlyphMetrics.hero))
          .foregroundStyle(colors.phase.tint.color)
          .frame(width: 24, height: 24)
          .accessibilityHidden(true)
      }
    }
  }

  private func eyebrowText(_ text: String) -> some View {
    Text(verbatim: text)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(colors.secondaryOnSky(atTop: true).color)
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
        .foregroundStyle(colors.secondaryOnSky(atTop: true).color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .layoutPriority(-1)
    }
  }

  private func footer(symbol: String, text: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .font(.system(size: 11))
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
      Text(verbatim: text)
        .font(.footnote)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Spacer(minLength: 0)
    }
    .foregroundStyle(colors.secondaryOnSky(atTop: false).color)
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
      top(eyebrow: Self.nowBadge(labels.now, palette: palette), glyph: event.kind)
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
      switch MenuHeroFooter(
        alerts: display.alerts(for: event), isPrayer: event.kind.isPrayer,
        isApproaching: isApproaching, silentMode: display.settings.silentMode)
      {
      case .adhan:
        footer(symbol: "bell.fill", text: format("menu.hero.adhanAt", time(event)))
      case .reminder(let before):
        footer(
          symbol: "alarm",
          text: format(
            "menu.hero.reminderBefore",
            MenuDuration.reminder(minutes: before, locale: display.locale)))
      case .none:
        EmptyView()
      }
    }
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
      eyebrow: HStack(spacing: 6) {
        Image(systemName: "speaker.wave.2.fill")
          .font(.system(size: 10))
          .frame(width: 13, height: 13)
        Text(verbatim: display.playingTitle ?? "")
          .font(.subheadline.weight(.semibold))
      }
      .foregroundStyle(colors.phase.text.color),
      glyph: event.kind)
    nameLine(display.name(of: event), when: time(event))
    // Stop: the native prominent push button, 28 pt tall, in `accent/fill`.
    Button(action: onStop) {
      Text(verbatim: display.labels.stopShort)
        .font(.body.weight(.medium))
        .foregroundStyle(palette.labelOnAccent.color)
    }
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .tint(palette.accentFill.color)
    .keyboardShortcut(.defaultAction)
    .menuPointerCursor()
    .accessibilityLabel(Text(verbatim: display.labels.stopAudio))
    // The adhan, not yet its du'a: the du'a follows it when it's on.
    if playback.slot == .alert, !playback.isDua, Preferences.shared.duaEnabled {
      footer(
        symbol: "speaker.wave.2.fill",
        text: localizedString("menu.hero.duaFollows", locale: display.locale))
    } else if playback.slot != .alert, let offset = playback.offsetMinutes {
      // A reminder says how far it is from its prayer: "10m before".
      footer(
        symbol: "alarm",
        text: display.text.offsetPhrase(offset, before: playback.slot == .preReminder))
    }
  }

  /// The next prayer's time isn't known: a dash, and why, when the day says.
  @ViewBuilder
  private var unknown: some View {
    let next = unknownNext
    top(eyebrow: eyebrowText(display.labels.nextPrayer), glyph: next?.kind)
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(verbatim: "—")
        .font(.title)
        .foregroundStyle(palette.labelPrimary.color)
      Spacer(minLength: 6)
      Text(verbatim: display.labels.nextUnknown)
        .font(.body.weight(.semibold))
        .foregroundStyle(palette.labelPrimary.color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    if next?.reason == .calculationUnavailable {
      footer(
        symbol: "questionmark.circle",
        text: localizedString("menu.row.missing", locale: display.locale))
    }
  }

  /// The prayer the schedule couldn't give that comes next today, and why.
  private var unknownNext: (kind: PrayerKind, reason: ScheduleGapReason)? {
    guard case .available(let day, .partial(let missing)) = display.day else { return nil }
    let passed = day.events.filter { $0.time <= display.date }.map(\.kind).max()
    return
      missing
      .filter { kind, _ in passed.map { kind > $0 } ?? true }
      .min { $0.key < $1.key }
      .map { ($0.key, $0.value) }
  }
}

/// The footer beneath the next prayer's countdown: the adhan's time while it approaches, a
/// before-reminder otherwise, else the adhan's time. Silent mode drops the adhan, which
/// doesn't sound, and keeps the reminder, whose banner still shows.
enum MenuHeroFooter: Equatable {
  case adhan
  case reminder(minutes: Int)
  case none

  init(alerts: PrayerAlerts, isPrayer: Bool, isApproaching: Bool, silentMode: Bool) {
    if isApproaching {
      self = alerts.alert && !silentMode ? .adhan : .none
    } else if let before = alerts.beforeMinutes {
      self = .reminder(minutes: before)
    } else if alerts.alert, isPrayer, !silentMode {
      self = .adhan
    } else {
      self = .none
    }
  }
}

/// The approaching card's rim, breathing in the accent. Each approach inserts a new rim,
/// whose own state starts the breath again.
private struct MenuBreathingRim: View {
  static let width: CGFloat = 1.5
  let color: ThemeColor
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var breathing = false

  var body: some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
      .strokeBorder(
        color.color.opacity(reduceMotion ? 1 : (breathing ? 1 : 0.45)), lineWidth: Self.width
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

/// The prayer glyphs' point sizes, which draw them as large as Figma does inside their
/// frames: 18 pt in a row, 24 pt on the card.
enum MenuGlyphMetrics {
  static let row: CGFloat = 10
  static let hero: CGFloat = 13.5
}

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
      MenuMissingRow(
        kind: configuration.kind, name: configuration.name, display: display, colors: colors)
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

  @FocusState private var bellFocused: Bool
  /// Whether the toggle's focus came from the keyboard (Tab), which shows the ring; the focus
  /// a window gives its first control as it opens doesn't.
  @State private var keyboardFocused = false

  private var palette: SalahPalette { colors.palette }

  var body: some View {
    HStack(spacing: 8) {
      PrayerGlyph(kind: event.kind)
        .font(.system(size: MenuGlyphMetrics.row))
        .foregroundStyle(glyphColor.color)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
      HStack(spacing: 6) {
        name
          .font(.body.weight(isStrong ? .semibold : .regular))
          .foregroundStyle((role == .passed ? palette.labelSecondary : palette.labelPrimary).color)
          .lineLimit(1)
          .fixedSize()
        if let detail {
          Text(verbatim: detail)
            .font(.subheadline)
            .foregroundStyle(detailColor.color)
            .lineLimit(1)
            .fixedSize()
        }
      }
      // A set minimum keeps the frame at the space the row gives it, whatever the text.
      .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
      .clipped()
      // The badge lies over the text's trailing end, whole, so a long detail runs under it.
      .overlay(alignment: .trailing) {
        if role == .current {
          MenuHero.nowBadge(display.labels.now, palette: palette).fixedSize()
        }
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
    .modifier(MenuRowInteraction(palette: palette, focused: keyboardFocused))
    .onChange(of: bellFocused) { _, focused in
      keyboardFocused = focused && NSApp.currentEvent?.type == .keyDown
    }
  }

  private var isStrong: Bool { role == .current || role == .next }

  private var background: Color {
    switch role {
    case .current: colors.phase.tintSubtle.color
    case .next: palette.accentSubtle.color
    case .passed, .upcoming: .clear
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
      return String(
        format: localizedString("today.row.in", locale: display.locale), locale: display.locale,
        MenuDuration.until(event.time.timeIntervalSince(display.date), locale: display.locale)
          .bidiIsolated)
    case .current, .passed:
      guard role == .current || display.prayerState?.previous?.id == event.id else { return nil }
      // An adhan can start a moment before its time; it has begun all the same.
      return MenuDuration.ago(
        max(display.date.timeIntervalSince(event.time), 0), locale: display.locale)
    case .upcoming:
      return nil
    }
  }

  @ViewBuilder
  private var bell: some View {
    if event.kind.isPrayer {
      // Silent mode draws every bell off: nothing sounds.
      let isOn = display.alerts(for: event).alert && !display.settings.silentMode
      let label = MenuBellLabel.name(
        prayer: display.name(of: event), day: day, locale: display.locale)
      Button(action: onToggleAlert) {
        Image(systemName: isOn ? "bell.fill" : "bell.slash")
          .font(.system(size: MenuBellLabel.symbolSize))
          .foregroundStyle(bellColor(isOn: isOn).color)
          .frame(width: MenuBellLabel.size, height: MenuBellLabel.size)
          // The click target reaches 2 pt past the 15 pt symbol frame.
          .padding(2)
          .contentShape(Rectangle())
          .padding(-2)
      }
      .buttonStyle(.plain)
      // The row draws the focus ring, in the accent.
      .focusEffectDisabled()
      .focused($bellFocused)
      // In silent mode the bells draw off and turn nothing on or off.
      .disabled(display.settings.silentMode)
      .menuPointerCursor()
      .help(Text(verbatim: label))
      .accessibilityLabel(Text(verbatim: label))
      .accessibilityValue(
        Text(
          verbatim: MenuBellLabel.value(
            isOn: display.alerts(for: event).alert, locale: display.locale)))
    } else {
      Image(systemName: "bell.slash")
        .font(.system(size: MenuBellLabel.symbolSize))
        .foregroundStyle(palette.labelTertiary.color)
        .frame(width: MenuBellLabel.size, height: MenuBellLabel.size)
        .accessibilityHidden(true)
    }
  }

  private func bellColor(isOn: Bool) -> ThemeColor {
    guard isOn else { return palette.labelTertiary }
    return isStrong ? palette.accent : palette.labelSecondary
  }
}

/// A row's alert toggle: its 15 pt frame, and what VoiceOver says, "Alert for Asr, on".
enum MenuBellLabel {
  static let size: CGFloat = 15
  /// The bell's point size, which draws it as large as Figma's.
  static let symbolSize: CGFloat = 13.5

  /// "Alert for Asr"; a row of another day leads with it: "Tomorrow · Alert for Fajr".
  static func name(prayer: String, day: String?, locale: Locale) -> String {
    let name = String(
      format: localizedString("menu.row.alertFor", locale: locale), locale: locale, prayer)
    return [day, name].compactMap { $0 }.joined(separator: " · ")
  }

  static func value(isOn: Bool, locale: Locale) -> String {
    localizedString(isOn ? "menu.row.alert.on" : "menu.row.alert.off", locale: locale)
  }
}

/// Figma's row interaction: `fill/quaternary` while hovered, `fill/tertiary` while pressed,
/// and the accent focus ring while the row's toggle has keyboard focus.
private struct MenuRowInteraction: ViewModifier {
  let palette: SalahPalette
  let focused: Bool

  @State private var hovering = false
  @GestureState private var pressed = false

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    content
      .overlay {
        shape.fill(
          pressed
            ? palette.fillTertiary.color : hovering ? palette.fillQuaternary.color : .clear
        )
        .allowsHitTesting(false)
      }
      .overlay {
        if focused {
          shape.strokeBorder(palette.accent.color, lineWidth: 2.5).allowsHitTesting(false)
        }
      }
      .contentShape(shape)
      .onHover { hovering = $0 }
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .updating($pressed) { _, pressed, _ in pressed = true })
  }
}

/// A row for a prayer the calculation can't give today: its glyph and name, "Doesn't occur
/// today", a dash, and its alert setting.
struct MenuMissingRow: View {
  let kind: PrayerKind
  let name: Text
  let display: SalahDisplay
  let colors: SalahColors

  var body: some View {
    let palette = colors.palette
    let isOn =
      kind.isPrayer && display.settings.alerts[kind]?.alert == true
      && !display.settings.silentMode
    HStack(spacing: 8) {
      PrayerGlyph(kind: kind)
        .font(.system(size: MenuGlyphMetrics.row))
        .foregroundStyle(palette.labelTertiary.color)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
      HStack(spacing: 6) {
        name.font(.body)
        Text(verbatim: localizedString("menu.row.missing", locale: display.locale))
          .font(.subheadline)
      }
      .foregroundStyle(palette.labelSecondary.color)
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)
      Text(verbatim: "—")
        .font(.body.monospacedDigit())
        .foregroundStyle(palette.labelSecondary.color)
        .accessibilityLabel(Text(verbatim: display.labels.notAvailable))
      Image(systemName: isOn ? "bell.fill" : "bell.slash")
        .font(.system(size: MenuBellLabel.symbolSize))
        .foregroundStyle((isOn ? palette.labelSecondary : palette.labelTertiary).color)
        .frame(width: MenuBellLabel.size, height: MenuBellLabel.size)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .frame(minHeight: 28)
    .accessibilityElement(children: .combine)
  }
}
