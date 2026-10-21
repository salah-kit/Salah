import SalahUI
import SwiftUI

// MARK: - Size

/// App-defined widget size, so the shared content views never depend on
/// WidgetKit's `WidgetFamily`. The extension maps `widgetFamily` to this; the
/// in-app preview passes it directly.
nonisolated enum SalahWidgetSize: Sendable, Hashable {
  case small
  case medium
  case large
}

nonisolated extension SalahWidgetSize {
  /// Normal desktop reference sizes measured on Mac14,10 with macOS 27.0.1.
  /// The in-app preview uses these bounds; the extension uses its host's actual size.
  /// See Design/README.md and https://github.com/salah-kit/Salah/issues/28.
  var desktopPointSize: CGSize {
    switch self {
    case .small: CGSize(width: 164, height: 164)
    case .medium: CGSize(width: 344, height: 164)
    case .large: CGSize(width: 344, height: 344)
    }
  }

  /// The margin between a face's edge and its content, in points.
  static let contentMargin = 14.0
}

/// A theme palette resolved to concrete SwiftUI `Color`s for one appearance.
nonisolated struct SalahWidgetColors: Sendable {
  var accent: Color
  /// Caption labels use semantic ink rather than the decorative accent, whose
  /// 3:1 editor floor is meant for large text. System ink also honors Increase Contrast.
  var accentText: Color { .primary }
  var primary: Color
  var backgroundTop: Color
  var backgroundBottom: Color
  var glow: Color
  var isDark: Bool
  /// The palette these colors come from, for contrast math.
  var palette: SalahWidgetPalette
}

nonisolated extension SalahWidgetTheme {
  /// Resolve the calm palette for the current system appearance, honoring the
  /// theme's `appearance` override (Phase 1 themes are always `.system`).
  func colors(for systemScheme: ColorScheme) -> SalahWidgetColors {
    let dark: Bool
    switch appearance {
    case .system: dark = systemScheme == .dark
    case .alwaysDark: dark = true
    case .alwaysLight: dark = false
    }
    let p = dark ? self.dark : self.light
    return SalahWidgetColors(
      accent: p.accent.color,
      primary: p.primary.color,
      backgroundTop: p.backgroundTop.color,
      backgroundBottom: p.backgroundBottom.color,
      glow: p.glow.color,
      isDark: dark,
      palette: p
    )
  }

  /// The color scheme to force when the theme pins an appearance, so the system
  /// colors (`.secondary`, `.primary`) match the themed background; nil = follow
  /// the system.
  var forcedColorScheme: ColorScheme? {
    switch appearance {
    case .system: nil
    case .alwaysDark: .dark
    case .alwaysLight: .light
    }
  }
}

nonisolated extension View {
  /// Apply a forced color scheme when non-nil; otherwise pass through unchanged.
  @ViewBuilder
  func salahColorScheme(_ scheme: ColorScheme?) -> some View {
    if let scheme {
      environment(\.colorScheme, scheme)
    } else {
      self
    }
  }
}

// MARK: - Functional tones (fixed, never themed)

nonisolated extension SalahWidgetTone {
  // Fixed functional colors - identical across every *theme* by design (a
  // functional color must mean the same thing regardless of theme), but with a
  // dark and a light variant so they keep contrast on every background base. The
  // dark variants are the bright night-backdrop values; the light variants are
  // deepened to stay legible on cream / sand / white.
  static let imminentDark = ThemeColor(1.00, 0.27, 0.23)  // red
  static let imminentLight = ThemeColor(0.80, 0.12, 0.10)
  static let preReminderDark = ThemeColor(1.00, 0.62, 0.04)  // orange
  static let preReminderLight = ThemeColor(0.78, 0.42, 0.00)
  static let prayerDark = ThemeColor(0.20, 0.84, 0.29)  // green
  static let prayerLight = ThemeColor(0.10, 0.52, 0.22)
  static let postReminderDark = ThemeColor(0.75, 0.35, 0.95)  // purple
  static let postReminderLight = ThemeColor(0.54, 0.20, 0.74)
  /// SwiftUI's `.secondary` on macOS 27, which the silent tone draws with: white at 55% in
  /// dark and black at 50% in light, and 70% and 76% with Increase Contrast. Only the
  /// contrast math uses these values.
  static let silentDark = ThemeColor(1, 1, 1, 0.55)
  static let silentLight = ThemeColor(0, 0, 0, 0.50)
  static let silentDarkIncreased = ThemeColor(1, 1, 1, 0.70)
  static let silentLightIncreased = ThemeColor(0, 0, 0, 0.76)

  /// The adhan / count-up "now" green for the given appearance - used directly
  /// for the count-up badge and current row.
  static func prayerColor(_ colors: SalahWidgetColors) -> Color {
    SalahWidgetTone.playingPrayerAudio.components(palette: colors.palette, isDark: colors.isDark)
      .color
  }

  /// The render color for this tone. Only `.normal` is themeable (it is the calm
  /// "primary" / next-prayer color); the functional tones are fixed per-appearance.
  /// Glows, tints and strokes use it as it is; text and glyphs draw it through
  /// `SalahWidgetInk`, which keeps their contrast.
  func color(_ colors: SalahWidgetColors) -> Color {
    switch self {
    case .normal: return colors.primary
    case .silent: return .secondary
    default: return components(palette: colors.palette, isDark: colors.isDark).color
    }
  }

  /// The tone's color as components, for contrast math. Only the silent tone, which is the
  /// system's secondary ink, changes with Increase Contrast.
  func components(
    palette: SalahWidgetPalette, isDark: Bool, contrast: ColorSchemeContrast = .standard
  ) -> ThemeColor {
    switch self {
    case .normal: palette.primary
    case .imminent: isDark ? Self.imminentDark : Self.imminentLight
    case .playingPreReminderAudio: isDark ? Self.preReminderDark : Self.preReminderLight
    case .playingPrayerAudio: isDark ? Self.prayerDark : Self.prayerLight
    case .playingPostReminderAudio: isDark ? Self.postReminderDark : Self.postReminderLight
    case .silent:
      switch (isDark, contrast == .increased) {
      case (true, false): Self.silentDark
      case (false, false): Self.silentLight
      case (true, true): Self.silentDarkIncreased
      case (false, true): Self.silentLightIncreased
      }
    }
  }
}

