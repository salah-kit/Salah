import SwiftUI

/// One collapsed prayer in the menu-bar living schedule. Mirrors the widget's
/// (private) `ScheduleRowView` look - alert/state icon + serif name + time, with
/// the next/active tones and a quieter passed treatment - but adds the menu-bar
/// interactivity: the leading bell doubles as an alert toggle, and the row lifts on
/// hover. `sinceText` keeps the most-recent-passed row (the "you are here" anchor)
/// prominent without lowering other rows below readable contrast.
struct MenuScheduleRow: View {
  let name: Text
  let time: Text
  let state: SalahWidgetRowState
  let isSunrise: Bool
  let alertEnabled: Bool
  let colors: SalahWidgetColors
  let labels: SalahWidgetLabels
  var sinceText: String? = nil
  /// Toggles this prayer's alert; nil for prayers that never alert (Sunrise).
  var onToggleAlert: (() -> Void)? = nil

  @State private var hovering = false

  var body: some View {
    HStack(spacing: 10) {
      leadingIcon

      name
        .font(Font.system(.subheadline, design: .serif).weight(weight))
        .salahInk(textInk)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(minWidth: 56, alignment: .leading)

      if state == .current {
        InlineBadge(
          text: labels.now, tint: SalahWidgetTone.prayerColor(colors),
          ink: .tone(.playingPrayerAudio).on(
            .playingPrayerAudio, opacity: SalahWidgetTint.stacked(SalahWidgetTint.badge, over: 0.12)
          ))
      }

      Spacer(minLength: 6)

      // The "since" count-up floats in the gap so the time stays right-aligned in
      // the same column as every other row.
      if let sinceText {
        Text(verbatim: sinceText)
          .font(Font.footnote.monospacedDigit())
          .salahInk(.tone(.playingPrayerAudio).on(tint, opacity: tintOpacity))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .layoutPriority(-1)
        Spacer(minLength: 6)
      }

      time
        .font(Font.subheadline.monospacedDigit())
        .salahInk(timeInk)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(minWidth: 70, alignment: .trailing)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(rowBackground)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
  }

  // MARK: Leading icon / alert toggle

  @ViewBuilder
  private var leadingIcon: some View {
    if isBellToggle, let onToggleAlert {
      Button(action: onToggleAlert) {
        Image(systemName: alertEnabled ? "bell.fill" : "bell.slash")
          .font(.footnote)
          .salahInk(
            (hovering || alertEnabled ? SalahWidgetInk.primary : .secondary).glyph.on(
              tint, opacity: tintOpacity)
          )
          .frame(width: 18, height: 18)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .menuPointerCursor()
      .help(alertToggleLabel)
      .accessibilityLabel(alertToggleLabel)
      .accessibilityValue(Text(verbatim: alertEnabled ? labels.alertOn : labels.alertOff))
    } else {
      Image(systemName: stateIconName)
        .font(.footnote)
        .salahInk(textInk.glyph)
        .frame(width: 18)
        .accessibilityHidden(true)
    }
  }

  /// The leading glyph doubles as the alert toggle only when it is the bell (a
  /// default-state, alertable prayer). `.next`/`.active` rows show their state
  /// glyph instead - the hero already carries the focus, and these are rare
  /// secondary rows.
  private var isBellToggle: Bool {
    guard onToggleAlert != nil, !isSunrise else { return false }
    switch state {
    case .next, .active: return false
    default: return true
    }
  }

  private var stateIconName: String {
    switch state {
    case .active: return "speaker.wave.2.fill"
    case .next: return "arrowtriangle.forward.fill"  // auto-mirrors under RTL
    default:
      if isSunrise { return "sunrise.fill" }
      return alertEnabled ? "bell.fill" : "bell.slash"
    }
  }

  // MARK: Inks over the row's tint

  private var tint: SalahWidgetTone? {
    switch state {
    case .next(let tone), .active(let tone): return tone
    case .current: return .playingPrayerAudio
    default: return nil
    }
  }

  private var tintOpacity: Double {
    switch state {
    case .next: 0.22
    case .active: 0.20
    case .current: 0.12
    default: 0
    }
  }

  private var textInk: SalahWidgetInk {
    let ink: SalahWidgetInk
    switch state {
    case .next(let tone), .active(let tone): ink = .tone(tone)
    case .current: ink = .tone(.playingPrayerAudio)
    case .passed where sinceText == nil: ink = .secondary
    default: ink = .primary
    }
    return ink.on(tint, opacity: tintOpacity)
  }

  private var timeInk: SalahWidgetInk {
    switch state {
    case .active: return .primary.on(tint, opacity: tintOpacity)
    default: return textInk
    }
  }

  private var weight: Font.Weight {
    switch state {
    case .next, .active, .current: return .semibold
    default: return .regular
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
            colors: [c.opacity(0.22), c.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(c.opacity(0.45), lineWidth: 1))
    case .active(let tone):
      RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tone.color(colors).opacity(0.20))
    case .current:
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(SalahWidgetTone.prayerColor(colors).opacity(0.12))
    default:
      if hovering {
        // An outline gives hover feedback without changing the surface behind
        // readable text.
        RoundedRectangle(cornerRadius: 9, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.20), lineWidth: 1)
      } else {
        Color.clear
      }
    }
  }

  private var alertToggleLabel: Text {
    name + Text(verbatim: " · \(localizedString("settings.notif.alert.toggle"))")
  }
}
