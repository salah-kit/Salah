import SalahCore
import SalahUI
import SwiftUI

/// The first screen's card: the next prayer on the time of day's sky, with its countdown.
/// It counts up in the phase's color when a prayer has just started, turns gold in the last
/// 15 minutes, and holds Stop while the adhan plays.
struct WatchPrayerHero: View {
  let presentation: WatchPrayerPresentation
  var onStop: () -> Void = {}
  @Environment(\.isLuminanceReduced) private var isLuminanceReduced
  @Environment(\.colorSchemeContrast) private var contrast
  private var theme: WatchTheme { WatchTheme(contrast: contrast) }

  private var mode: WatchPrayerPresentation.HeroMode { presentation.heroMode }

  var body: some View {
    let colors = SalahColors(
      phase: presentation.display.phase, scheme: .dark, contrast: contrast)
    VStack(alignment: .leading, spacing: WatchMetrics.heroGap) {
      VStack(alignment: .leading, spacing: WatchMetrics.heroGap) {
        HStack(spacing: 6) {
          eyebrow(phaseText: colors.phase.text.color)
          Spacer(minLength: 0)
          if let event = presentation.heroEvent {
            WatchPrayerGlyph(
              name: event.glyphName, size: WatchMetrics.heroGlyph,
              color: colors.phase.tint.color)
          }
        }
        Text(verbatim: presentation.heroName)
          .font(.title2)
          .foregroundStyle(theme.labelPrimary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(verbatim: presentation.heroTime)
          .font(.footnote)
          .foregroundStyle(theme.labelSecondary)
        if let countdown = presentation.countdown(showsSeconds: !isLuminanceReduced) {
          Text(verbatim: countdown)
            .font(WatchNumeral.countdown)
            .foregroundStyle(countdownColor(phaseText: colors.phase.text.color))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
      }
      // One element, read as a sentence; Stop is its own.
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: presentation.heroAccessibility))
      .accessibilityIdentifier("hero")
      if mode == .playing {
        stopButton
      }
    }
    .padding(WatchMetrics.heroPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      colors.sky,
      in: RoundedRectangle(cornerRadius: WatchMetrics.heroRadius, style: .continuous)
    )
    .overlay {
      if mode == .approaching {
        RoundedRectangle(cornerRadius: WatchMetrics.heroRadius, style: .continuous)
          .strokeBorder(theme.accent, lineWidth: 2)
      }
    }
  }

  @ViewBuilder
  private func eyebrow(phaseText: Color) -> some View {
    if mode == .justStarted {
      // The Now badge.
      Text(verbatim: presentation.eyebrow)
        .watchFootnote2(weight: .semibold)
        .foregroundStyle(theme.labelOnAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(theme.accentFill, in: Capsule())
    } else {
      Text(verbatim: presentation.eyebrow)
        .font(.footnote)
        .foregroundStyle(mode == .playing ? phaseText : theme.labelSecondary)
        .lineLimit(1)
    }
  }

  private func countdownColor(phaseText: Color) -> Color {
    switch mode {
    case .approaching: theme.accentText
    case .justStarted: phaseText
    default: theme.labelPrimary
    }
  }

  private var stopButton: some View {
    Button(action: onStop) {
      Text(verbatim: presentation.copy("Stop", "إيقاف"))
        .font(.headline)
        .foregroundStyle(theme.labelOnAccent)
        .frame(maxWidth: .infinity, minHeight: WatchMetrics.controlHeight)
        .background(theme.accentFill, in: Capsule())
    }
    .buttonStyle(.plain)
    .padding(.top, 4)
    .accessibilityIdentifier("hero.stop")
  }
}
