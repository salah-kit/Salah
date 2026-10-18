import Foundation
import SalahUI
import SwiftUI
import WidgetKit

// MARK: - Design tokens

/// The primitives of `Design/tokens/primitives.json` that the widget draws with, named as
/// each token's `swift` entry.
nonisolated enum SalahPalette {
  /// `ink/light-78`: `#3c3c43` at 78%.
  static let inkLight78 = ThemeColor(red: 0.2353, green: 0.2353, blue: 0.2627, opacity: 0.78)
  /// `ink/light-92`: `#3c3c43` at 92%.
  static let inkLight92 = ThemeColor(red: 0.2353, green: 0.2353, blue: 0.2627, opacity: 0.92)
  /// `ink/dark-64`: `#ebebf5` at 64%.
  static let inkDark64 = ThemeColor(red: 0.9216, green: 0.9216, blue: 0.9608, opacity: 0.64)
  /// `ink/dark-84`: `#ebebf5` at 84%.
  static let inkDark84 = ThemeColor(red: 0.9216, green: 0.9216, blue: 0.9608, opacity: 0.84)
}

/// Salah's semantic colors, named as each token's `swift` entry in `Design/tokens`. Each
/// one picks its value from the four color files by the appearance and the Increase
/// Contrast setting, as `Design/README.md` (Increase Contrast) describes.
nonisolated enum SalahColor {
  /// `label/secondary`: secondary text. Stronger than the system's secondary label, so
  /// body text keeps its contrast on the widget's skies.
  static func labelSecondary(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
    labelSecondaryComponents(scheme, contrast).color
  }

  /// `label/secondary` as components, for contrast math.
  static func labelSecondaryComponents(
    _ scheme: ColorScheme, _ contrast: ColorSchemeContrast
  ) -> ThemeColor {
    switch (scheme == .dark, contrast == .increased) {
    case (false, false): SalahPalette.inkLight78
    case (false, true): SalahPalette.inkLight92
    case (true, false): SalahPalette.inkDark64
    case (true, true): SalahPalette.inkDark84
    }
  }
}

// MARK: - Backdrop

/// What a widget face is drawn over: its theme's palette in one appearance, and the tone of
/// the glow. The view that draws `SalahWidgetBackground` puts it in the environment
/// (`salahWidgetBackdrop`), so each ink in the face can reach its contrast against it.
nonisolated struct SalahWidgetBackdrop: Equatable, Sendable {
  var palette: SalahWidgetPalette
  var isDark: Bool
  var tone: SalahWidgetTone

  init(colors: SalahWidgetColors, tone: SalahWidgetTone) {
    self.palette = colors.palette
    self.isDark = colors.isDark
    self.tone = tone
  }

  /// The opacity of the tints text can sit on: a large row's state fill (at most 22%), the
  /// large focus card (24%), and the Now badge on its row (16% over 12%).
  static let tintOpacity = 0.28

  /// The point of the backdrop where an ink is hardest to read: the lightest in dark, the
  /// darkest in light, under a tint of `tint` when the ink sits on one. `contrast` is the
  /// Increase Contrast setting, which strengthens the silent tone's glow.
  ///
  /// It samples `SalahWidgetBackground`'s gradient and glows inside the content margin of
  /// every widget size, as SwiftUI composites them, so a face's ink holds wherever its
  /// text lands.
  func limit(tint: SalahWidgetTone?, contrast: ColorSchemeContrast) -> ThemeColor {
    let top = palette.backgroundTop
    let bottom = palette.backgroundBottom
    let toneColor = tone.components(palette: palette, isDark: isDark, contrast: contrast)
    let toneOpacity = SalahWidgetBackground.toneGlowOpacity(isDark: isDark)
    let accentOpacity = SalahWidgetBackground.accentGlowOpacity(isDark: isDark)
    let tintColor = tint?.components(palette: palette, isDark: isDark, contrast: contrast)
    let margin = SalahWidgetSize.contentMargin
    let steps = 8
    var limit: ThemeColor?
    var limitLuminance = 0.0
    for size in [SalahWidgetSize.small, .medium, .large] {
      let frame = size.desktopPointSize
      for column in 0...steps {
        for row in 0...steps {
          let x = margin + (frame.width - 2 * margin) * Double(column) / Double(steps)
          let y = margin + (frame.height - 2 * margin) * Double(row) / Double(steps)
          var point = top.mixed(with: bottom, by: y / frame.height)
          let toneDistance = hypot(frame.width - x, frame.height - y)
          point = toneColor.over(
            point,
            opacity: toneOpacity
              * max(0, 1 - toneDistance / SalahWidgetBackground.toneGlowRadius))
          point = palette.glow.over(
            point,
            opacity: accentOpacity
              * max(0, 1 - hypot(x, y) / SalahWidgetBackground.accentGlowRadius))
          if let tintColor {
            point = tintColor.over(point, opacity: Self.tintOpacity)
          }
          let luminance = point.relativeLuminance
          if limit == nil || (isDark ? luminance > limitLuminance : luminance < limitLuminance) {
            limit = point
            limitLuminance = luminance
          }
        }
      }
    }
    return limit ?? top
  }
}

