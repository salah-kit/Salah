import SalahCore
import SalahUI
import SwiftUI

/// One prayer in Today's list: the glyph, the name and its relative time, and the time.
/// Rows take focus because pressing one opens that prayer's adhan setting. At accessibility
/// text sizes the time goes under the name.
struct TVPrayerRow: View {
  let event: PrayerEvent
  let presentation: TVPrayerPresentation
  var action: () -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @ScaledMetric(relativeTo: .headline) private var glyphSize: CGFloat = 44

  var body: some View {
    let status = presentation.status(of: event)
    Button(action: action) {
      content(status: status)
    }
    .buttonStyle(
      TVPlatterButtonStyle(
        background: isNext(status) ? TVTheme.accentSubtle : .clear,
        rim: isApproaching(status) ? TVTheme.accentStroke : nil)
    )
    .accessibilityLabel(presentation.rowAccessibility(for: event))
    .accessibilityHint(
      presentation.copy("Opens this prayer’s sound setting", "يفتح إعداد صوت هذه الصلاة")
    )
    .accessibilityIdentifier("today.row.\(event.kind.rawValue)")
  }

  @ViewBuilder
  private func content(status: PrayerEventStatus) -> some View {
    let emphasis = isNext(status)
    let color = labelColor(status)
    let name = Text(verbatim: presentation.display.name(of: event))
      .font(.headline.weight(emphasis ? .bold : .medium))
      .foregroundStyle(color)
    let time = Text(verbatim: presentation.time.time(event.time))
      .font(.headline.weight(emphasis ? .bold : .medium))
      .monospacedDigit()
      .foregroundStyle(color)
    let detail = presentation.detail(for: event).map {
      Text(verbatim: $0)
        .font(.caption.weight(isApproaching(status) ? .bold : .medium))
        .foregroundStyle(emphasis ? TVTheme.accentText : TVTheme.labelSecondary)
    }
    if dynamicTypeSize.isAccessibilitySize {
      HStack(alignment: .center, spacing: 22) {
        glyph(status)
        VStack(alignment: .leading, spacing: 4) {
          name
          HStack(spacing: 18) {
            time
            detail
          }
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      HStack(spacing: 22) {
        glyph(status)
        name
        detail
        Spacer(minLength: 16)
        time
      }
      .lineLimit(1)
      .padding(.horizontal, 28)
      .frame(height: TVMetrics.rowHeight)
      .frame(maxWidth: .infinity)
    }
  }

  private func glyph(_ status: PrayerEventStatus) -> some View {
    let colors = SalahColors(
      phase: presentation.display.settings.followsTimeOfDay ? phase : .neutral, scheme: scheme,
      contrast: contrast)
    let tint: Color =
      switch status {
      case .next: TVTheme.accentText
      case .passed: TVTheme.labelTertiary
      default: colors.phase.tint.color
      }
    return TVPrayerGlyph(name: event.glyphName, size: glyphSize, color: tint)
  }

  /// The time of day the event opens, for its glyph.
  private var phase: SalahPhase {
    SalahPhase.at(event.time, events: presentation.display.listedDay?.events ?? [event])
  }

  private func labelColor(_ status: PrayerEventStatus) -> Color {
    switch status {
    case .passed: TVTheme.labelSecondary
    default: TVTheme.labelPrimary
    }
  }

  private func isNext(_ status: PrayerEventStatus) -> Bool {
    if case .next = status { return true }
    return false
  }

  private func isApproaching(_ status: PrayerEventStatus) -> Bool {
    if case .next(approaching: true) = status { return event.kind.isPrayer }
    return false
  }
}
