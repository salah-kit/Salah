import Foundation

/// An sRGB color stored as plain components so it round-trips through `Codable`
/// and renders the identical shade in the installed widget and the in-app live
/// preview. The SwiftUI `Color` accessor lives in the design-system file; this
/// type stays Foundation-only so `SalahWidgetSnapshot` can carry a theme
/// without importing SwiftUI.
nonisolated struct SalahColorSpec: Codable, Equatable, Sendable {
  var red: Double
  var green: Double
  var blue: Double
  var opacity: Double

  init(_ red: Double, _ green: Double, _ blue: Double, _ opacity: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
  }
}

// MARK: - Contrast / separation math (pure, for the custom-theme guardrails)

nonisolated extension SalahColorSpec {
  /// WCAG relative luminance.
  var relativeLuminance: Double {
    func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
  }

  /// WCAG contrast ratio between two colors (1…21).
  static func contrastRatio(_ a: SalahColorSpec, _ b: SalahColorSpec) -> Double {
    let la = a.relativeLuminance
    let lb = b.relativeLuminance
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  }

  /// Hue-preserving luminance nudge: lighten (on a dark surface) or darken (on a
  /// light one) until this color clears `ratio` against `surface`, or it bottoms
  /// out. Used by "Fix contrast".
  func adjustedForContrast(against surface: SalahColorSpec, ratio target: Double = 4.5)
    -> SalahColorSpec
  {
    if Self.contrastRatio(self, surface) >= target { return self }
    let towardLight = surface.relativeLuminance < 0.5
    var best = self
    for step in 1...20 {
      let t = Double(step) / 20.0
      let candidate = SalahColorSpec(
        red + (towardLight ? (1 - red) : -red) * t,
        green + (towardLight ? (1 - green) : -green) * t,
        blue + (towardLight ? (1 - blue) : -blue) * t,
        opacity)
      best = candidate
      if Self.contrastRatio(candidate, surface) >= target { break }
    }
    return best
  }

  /// Rough perceptual distance (0…~1.4) for the functional-hue separation check.
  func distance(to other: SalahColorSpec) -> Double {
    let dr = red - other.red
    let dg = green - other.green
    let db = blue - other.blue
    return (dr * dr + dg * dg + db * db).squareRoot()
  }
}

/// Whether the widget follows the system appearance or is pinned. Part of the
/// theme so the choice rides in the snapshot; in Phase 1 every theme is `.system`.
nonisolated enum SalahWidgetAppearance: String, Codable, Equatable, Sendable {
  case system
  case alwaysDark
  case alwaysLight
}

/// The **calm** palette for one appearance. Only these tokens are themeable; the
/// functional state colors (imminent red, count-up green, the audio tones, stop,
/// silent grey) are fixed constants in the design system and never live here.
nonisolated struct SalahWidgetPalette: Codable, Equatable, Sendable {
  /// The brand "guiding light" (brass in Nocturne): hairlines, date glyph, badges, glow.
  var accent: SalahColorSpec
  /// The next-prayer / resting color (blue in Nocturne): the countdown + active row.
  var primary: SalahColorSpec
  var backgroundTop: SalahColorSpec
  var backgroundBottom: SalahColorSpec
  var glow: SalahColorSpec
}

