import SalahCore
import SalahUI
import SwiftUI

/// The inline expanded focus in the menu-bar living schedule - the next event's
/// calm count-down, a just-started prayer's green count-up, or the end-of-day
/// Tomorrow card. Mirrors the widget's (private) `ActiveCardView` large layout on
/// the shared `salahHeroCard` surface, refined for the menu bar: a live-ticking
/// countdown, an alert toggle for the focused prayer, and a gentle imminent pulse
/// (gated on Reduce Motion).
struct MenuHeroCard: View {
  let focus: SalahDisplay.Focus
  let name: Text?
  let time: Text?
  let display: SalahDisplay
  let colors: SalahWidgetColors
  /// Toggles the focused prayer's alert; nil for the Tomorrow card and sunrise.
  var onToggleAlert: (() -> Void)? = nil

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pulsing = false

  private var labels: SalahWidgetLabels { display.labels }
  private var event: PrayerEvent { focus.event }
  private var date: Date { display.date }
  private var alertEnabled: Bool { display.alerts(for: event).alert }

  private var tone: SalahWidgetTone {
    switch focus {
    case .countUp: return .playingPrayerAudio  // green
    case .countdown: return isTomorrow ? .normal : display.tone  // normal / imminent
    }
  }
  private var toneColor: Color { tone.color(colors) }
  private var isImminent: Bool {
    if case .countdown = focus { return tone == .imminent }
    return false
  }
  private var isCountUp: Bool { focus.isCountUp }
  private var isTomorrow: Bool { display.focusIsTomorrow }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      statusLine
      nameRow
      timerRow
      reminderRow
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .salahHeroCard(toneColor: toneColor, accent: colors.accent)
    .overlay {
      // A slow breathing border in the final 15 minutes (imminent). Motion only -
      // skipped under Reduce Motion, where the red tone + icon already signal it.
      if isImminent, !reduceMotion {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(toneColor.opacity(pulsing ? 0.85 : 0.25), lineWidth: 1)
          .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: pulsing)
          .onAppear { pulsing = true }
          .allowsHitTesting(false)
      }
    }
  }

  // MARK: Pieces

  @ViewBuilder
  private var statusLine: some View {
    HStack(spacing: 6) {
      if isCountUp {
        InlineBadge(text: labels.now, tint: SalahWidgetTone.prayerColor(colors))
      } else {
        EyebrowLabel(text: isTomorrow ? labels.tomorrow : labels.nextPrayer, accent: colors.accent)
      }
      Spacer(minLength: 8)
      if let onToggleAlert, !isTomorrow {
        Button(action: onToggleAlert) {
          Image(systemName: alertEnabled ? "bell.fill" : "bell.slash")
            .font(.caption)
            .foregroundStyle(alertEnabled ? colors.accent : Color.secondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuPointerCursor()
        .help(Text(verbatim: alertToggleLabel))
        .accessibilityLabel(Text(verbatim: alertToggleLabel))
        .accessibilityValue(Text(verbatim: alertEnabled ? labels.alertOn : labels.alertOff))
      }
    }
  }

  private var nameRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      (name ?? Text(verbatim: "–"))
        .font(.system(.title2, design: .serif, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Spacer(minLength: 6)
      Label {
        (time ?? Text(verbatim: "–")).lineLimit(1).minimumScaleFactor(0.8)
      } icon: {
        Image(systemName: "clock")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .labelStyle(.titleAndIcon)
      .layoutPriority(-1)
    }
  }

  private var timerRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      if isImminent {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.title3)
          .foregroundStyle(toneColor)
          .accessibilityHidden(true)
      }
      MenuLiveCountdown(
        target: event.time, reference: date, color: toneColor,
        font: .system(size: 30, weight: .semibold), bold: isImminent, countingUp: isCountUp)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: countdownAccessibilityLabel))
  }

  @ViewBuilder
  private var reminderRow: some View {
    if !isCountUp, let detail = display.reminderDetail(for: event) {
      Label {
        Text(verbatim: detail).lineLimit(1).minimumScaleFactor(0.7)
      } icon: {
        Image(systemName: "alarm")
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .labelStyle(.titleAndIcon)
    }
  }

  // MARK: Labels

  private var alertToggleLabel: String {
    "\(display.name(of: event)) · \(localizedString("settings.notif.alert.toggle"))"
  }

  /// A spelled-out duration for VoiceOver (the visible timer is the abbreviated
  /// "1:24"), in the display's locale.
  private var countdownAccessibilityLabel: String {
    let duration = PrayerDurationFormat.string(
      abs(event.time.timeIntervalSince(date)), width: .spoken, locale: display.locale)
    if isCountUp {
      return "\(display.name(of: event)) · \(labels.since) \(duration)"
    }
    return "\(display.name(of: event)) · \(duration) \(labels.remaining)"
  }
}
