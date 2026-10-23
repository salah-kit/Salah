import SalahUI
import SwiftUI

enum IOSPrayerRowState: Equatable {
  case past, next, approaching, current, upcoming, missing
}

/// One day-list row, with an independent accessible alert control.
struct IOSPrayerRow: View {
  let name: String
  let time: String
  var detail: String? = nil
  var state: IOSPrayerRowState = .upcoming
  let glyph: String
  var alertEnabled: Bool
  var currentLabel: String? = nil
  var dayOffset: String? = nil
  var phase: SalahPhase = .neutral
  var alertAccessibilityLabel: String? = nil
  var onAlert: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.locale) private var locale

  private var emphasized: Bool {
    state == .next || state == .approaching || state == .current
  }

  private var secondary: Bool { state == .past || state == .missing }

  var body: some View {
    let colors = SalahColors(phase: phase, scheme: scheme, contrast: contrast)
    HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
      HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 12) {
        IOSPrayerGlyph(name: glyph)
          .foregroundStyle(glyphColor(colors))
          .padding(.top, typeSize.isAccessibilitySize ? 3 : 0)
        VStack(alignment: .leading, spacing: 1) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: name)
              .font(.body.weight(emphasized ? .semibold : .regular))
              .foregroundStyle(textColor(colors))
              .fixedSize(horizontal: false, vertical: true)
            if state == .current, let currentLabel {
              Text(verbatim: currentLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(IOSTheme.labelOnAccent)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(IOSTheme.accentFill, in: Capsule())
            }
          }
          if typeSize.isAccessibilitySize { timeLabel(colors) }
          if let detail, !detail.isEmpty {
            Text(verbatim: detail)
              .font(.footnote)
              .foregroundStyle(detailColor(colors))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if !typeSize.isAccessibilitySize { timeLabel(colors) }
      }
      .accessibilityElement(children: .combine)
      Color.clear
        .frame(width: 20, height: 20)
        .overlay {
          Button(action: onAlert) {
            Image(systemName: alertEnabled ? "bell.fill" : "bell.slash")
              .font(.system(size: 17))
              .foregroundStyle(alertColor(colors))
              .frame(width: IOSMetrics.hitTarget, height: IOSMetrics.hitTarget)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(alertAccessibilityLabel ?? "Alert for \(name)")
          .accessibilityValue(alertValue)
          .accessibilityAddTraits(alertEnabled ? .isSelected : [])
          .disabled(state == .missing)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 9)
    .frame(minHeight: IOSMetrics.rowHeight)
    .background(backgroundColor(colors), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var alertValue: String {
    let labels = SalahWidgetLabels.localized(
      forLanguageCode: locale.language.languageCode?.identifier)
    return alertEnabled ? labels.alertOn : labels.alertOff
  }

  private func timeLabel(_ colors: SalahColors) -> some View {
    HStack(alignment: .top, spacing: 3) {
      Text(verbatim: time)
        .font(.body.weight(emphasized ? .semibold : .regular).monospacedDigit())
        .foregroundStyle(textColor(colors))
        .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
      if let dayOffset {
        Text(verbatim: dayOffset)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(IOSTheme.labelSecondary)
      }
    }
  }

  private func textColor(_ colors: SalahColors) -> Color {
    if state == .current { return colors.phase.text.color }
    return secondary ? IOSTheme.labelSecondary : IOSTheme.labelPrimary
  }

  private func glyphColor(_ colors: SalahColors) -> Color {
    if state == .current { return colors.phase.tint.color }
    if state == .next || state == .approaching { return IOSTheme.accent }
    return secondary ? IOSTheme.labelSecondary : IOSTheme.labelPrimary
  }

  private func detailColor(_ colors: SalahColors) -> Color {
    if state == .current { return colors.phase.text.color }
    return state == .next || state == .approaching ? IOSTheme.accentText : IOSTheme.labelSecondary
  }

  private func alertColor(_ colors: SalahColors) -> Color {
    alertEnabled ? glyphColor(colors) : IOSTheme.labelSecondary
  }

  private func backgroundColor(_ colors: SalahColors) -> Color {
    switch state {
    case .next, .approaching: IOSTheme.accentSubtle
    case .current: colors.phase.tintSubtle.color
    default: .clear
    }
  }
}