/// A complete widget theme: the calm tokens for both appearances plus the
/// appearance mode. Resolved app-side and embedded in `SalahWidgetSnapshot`;
/// the widget reads it verbatim. Functional colors are deliberately absent (see
/// `SalahWidgetTone` in the design system) so they can never drift per theme.
nonisolated struct SalahWidgetTheme: Codable, Equatable, Sendable {
  /// Preset identifier (e.g. "nocturne") or "custom".
  var id: String
  var appearance: SalahWidgetAppearance
  var dark: SalahWidgetPalette
  var light: SalahWidgetPalette

  /// The default look (today's "Nocturne": brass accent, blue primary, midnight
  /// base in dark / warm dawn base in light). Phase-1 snapshots resolve to this;
  /// Phase 2's Appearance tab swaps in the user's choice through the same field.
  static let nocturne = SalahWidgetTheme(
    id: "nocturne",
    appearance: .system,
    dark: SalahWidgetPalette(
      accent: SalahColorSpec(0.88, 0.69, 0.29),  // brass
      primary: SalahColorSpec(0.04, 0.52, 1.00),  // blue
      backgroundTop: SalahColorSpec(0.075, 0.094, 0.180),
      backgroundBottom: SalahColorSpec(0.027, 0.035, 0.078),
      glow: SalahColorSpec(0.88, 0.69, 0.29)  // brass glow
    ),
    light: SalahWidgetPalette(
      accent: SalahColorSpec(0.62, 0.45, 0.12),  // deeper brass for contrast
      primary: SalahColorSpec(0.00, 0.40, 0.85),  // deeper blue, readable on cream
      backgroundTop: SalahColorSpec(0.992, 0.976, 0.945),
      backgroundBottom: SalahColorSpec(0.953, 0.925, 0.875),
      glow: SalahColorSpec(0.88, 0.69, 0.29)
    )
  )

  /// Warm "Dawn": sand base, gold accent, soft-teal primary. A light-first mood.
  static let dawn = SalahWidgetTheme(
    id: "dawn",
    appearance: .system,
    dark: SalahWidgetPalette(
      accent: SalahColorSpec(0.85, 0.62, 0.30),
      primary: SalahColorSpec(0.32, 0.64, 0.68),
      backgroundTop: SalahColorSpec(0.16, 0.13, 0.11),
      backgroundBottom: SalahColorSpec(0.09, 0.07, 0.055),
      glow: SalahColorSpec(0.85, 0.62, 0.30)
    ),
    light: SalahWidgetPalette(
      accent: SalahColorSpec(0.66, 0.44, 0.12),
      primary: SalahColorSpec(0.00, 0.44, 0.50),
      backgroundTop: SalahColorSpec(0.992, 0.952, 0.890),
      backgroundBottom: SalahColorSpec(0.968, 0.910, 0.820),
      glow: SalahColorSpec(0.85, 0.62, 0.30)
    )
  )

  /// "Oasis": midnight base, emerald accent, teal-blue primary.
  static let oasis = SalahWidgetTheme(
    id: "oasis",
    appearance: .system,
    dark: SalahWidgetPalette(
      accent: SalahColorSpec(0.20, 0.74, 0.58),
      primary: SalahColorSpec(0.18, 0.62, 0.80),
      backgroundTop: SalahColorSpec(0.05, 0.11, 0.11),
      backgroundBottom: SalahColorSpec(0.02, 0.05, 0.05),
      glow: SalahColorSpec(0.20, 0.74, 0.58)
    ),
    light: SalahWidgetPalette(
      accent: SalahColorSpec(0.00, 0.50, 0.40),
      primary: SalahColorSpec(0.00, 0.42, 0.60),
      backgroundTop: SalahColorSpec(0.930, 0.972, 0.962),
      backgroundBottom: SalahColorSpec(0.860, 0.930, 0.912),
      glow: SalahColorSpec(0.20, 0.74, 0.58)
    )
  )

  /// "Ink": graphite base, near-monochrome - a cool slate primary + brass whisper.
  static let ink = SalahWidgetTheme(
    id: "ink",
    appearance: .system,
    dark: SalahWidgetPalette(
      accent: SalahColorSpec(0.72, 0.64, 0.48),
      primary: SalahColorSpec(0.62, 0.67, 0.76),
      backgroundTop: SalahColorSpec(0.13, 0.13, 0.15),
      backgroundBottom: SalahColorSpec(0.07, 0.07, 0.085),
      glow: SalahColorSpec(0.72, 0.64, 0.48)
    ),
    light: SalahWidgetPalette(
      accent: SalahColorSpec(0.42, 0.37, 0.28),
      primary: SalahColorSpec(0.30, 0.35, 0.44),
      backgroundTop: SalahColorSpec(0.962, 0.962, 0.972),
      backgroundBottom: SalahColorSpec(0.900, 0.900, 0.920),
      glow: SalahColorSpec(0.42, 0.37, 0.28)
    )
  )

  /// "High Contrast": near-black/white base with a color-blind-safe yellow accent
  /// + blue primary. A deliberate look that complements honoring the system
  /// Increase-Contrast setting (which boosts whatever theme is active).
  static let highContrast = SalahWidgetTheme(
    id: "highContrast",
    appearance: .system,
    dark: SalahWidgetPalette(
      accent: SalahColorSpec(1.00, 0.84, 0.00),
      primary: SalahColorSpec(0.35, 0.70, 1.00),
      backgroundTop: SalahColorSpec(0.04, 0.04, 0.05),
      backgroundBottom: SalahColorSpec(0.00, 0.00, 0.00),
      glow: SalahColorSpec(1.00, 0.84, 0.00)
    ),
    light: SalahWidgetPalette(
      accent: SalahColorSpec(0.50, 0.38, 0.00),
      primary: SalahColorSpec(0.00, 0.32, 0.80),
      backgroundTop: SalahColorSpec(1.00, 1.00, 1.00),
      backgroundBottom: SalahColorSpec(0.95, 0.95, 0.96),
      glow: SalahColorSpec(0.50, 0.38, 0.00)
    )
  )

  /// The starter set, in display order. Differ only in the calm palette.
  static let allPresets: [SalahWidgetTheme] = [.nocturne, .dawn, .oasis, .ink, .highContrast]

  static func preset(id: String) -> SalahWidgetTheme? {
    allPresets.first { $0.id == id }
  }

  /// Build a one-off custom theme: the user-picked accent + primary (applied to
  /// both appearances), a curated background base, and an appearance mode. The
  /// glow follows the accent (the brand "guiding light").
  static func custom(
    accent: SalahColorSpec,
    primary: SalahColorSpec,
    base: SalahWidgetBackgroundBase,
    appearance: SalahWidgetAppearance
  ) -> SalahWidgetTheme {
    SalahWidgetTheme(
      id: "custom",
      appearance: appearance,
      dark: SalahWidgetPalette(
        accent: accent, primary: primary,
        backgroundTop: base.darkTop, backgroundBottom: base.darkBottom, glow: accent),
      light: SalahWidgetPalette(
        accent: accent, primary: primary,
        backgroundTop: base.lightTop, backgroundBottom: base.lightBottom, glow: accent)
    )
  }
}

