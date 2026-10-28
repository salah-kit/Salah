import SalahCore
import SalahUI
import SwiftUI

/// A prayer on its platter: the next one on the gold wash with its countdown, the one that
/// just started on the phase's wash. When the name and the time no longer fit on one line, at
/// the larger text sizes, the time moves under the name and the name wraps instead of being
/// cut.
struct WatchPrayerRow: View {
  let row: WatchPrayerPresentation.Row
  let phase: SalahPhase
  @Environment(\.colorSchemeContrast) private var contrast
  private var theme: WatchTheme { WatchTheme(contrast: contrast) }

  private typealias State = WatchPrayerPresentation.RowState

  var body: some View {
    let colors = SalahColors(phase: phase, scheme: .dark, contrast: contrast).phase
    ViewThatFits(in: .horizontal) {
      HStack(spacing: WatchMetrics.rowGap) {
        glyph(colors)
        VStack(alignment: .leading, spacing: 0) {
          name.fixedSize()
          detail(colors, wraps: false)
        }
        Spacer(minLength: 4)
        time.fixedSize()
      }
      HStack(alignment: .top, spacing: WatchMetrics.rowGap) {
        glyph(colors)
        VStack(alignment: .leading, spacing: 0) {
          name.fixedSize(horizontal: false, vertical: true)
          detail(colors, wraps: true)
          time
        }
        Spacer(minLength: 0)
      }
    }
    .padding(.horizontal, WatchMetrics.rowPaddingH)
    .padding(.vertical, WatchMetrics.rowPaddingV)
    .frame(maxWidth: .infinity, minHeight: WatchMetrics.rowHeight, alignment: .leading)
    .background(
      background(colors),
      in: RoundedRectangle(cornerRadius: WatchMetrics.rowRadius, style: .continuous)
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: row.accessibility))
    .accessibilityIdentifier("row." + row.id.rawValue)
  }

  private var isEmphasized: Bool {
    [State.next, .approaching, .current].contains(row.state)
  }

  private var isQuiet: Bool { [State.past, .missing].contains(row.state) }

  private func glyph(_ colors: SalahPhase.Colors) -> some View {
    let color: Color =
      switch row.state {
      case .past, .missing: theme.labelTertiary
      case .upcoming: theme.labelSecondary
      case .next, .approaching: theme.accent
      case .current: colors.tint.color
      }
    return WatchPrayerGlyph(name: row.glyph, size: WatchMetrics.rowGlyph, color: color)
  }

  private var name: some View {
    Text(verbatim: row.name)
      .font(.body.weight(isEmphasized ? .semibold : .regular))
      .foregroundStyle(isQuiet ? theme.labelSecondary : theme.labelPrimary)
  }

  /// "in 2:16", "Now" or "Not today" under the name: on one line beside the time, or
  /// wrapping under it.
  @ViewBuilder
  private func detail(_ colors: SalahPhase.Colors, wraps: Bool) -> some View {
    if let detail = row.detail {
      let color: Color =
        switch row.state {
        case .next, .approaching: theme.accentText
        case .current: colors.text.color
        case .past, .upcoming, .missing: theme.labelSecondary
        }
      Text(verbatim: detail)
        .watchFootnote2()
        .foregroundStyle(color)
        .fixedSize(horizontal: !wraps, vertical: true)
    }
  }

  private var time: some View {
    Text(verbatim: row.time)
      .font(.body.monospacedDigit())
      .foregroundStyle(isQuiet ? theme.labelSecondary : theme.labelPrimary)
  }

  private func background(_ colors: SalahPhase.Colors) -> Color {
    switch row.state {
    case .next, .approaching: theme.accentSubtle
    case .current: colors.tintSubtle.color
    case .past, .upcoming, .missing: theme.fillTertiary
    }
  }
}
