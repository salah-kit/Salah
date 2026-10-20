import SwiftUI

/// Shown in the focus position while an adhan / reminder / du'ā' plays. Unlike the
/// widget's full-panel `WidgetStopContent` (a single Stop intent), the in-process
/// menu bar keeps the schedule visible and offers a real Stop button beside the
/// playing state, tinted by the slot tone.
struct MenuStopCard: View {
  let title: String
  let subtitle: String
  let tone: SalahWidgetTone
  let labels: SalahWidgetLabels
  let colors: SalahWidgetColors
  let onStop: () -> Void

  private var toneColor: Color { tone.color(colors) }

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: title)
          .font(.system(.subheadline, design: .serif, weight: .semibold))
          .salahInk(.primary.on(tone, opacity: SalahWidgetTint.card))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(verbatim: subtitle)
          .font(.caption2)
          .salahInk(.secondary.on(tone, opacity: SalahWidgetTint.card))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      Spacer(minLength: 8)
      Button(action: onStop) {
        HStack(spacing: 5) {
          Image(systemName: "stop.fill")
            .salahInk(stopInk.glyph)
          Text(verbatim: labels.stopShort)
            .salahInk(stopInk)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(toneColor.opacity(0.18)))
        .overlay(Capsule().strokeBorder(toneColor.opacity(0.55), lineWidth: 1))
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .menuPointerCursor()
      .accessibilityLabel(Text(verbatim: labels.stopAudio))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .salahHeroCard(toneColor: toneColor, accent: colors.accent)
  }

  private var stopInk: SalahWidgetInk {
    .tone(tone).on(tone, opacity: SalahWidgetTint.stacked(0.18, over: SalahWidgetTint.card))
  }
}