/// The curated background moods a custom theme can choose from (never a free
/// color). Each supplies a dark and a light gradient.
nonisolated enum SalahWidgetBackgroundBase: String, Codable, Equatable, Sendable, CaseIterable {
  case midnight
  case sand
  case graphite

  var darkTop: SalahColorSpec {
    switch self {
    case .midnight: SalahColorSpec(0.075, 0.094, 0.180)
    case .sand: SalahColorSpec(0.16, 0.13, 0.11)
    case .graphite: SalahColorSpec(0.13, 0.13, 0.15)
    }
  }
  var darkBottom: SalahColorSpec {
    switch self {
    case .midnight: SalahColorSpec(0.027, 0.035, 0.078)
    case .sand: SalahColorSpec(0.09, 0.07, 0.055)
    case .graphite: SalahColorSpec(0.07, 0.07, 0.085)
    }
  }
  var lightTop: SalahColorSpec {
    switch self {
    case .midnight: SalahColorSpec(0.992, 0.976, 0.945)
    case .sand: SalahColorSpec(0.992, 0.952, 0.890)
    case .graphite: SalahColorSpec(0.962, 0.962, 0.972)
    }
  }
  var lightBottom: SalahColorSpec {
    switch self {
    case .midnight: SalahColorSpec(0.953, 0.925, 0.875)
    case .sand: SalahColorSpec(0.968, 0.910, 0.820)
    case .graphite: SalahColorSpec(0.900, 0.900, 0.920)
    }
  }
}