// MARK: - Tints

/// The opacities of the tone-colored fills text sits on. The views draw with them, and
/// `SalahWidgetInk` checks text against them (at each gradient's strongest end).
nonisolated enum SalahWidgetTint {
  /// The next prayer's large row: a gradient from leading to trailing.
  static let nextRow = 0.22
  static let nextRowTrailing = 0.08
  /// The playing prayer's large row.
  static let activeRow = 0.20
  /// The large row of the prayer that just started.
  static let currentRow = 0.12
  /// The large focus card: a gradient from top-leading to bottom-trailing.
  static let card = 0.24
  static let cardTrailing = 0.07
  /// The Now badge's capsule.
  static let badge = 0.16

  /// The opacity of a tint at `top` over one at `bottom`, in the same color.
  static func stacked(_ top: Double, over bottom: Double) -> Double {
    1 - (1 - top) * (1 - bottom)
  }
}

// MARK: - Backdrop

/// Atmospheric widget backdrop: a vertical night/dawn gradient (from the theme)
/// lit by two soft glows - a tone-colored "horizon" that shifts with the prayer
/// state, and a themed accent highlight standing in for the guiding light.
nonisolated struct SalahWidgetBackground: View {
  let tone: SalahWidgetTone
  let colors: SalahWidgetColors
  /// Flatten the atmosphere only when the owning surface requests it.
  var isSolid = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    if isSolid {
      colors.backgroundTop
    } else {
      let dark = colors.isDark
      ZStack {
        LinearGradient(
          colors: [colors.backgroundTop, colors.backgroundBottom],
          startPoint: .top,
          endPoint: .bottom
        )
        // The soft glows are the "transparency"; flatten to the base gradient when
        // the system asks to reduce transparency.
        if !reduceTransparency {
          RadialGradient(
            colors: [tone.color(colors).opacity(Self.toneGlowOpacity(isDark: dark)), .clear],
            center: .bottomTrailing,
            startRadius: 0,
            endRadius: Self.toneGlowRadius
          )
          RadialGradient(
            colors: [colors.glow.opacity(Self.accentGlowOpacity(isDark: dark)), .clear],
            center: .topLeading,
            startRadius: 0,
            endRadius: Self.accentGlowRadius
          )
        }
      }
    }
  }

  /// The tone glow's opacity at the bottom-trailing corner, and how far it reaches.
  static func toneGlowOpacity(isDark: Bool) -> Double { isDark ? 0.40 : 0.18 }
  static let toneGlowRadius = 320.0
  /// The accent glow's opacity at the top-leading corner, and how far it reaches.
  static func accentGlowOpacity(isDark: Bool) -> Double { isDark ? 0.13 : 0.08 }
  static let accentGlowRadius = 240.0
}

/// Thin vertical accent hairline dividing the medium widget's two columns.
nonisolated struct SalahHairline: View {
  let accent: Color

  var body: some View {
    LinearGradient(
      colors: [.clear, accent.opacity(0.35), .clear],
      startPoint: .top,
      endPoint: .bottom
    )
    .frame(width: 1)
  }
}

// MARK: - Micro-components

/// Accent "eyebrow" label (e.g. NEXT PRAYER). Uppercased for editorial weight - a
/// no-op for Arabic, and never letter-spaced, so cursive joining stays intact.
nonisolated struct EyebrowLabel: View {
  let text: String
  let accent: Color
  var muted: Bool = false
  /// The widget's ink, in place of `accent`; the menu bar passes none.
  var ink: SalahWidgetInk? = nil

  var body: some View {
    let label = Text(verbatim: text)
      .font(.caption2.weight(.semibold))
      .textCase(.uppercase)
      .lineLimit(1)
    if let ink {
      label.salahInk(ink)
    } else {
      label.foregroundStyle(muted ? Color.secondary : accent)
    }
  }
}

/// Small uppercase capsule for the "Tomorrow" / "Now" markers - a tinted tag with
/// a hairline border. The tint is supplied by the caller (accent or a tone color).
nonisolated struct InlineBadge: View {
  let text: String
  let tint: Color
  /// The widget's ink for the text, in place of `tint`; the menu bar passes none.
  var ink: SalahWidgetInk? = nil

  var body: some View {
    inked(
      Text(verbatim: text)
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
    )
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .background(Capsule().fill(tint.opacity(SalahWidgetTint.badge)))
    .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 0.75))
    .lineLimit(1)
  }

  @ViewBuilder
  private func inked(_ label: some View) -> some View {
    if let ink {
      label.salahInk(ink)
    } else {
      label.foregroundStyle(tint)
    }
  }
}

nonisolated extension View {
  /// Hero surface: a tone-tinted gradient fill with a fine accent-into-tone
  /// hairline, lifting the focus block off the backdrop like an inlay.
  func salahHeroCard(toneColor: Color, accent: Color) -> some View {
    background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(
          LinearGradient(
            colors: [
              toneColor.opacity(SalahWidgetTint.card),
              toneColor.opacity(SalahWidgetTint.cardTrailing),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
              LinearGradient(
                colors: [accent.opacity(0.45), toneColor.opacity(0.30)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 1
            )
        )
    }
  }
}