private nonisolated struct SalahWidgetBackdropKey: EnvironmentKey {
  static let defaultValue = SalahWidgetBackdrop(
    colors: SalahWidgetTheme.nocturne.colors(for: .light), tone: .normal)
}

nonisolated extension EnvironmentValues {
  /// The backdrop the widget face is drawn over. Set it where `SalahWidgetBackground` is
  /// drawn.
  var salahWidgetBackdrop: SalahWidgetBackdrop {
    get { self[SalahWidgetBackdropKey.self] }
    set { self[SalahWidgetBackdropKey.self] = newValue }
  }
}

// MARK: - Inks

/// The ink of one piece of a widget face's text or glyphs.
///
/// In full-color rendering, which the in-app preview also gets:
/// - `primary` is the system's `.primary`;
/// - `secondary` is `SalahColor.labelSecondary`, made more opaque where a face's glow would
///   take it below its contrast;
/// - a tone or the accent keeps its hue, moved toward white in dark or black in light until
///   it reaches its contrast.
///
/// Text reaches 4.5:1 and glyphs 3:1 against the backdrop's `limit`, including the tint
/// under it. In accented and vibrant rendering the system recolors the content and
/// removes the backdrop, so the inks are the system's `.primary` and `.secondary`, and the
/// tones and the accent as the theme gives them.
///
/// `opacity` dims an ink, as passed rows are dimmed. A dimmed ink is a documented choice
/// that doesn't reach its contrast (`Design/README.md`, Widgets).
nonisolated struct SalahWidgetInk: Hashable, Sendable {
  enum Source: Hashable, Sendable {
    case primary
    case secondary
    case tone(SalahWidgetTone)
    case accent
  }

  var source: Source
  /// A glyph, which needs 3:1, rather than text, which needs 4.5:1.
  var isGlyph = false
  /// The tone of the tint the ink sits on, or `nil` on the bare backdrop.
  var tint: SalahWidgetTone?
  var opacity = 1.0

  static let primary = SalahWidgetInk(source: .primary)
  static let secondary = SalahWidgetInk(source: .secondary)
  static let accent = SalahWidgetInk(source: .accent)
  static func tone(_ tone: SalahWidgetTone) -> SalahWidgetInk {
    SalahWidgetInk(source: .tone(tone))
  }

  /// The same ink, for a glyph.
  var glyph: SalahWidgetInk {
    var ink = self
    ink.isGlyph = true
    return ink
  }

  /// The same ink, on a tint of `tone`.
  func on(_ tone: SalahWidgetTone?) -> SalahWidgetInk {
    var ink = self
    ink.tint = tone
    return ink
  }

  /// The same ink at `opacity`.
  func dimmed(_ opacity: Double) -> SalahWidgetInk {
    var ink = self
    ink.opacity = opacity
    return ink
  }

  /// The contrast the ink reaches against its surface, undimmed.
  var minimumContrast: Double { isGlyph ? 3 : 4.5 }

  /// The style to draw the ink with.
  func style(
    on backdrop: SalahWidgetBackdrop, contrast: ColorSchemeContrast,
    renderingMode: WidgetRenderingMode
  ) -> AnyShapeStyle {
    let palette = backdrop.palette
    let isDark = backdrop.isDark
    guard renderingMode == .fullColor else {
      switch source {
      case .primary: return Self.system(.primary, opacity: opacity)
      case .secondary, .tone(.silent): return Self.system(.secondary, opacity: opacity)
      case .tone(let tone):
        return AnyShapeStyle(tone.components(palette: palette, isDark: isDark).inkColor(opacity))
      case .accent: return AnyShapeStyle(palette.accent.inkColor(opacity))
      }
    }
    let limit = backdrop.limit(tint: tint, contrast: contrast)
    switch source {
    case .primary:
      return Self.system(.primary, opacity: opacity)
    case .secondary, .tone(.silent):
      let ink = SalahColor.labelSecondaryComponents(isDark ? .dark : .light, contrast)
      return AnyShapeStyle(
        ink.raisedForContrast(over: limit, ratio: minimumContrast).inkColor(opacity))
    case .tone(let tone):
      let base = tone.components(palette: palette, isDark: isDark)
      return AnyShapeStyle(
        base.movedForContrast(over: limit, ratio: minimumContrast, lighter: isDark).inkColor(
          opacity))
    case .accent:
      return AnyShapeStyle(
        palette.accent.movedForContrast(over: limit, ratio: minimumContrast, lighter: isDark)
          .inkColor(opacity))
    }
  }

  private static func system(_ style: HierarchicalShapeStyle, opacity: Double) -> AnyShapeStyle {
    opacity == 1 ? AnyShapeStyle(style) : AnyShapeStyle(style.opacity(opacity))
  }
}

// MARK: - Drawing an ink

