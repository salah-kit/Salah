import SalahCore
import SalahUI
import SwiftUI

/// The watch's semantic colors: the design system's dark palette (`SalahPalette`), with
/// Increase Contrast. Salah's watch design is always dark, and the watchOS asset compiler
/// keeps one appearance of a color set, so the watch reads the tokens from code rather than
/// the iPhone's color sets.
nonisolated struct WatchTheme {
  let palette: SalahPalette

  init(contrast: ColorSchemeContrast) {
    palette = SalahPalette(isDark: true, increasedContrast: contrast == .increased)
  }

  var labelPrimary: Color { palette.labelPrimary.color }
  var labelSecondary: Color { palette.labelSecondary.color }
  var labelTertiary: Color { palette.labelTertiary.color }
  var labelOnAccent: Color { palette.labelOnAccent.color }
  var accent: Color { palette.accent.color }
  var accentText: Color { palette.accentText.color }
  var accentFill: Color { palette.accentFill.color }
  var accentSubtle: Color { palette.accentSubtle.color }
  var fillTertiary: Color { palette.fillTertiary.color }
  var background: Color { .black }
  /// The Qibla dial's face.
  var dial: Color { palette.groupedSecondary.color }
}

/// The watchOS layout tokens (`Design/tokens/layout.watchos.json`) and the screens' own
/// measurements, in points.
nonisolated enum WatchMetrics {
  /// The screens' content inset from the display's edges, and the gap between platters.
  static let screenInset: CGFloat = 6
  static let stackGap: CGFloat = 6
  /// The hero: its padding, the gap between its lines and its corner radius.
  static let heroPadding: CGFloat = 12
  static let heroGap: CGFloat = 2
  static let heroRadius: CGFloat = 24
  static let heroGlyph: CGFloat = 26
  /// A prayer row platter.
  static let rowHeight: CGFloat = 48
  static let rowRadius: CGFloat = 20
  static let rowPaddingH: CGFloat = 12
  static let rowPaddingV: CGFloat = 8
  static let rowGap: CGFloat = 8
  static let rowGlyph: CGFloat = 22
  /// The full-width Stop button.
  static let controlHeight: CGFloat = 44
}

/// The watch's numerals: the hero's countdown is watchOS Title 2, rounded and semibold
/// (`watchos/numeric/countdown`), so it scales with the text size.
nonisolated enum WatchNumeral {
  static var countdown: Font {
    .system(.title2, design: .rounded).weight(.semibold).monospacedDigit()
  }
}

/// watchOS Footnote 2: 12 pt, scaled relative to Footnote, for the details under a row's
/// name and the Now badge. `Font.footnote` is Footnote 1, a step larger.
struct WatchFootnote2: ViewModifier {
  var weight: Font.Weight = .regular
  @ScaledMetric(relativeTo: .footnote) private var size = 12.0

  func body(content: Content) -> some View {
    content.font(.system(size: size, weight: weight))
  }
}

extension View {
  func watchFootnote2(weight: Font.Weight = .regular) -> some View {
    modifier(WatchFootnote2(weight: weight))
  }
}

/// The time of day's sky behind a screen: the phase's top color fading to black by the
/// middle of the display, as the watch screens draw it.
struct WatchSkyBackground: View {
  var phase: SalahPhase
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    let colors = SalahColors(phase: phase, scheme: .dark, contrast: contrast)
    LinearGradient(
      stops: [
        .init(color: colors.phase.skyTop.color, location: 0),
        .init(color: WatchTheme(contrast: contrast).background, location: 0.55),
      ], startPoint: .top, endPoint: .bottom
    )
    .ignoresSafeArea()
    .accessibilityHidden(true)
  }
}

/// Custom prayer symbols never mirror: they're the same marks in every language.
struct WatchPrayerGlyph: View {
  let name: String
  var size: CGFloat
  var color: Color

  var body: some View {
    Image(name, bundle: AppResources.bundle)
      .symbolRenderingMode(.hierarchical)
      // The custom-symbol template includes its optical margins, so its em is smaller than
      // the slot it fills.
      .font(.system(size: size * 0.58))
      .foregroundStyle(color)
      .frame(width: size, height: size)
      .environment(\.layoutDirection, .leftToRight)
      .accessibilityHidden(true)
  }
}

nonisolated extension PrayerEvent {
  /// The glyph of the event: Jumu'ah's own on a Friday that declares it.
  var glyphName: String {
    observance == .jumuah ? "salah.jumuah" : "salah." + kind.rawValue
  }
}

nonisolated extension PrayerKind {
  /// The kind's own glyph, for a row the day couldn't give a time.
  var glyphName: String { "salah." + rawValue }
}
