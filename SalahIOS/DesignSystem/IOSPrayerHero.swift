import SalahUI
import SwiftUI

enum IOSPrayerHeroState: Equatable {
  case normal, approaching, current, playing, unavailable
}

/// The same focus on iPhone and iPad: a countdown, a just-started prayer, or active audio.
struct IOSPrayerHero: View {
  let eyebrow: String
  let name: String
  let subtitle: String
  let countdown: String
  let glyph: String
  let phase: SalahPhase
  var state: IOSPrayerHeroState = .normal
  var footer: String? = nil
  var stopTitle: String? = nil
  var onStop: (() -> Void)? = nil
  var accessibilityIdentifierPrefix = "today"
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let colors = SalahColors(phase: phase, scheme: scheme, contrast: contrast)
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        if state == .playing {
          Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 18))
            .foregroundStyle(colors.phase.text.color)
            .accessibilityHidden(true)
        }
        Text(verbatim: eyebrow)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(state == .playing ? colors.phase.text.color : IOSTheme.labelSecondary)
        Spacer(minLength: 0)
        IOSPrayerGlyph(name: glyph, size: 34)
          .foregroundStyle(colors.phase.tint.color)
      }
      Text(verbatim: name)
        .font(.largeTitle.bold())
        .foregroundStyle(IOSTheme.labelPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("\(accessibilityIdentifierPrefix).name")
      Text(verbatim: subtitle)
        .font(.title3)
        .foregroundStyle(IOSTheme.labelSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if state != .playing {
        IOSHeroCountdown(
          value: countdown, color: countdownColor(colors), reduceMotion: reduceMotion,
          identifier: "\(accessibilityIdentifierPrefix).countdown"
        )
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
      }
      if let onStop, let stopTitle {
        Button(action: onStop) {
          Text(verbatim: stopTitle)
            .frame(maxWidth: .infinity)
            .foregroundStyle(IOSTheme.labelOnAccent)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .tint(IOSTheme.accentFill)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityIdentifier("\(accessibilityIdentifierPrefix).stopAudio")
      }
      if let footer, !footer.isEmpty {
        Label {
          Text(verbatim: footer).fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: state == .playing ? "speaker.wave.2.fill" : "alarm")
        }
        .font(.footnote)
        .foregroundStyle(IOSTheme.labelSecondary)
        .padding(.top, 8)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(colors.sky, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay {
      if state == .approaching {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
          .strokeBorder(IOSTheme.accent, lineWidth: 2)
          .allowsHitTesting(false)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func countdownColor(_ colors: SalahColors) -> Color {
    switch state {
    case .approaching: IOSTheme.accentText
    case .current: colors.phase.text.color
    default: IOSTheme.labelPrimary
    }
  }
}

/// Its scaled metric reads the capped environment on this view, so AX4 and AX5 keep
/// the AX3 display size while surrounding titles and descriptions keep growing.
private struct IOSHeroCountdown: View {
  let value: String
  let color: Color
  let reduceMotion: Bool
  let identifier: String
  @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64

  var body: some View {
    Text(verbatim: value)
      .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
      .foregroundStyle(color)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .contentTransition(reduceMotion ? .identity : .numericText())
      .accessibilityIdentifier(identifier)
  }
}