nonisolated extension View {
  /// Draws the view's text and glyphs in `ink`, resolved for the face's backdrop, the
  /// rendering mode and the Increase Contrast setting.
  func salahInk(_ ink: SalahWidgetInk) -> some View {
    modifier(SalahInkModifier(ink: ink))
  }
}

private nonisolated struct SalahInkModifier: ViewModifier {
  let ink: SalahWidgetInk
  @Environment(\.salahWidgetBackdrop) private var backdrop
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.salahWidgetInkProbe) private var probe

  func body(content: Content) -> some View {
    let styled = content.foregroundStyle(
      ink.style(on: backdrop, contrast: contrast, renderingMode: renderingMode))
    if let probe {
      styled.opacity(probe.draws(ink, over: backdrop) ? 1 : 0)
    } else {
      styled
    }
  }
}

/// Draws only some of a face's inks, so a test can find each ink's glyphs and measure the
/// ink against the surface beneath them. SalahTests renders a face with every ink hidden,
/// then with one shown at a time; the probe lists the inks the face draws, and the backdrop
/// each resolves against.
nonisolated final class SalahWidgetInkProbe: @unchecked Sendable {
  /// An ink a face draws, and the backdrop it resolves against.
  struct Drawn: Sendable {
    var ink: SalahWidgetInk
    var backdrop: SalahWidgetBackdrop
  }

  /// The ink drawn, or `nil` to hide every ink.
  let shown: SalahWidgetInk?
  private let lock = NSLock()
  private var inks: [SalahWidgetInk: SalahWidgetBackdrop] = [:]

  init(showing shown: SalahWidgetInk? = nil) {
    self.shown = shown
  }

  /// The inks the face has asked to draw.
  var drawn: [Drawn] {
    lock.withLock { inks.map { Drawn(ink: $0.key, backdrop: $0.value) } }
  }

  /// Notes that the face draws `ink` over `backdrop`, and says whether to show it.
  func draws(_ ink: SalahWidgetInk, over backdrop: SalahWidgetBackdrop) -> Bool {
    lock.withLock { inks[ink] = backdrop }
    return ink == shown
  }
}

private nonisolated struct SalahWidgetInkProbeKey: EnvironmentKey {
  static let defaultValue: SalahWidgetInkProbe? = nil
}

nonisolated extension EnvironmentValues {
  /// The probe that measures a face's inks in SalahTests; `nil` draws every ink.
  var salahWidgetInkProbe: SalahWidgetInkProbe? {
    get { self[SalahWidgetInkProbeKey.self] }
    set { self[SalahWidgetInkProbeKey.self] = newValue }
  }
}

// MARK: - Color math

nonisolated extension ThemeColor {
  /// This color drawn at `opacity` (times its own) over an opaque `surface`, as SwiftUI
  /// composites in sRGB.
  func over(_ surface: ThemeColor, opacity: Double = 1) -> ThemeColor {
    let alpha = min(max(self.opacity * opacity, 0), 1)
    func blend(_ top: Double, _ bottom: Double) -> Double { top * alpha + bottom * (1 - alpha) }
    return ThemeColor(
      red: blend(red, surface.red), green: blend(green, surface.green),
      blue: blend(blue, surface.blue))
  }

  /// The opaque color a fraction `amount` of the way to `other`, as a linear gradient
  /// interpolates.
  func mixed(with other: ThemeColor, by amount: Double) -> ThemeColor {
    let t = min(max(amount, 0), 1)
    return ThemeColor(
      red: red + (other.red - red) * t, green: green + (other.green - green) * t,
      blue: blue + (other.blue - blue) * t)
  }

  /// This color moved toward white (`lighter`) or black until it reaches `ratio` against
  /// `surface`, keeping its hue, in forty equal steps. Unlike
  /// `adjustedForContrast(against:ratio:)`, the direction follows the appearance rather
  /// than the surface, since a tinted surface in light can be darker than mid-gray.
  func movedForContrast(over surface: ThemeColor, ratio: Double, lighter: Bool) -> ThemeColor {
    let start = ThemeColor(red: red, green: green, blue: blue)
    if Self.contrastRatio(start, surface) >= ratio { return start }
    let end = lighter ? 1.0 : 0.0
    var candidate = start
    for step in 1...40 {
      let fraction = Double(step) / 40
      candidate = ThemeColor(
        red: red + (end - red) * fraction, green: green + (end - green) * fraction,
        blue: blue + (end - blue) * fraction)
      if Self.contrastRatio(candidate, surface) >= ratio { break }
    }
    return candidate
  }

  /// This translucent ink with its opacity raised, a hundredth at a time, until it reaches
  /// `ratio` over `surface`. An ink that already reaches it comes back unchanged.
  func raisedForContrast(over surface: ThemeColor, ratio: Double) -> ThemeColor {
    var ink = self
    while ink.opacity < 1, Self.contrastRatio(ink.over(surface), surface) < ratio {
      ink.opacity = min(1, ink.opacity + 0.01)
    }
    return ink
  }

  /// The color to draw, at `opacity` times its own.
  func inkColor(_ opacity: Double) -> Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: self.opacity * opacity)
  }
}
