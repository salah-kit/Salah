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

  /// The system's primary label, which `label/primary` maps to, as components on macOS 27:
  /// black or white at 85%, and opaque with Increase Contrast. Only contrast math uses them.
  static func labelPrimaryComponents(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast)
    -> ThemeColor
  {
    let white: Double = scheme == .dark ? 1 : 0
    return ThemeColor(
      red: white, green: white, blue: white, opacity: contrast == .increased ? 1 : 0.85)
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

/// What a widget face is drawn over: its theme's palette in one appearance, the tone of the
/// glow, the face's size, and the direction the backdrop is drawn in. The view that draws `SalahWidgetBackground` puts it in the
/// environment (`salahWidgetBackdrop`) and names the face's coordinate space
/// (`SalahWidgetBackdrop.coordinateSpace`), so each ink can reach its contrast against the
/// backdrop where it's drawn.
nonisolated struct SalahWidgetBackdrop: Equatable, Sendable {
  var palette: SalahWidgetPalette
  var isDark: Bool
  var tone: SalahWidgetTone
  /// The face's size, which `SalahWidgetBackground` fills.
  var size: CGSize
  /// Whether `SalahWidgetBackground` is drawn right to left, which mirrors its glows.
  var isRightToLeft: Bool

  init(colors: SalahWidgetColors, tone: SalahWidgetTone, size: CGSize, isRightToLeft: Bool) {
    self.palette = colors.palette
    self.isDark = colors.isDark
    self.tone = tone
    self.size = size
    self.isRightToLeft = isRightToLeft
  }

  /// The coordinate space of the face that `SalahWidgetBackground` fills.
  static let coordinateSpace = "salahWidgetFace"

  /// How far past an element's frame its surface is sampled, in points, for glyphs whose
  /// antialiasing reaches past the frame.
  static let sampleMargin = 4.0

  /// The point of the backdrop under `frame` where an ink is hardest to read: the lightest
  /// in dark, the darkest in light.
  ///
  /// It composites `SalahWidgetBackground`'s gradient and glows as SwiftUI draws them, at a
  /// grid of points over `frame` and `sampleMargin` around it, both bare and under the tint
  /// the ink sits on at `tintOpacity`: a tint can be a gradient that fades, or lighten in
  /// light and darken in dark, so the bare backdrop can be the harder one. `contrast` is the Increase Contrast setting, which strengthens the
  /// silent tone's glow. Without a frame, it samples the content of every widget size, which
  /// holds anywhere.
  func limit(
    in frame: CGRect?, tint: SalahWidgetTone?, tintOpacity: Double,
    contrast: ColorSchemeContrast
  ) -> ThemeColor {
    let tintColor = tint?.components(palette: palette, isDark: isDark, contrast: contrast)
    var regions: [(face: CGSize, area: CGRect)] = []
    if let frame {
      let face = CGRect(origin: .zero, size: size)
      let area = frame.insetBy(dx: -Self.sampleMargin, dy: -Self.sampleMargin).intersection(face)
      regions = [(size, area.isNull ? face : area)]
    } else {
      let margin = SalahWidgetSize.contentMargin
      regions = [SalahWidgetSize.small, .medium, .large].map {
        let face = $0.desktopPointSize
        return (face: face, area: CGRect(origin: .zero, size: face).insetBy(dx: margin, dy: margin))
      }
    }
    var limit = palette.backgroundTop
    var limitLuminance: Double?
    let steps = 6
    for (face, area) in regions {
      for column in 0...steps {
        for row in 0...steps {
          let point = CGPoint(
            x: area.minX + area.width * Double(column) / Double(steps),
            y: area.minY + area.height * Double(row) / Double(steps))
          let bare = surface(at: point, face: face, contrast: contrast)
          for color in [bare, tintColor.map { $0.over(bare, opacity: tintOpacity) } ?? bare] {
            let luminance = color.relativeLuminance
            if let current = limitLuminance, isDark ? luminance <= current : luminance >= current {
              continue
            }
            limit = color
            limitLuminance = luminance
          }
        }
      }
    }
    return limit
  }

  /// The backdrop's color at `point` of a face of size `face`. Right to left, SwiftUI
  /// mirrors the glows: the tone's comes from the bottom-left corner.
  private func surface(at point: CGPoint, face: CGSize, contrast: ColorSchemeContrast)
    -> ThemeColor
  {
    let toneColor = tone.components(palette: palette, isDark: isDark, contrast: contrast)
    let toneCenter = CGPoint(x: isRightToLeft ? 0 : face.width, y: face.height)
    let accentCenter = CGPoint(x: isRightToLeft ? face.width : 0, y: 0)
    func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
    var color = palette.backgroundTop.mixed(
      with: palette.backgroundBottom, by: face.height > 0 ? point.y / face.height : 0)
    color = toneColor.over(
      color,
      opacity: SalahWidgetBackground.toneGlowOpacity(isDark: isDark)
        * max(0, 1 - distance(point, toneCenter) / SalahWidgetBackground.toneGlowRadius))
    color = palette.glow.over(
      color,
      opacity: SalahWidgetBackground.accentGlowOpacity(isDark: isDark)
        * max(0, 1 - distance(point, accentCenter) / SalahWidgetBackground.accentGlowRadius))
    return color
  }
}

private nonisolated struct SalahWidgetBackdropKey: EnvironmentKey {
  static let defaultValue: SalahWidgetBackdrop? = nil
}

nonisolated extension EnvironmentValues {
  /// The backdrop the widget face is drawn over. Set it where `SalahWidgetBackground` is
  /// drawn. Without one, inks resolve against Nocturne in the current appearance, anywhere
  /// on a face.
  var salahWidgetBackdrop: SalahWidgetBackdrop? {
    get { self[SalahWidgetBackdropKey.self] }
    set { self[SalahWidgetBackdropKey.self] = newValue }
  }
}

// MARK: - Inks

/// The ink of one piece of a widget face's text or glyphs.
///
/// In full-color rendering, which the in-app preview also gets:
/// - `primary` is the system's `.primary`;
/// - `secondary` is `SalahColor.labelSecondary`, made more opaque where the backdrop under it
///   would take it below its contrast;
/// - a tone or the accent keeps its hue, moved toward white in dark or black in light only
///   as far as the backdrop under it needs.
///
/// Each ink resolves against the hardest point of the backdrop under its own frame, with the
/// tint it sits on (`SalahWidgetBackdrop.limit`). Text aims at 4.6:1 and glyphs at 3.1:1, a
/// little above the 4.5:1 and 3:1 they must reach, so rounding can't take them below. In
/// accented and vibrant rendering the system recolors the content and removes the
/// backdrop: tone and accent text use `.primary`, their glyphs use `.secondary`, and
/// secondary text keeps the system's `.secondary` hierarchy.
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
  /// The opacity of that tint, with any tints stacked under it (`SalahWidgetTint`).
  var tintOpacity = 0.0
  var opacity = 1.0
  /// Text that can wrap onto more lines. It resolves against the whole face rather than its
  /// own frame, so it's drawn once, in place, and wraps exactly as styled text does: a copy
  /// laid out again at its own size could break its lines differently.
  var wraps = false

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

  /// The same ink, on a tint of `tone` at `opacity`; `nil` for the bare backdrop.
  func on(_ tone: SalahWidgetTone?, opacity: Double) -> SalahWidgetInk {
    var ink = self
    ink.tint = tone
    ink.tintOpacity = tone == nil ? 0 : opacity
    return ink
  }

  /// The same ink, for text that can wrap onto more lines.
  var wrapping: SalahWidgetInk {
    var ink = self
    ink.wraps = true
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

  /// The contrast the ink aims at, a little above `minimumContrast`: the model of the
  /// backdrop matches SwiftUI's rendering to about one level in 255.
  var targetContrast: Double { minimumContrast + 0.1 }

  /// The ink resolved for a face.
  struct Resolved {
    var style: AnyShapeStyle
    /// The color drawn, when it isn't one of the system's styles.
    var color: ThemeColor?
  }

  /// The ink resolved for `backdrop` under `frame`, a frame in the face's coordinate space.
  /// Without a backdrop, it resolves against Nocturne in `scheme`, anywhere on a face.
  func resolved(
    on backdrop: SalahWidgetBackdrop?, in frame: CGRect?, scheme: ColorScheme,
    contrast: ColorSchemeContrast, renderingMode: WidgetRenderingMode
  ) -> Resolved {
    let backdrop =
      backdrop
      ?? SalahWidgetBackdrop(
        colors: SalahWidgetTheme.nocturne.colors(for: scheme), tone: .normal, size: .zero,
        isRightToLeft: false)
    let frame = backdrop.size == .zero ? nil : frame
    let palette = backdrop.palette
    let isDark = backdrop.isDark
    func color(_ color: ThemeColor) -> Resolved {
      Resolved(style: AnyShapeStyle(color.inkColor(opacity)), color: color)
    }
    guard renderingMode == .fullColor else {
      switch source {
      case .primary: return Self.system(.primary, opacity: opacity)
      case .secondary: return Self.system(.secondary, opacity: opacity)
      case .tone, .accent:
        return Self.system(isGlyph ? .secondary : .primary, opacity: opacity)
      }
    }
    func limit() -> ThemeColor {
      backdrop.limit(
        in: frame, tint: tint, tintOpacity: tintOpacity, contrast: contrast)
    }
    switch source {
    case .primary:
      // The label color itself, rather than the hierarchical style, so it doesn't follow a
      // foreground style set around the face. Only a glow as light as the text, from a theme
      // primary near white in dark, say, needs more.
      let label = SalahColor.labelPrimaryComponents(isDark ? .dark : .light, contrast)
      let surface = limit()
      if ThemeColor.contrastRatio(label.over(surface), surface) >= targetContrast {
        return Resolved(
          style: AnyShapeStyle(opacity == 1 ? Color.primary : Color.primary.opacity(opacity)),
          color: nil)
      }
      return color(label.raisedForContrast(over: surface, ratio: targetContrast, lighter: isDark))
    case .secondary, .tone(.silent):
      let ink = SalahColor.labelSecondaryComponents(isDark ? .dark : .light, contrast)
      return color(ink.raisedForContrast(over: limit(), ratio: targetContrast, lighter: isDark))
    case .tone(let tone):
      return color(
        tone.components(palette: palette, isDark: isDark)
          .movedForContrast(over: limit(), ratio: targetContrast, lighter: isDark))
    case .accent:
      return color(
        palette.accent.movedForContrast(over: limit(), ratio: targetContrast, lighter: isDark))
    }
  }

  private static func system(_ style: HierarchicalShapeStyle, opacity: Double) -> Resolved {
    Resolved(
      style: opacity == 1 ? AnyShapeStyle(style) : AnyShapeStyle(style.opacity(opacity)),
      color: nil)
  }
}

// MARK: - Drawing an ink

nonisolated extension View {
  /// Draws the view's text and glyphs in `ink`, resolved for the backdrop under the view, the
  /// rendering mode and the Increase Contrast setting.
  ///
  /// The view lays out as usual but draws nothing itself: a copy of it in an overlay, which
  /// reads its frame in the face's coordinate space, draws it in the resolved ink. That works
  /// in WidgetKit's single render pass. Only the copy is visible to accessibility.
  func salahInk(_ ink: SalahWidgetInk) -> some View {
    modifier(SalahInkModifier(ink: ink))
  }
}

private nonisolated struct SalahInkModifier: ViewModifier {
  let ink: SalahWidgetInk
  @Environment(\.salahWidgetBackdrop) private var backdrop
  @Environment(\.colorScheme) private var scheme
  @Environment(\.colorSchemeContrast) private var contrast
  @Environment(\.widgetRenderingMode) private var renderingMode
  @Environment(\.salahWidgetInkProbe) private var probe

  func body(content: Content) -> some View {
    if ink.wraps {
      wrapped(content)
    } else {
      placed(content)
    }
  }

  /// Text that can wrap, drawn in place in an ink that holds anywhere on the face.
  @ViewBuilder
  private func wrapped(_ content: Content) -> some View {
    let resolved = ink.resolved(
      on: backdrop, in: nil, scheme: scheme, contrast: contrast, renderingMode: renderingMode)
    if let probe {
      content
        .foregroundStyle(resolved.style)
        .opacity(probe.mode == .show ? 1 : 0)
        .overlay {
          GeometryReader { proxy in
            let frame = proxy.frame(in: .named(SalahWidgetBackdrop.coordinateSpace))
            if probe.record(ink, in: frame, color: resolved.color) == .paint {
              Rectangle().fill(resolved.style).padding(-SalahWidgetInkProbe.paintMargin)
            }
          }
        }
    } else {
      content.foregroundStyle(resolved.style)
    }
  }

  /// The view laid out as usual, hidden, with a copy in an overlay that reads its frame and
  /// draws in the ink resolved there. The copy is proposed the view's own size, so a view
  /// whose layout depends on its proposal beyond that, such as wrapping text, should use
  /// `wrapping`.
  private func placed(_ content: Content) -> some View {
    content
      .hidden()
      .accessibilityHidden(true)
      .overlay {
        GeometryReader { proxy in
          let frame = proxy.frame(in: .named(SalahWidgetBackdrop.coordinateSpace))
          let resolved = ink.resolved(
            on: backdrop, in: frame, scheme: scheme, contrast: contrast,
            renderingMode: renderingMode)
          drawn(content, resolved, frame: frame)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
      }
  }

  @ViewBuilder
  private func drawn(_ content: Content, _ resolved: SalahWidgetInk.Resolved, frame: CGRect)
    -> some View
  {
    switch probe?.record(ink, in: frame, color: resolved.color) {
    case nil, .show?:
      content.foregroundStyle(resolved.style)
    case .hide?:
      content.foregroundStyle(resolved.style).opacity(0)
    case .paint?:
      Rectangle().fill(resolved.style).padding(-SalahWidgetInkProbe.paintMargin)
    }
  }
}

/// Measures a face's inks in SalahTests. It lists each inked element the face draws, with its
/// frame in the face's coordinate space, and draws every element one way: as usual, hidden
/// (the surface under the text), or as a rectangle of its resolved ink over its frame, so a
/// test can measure each ink against the pixels under its glyphs.
nonisolated final class SalahWidgetInkProbe: @unchecked Sendable {
  enum Mode: Sendable {
    case show
    case hide
    case paint
  }

  /// An inked element of a face.
  struct Element: Equatable, Sendable {
    var ink: SalahWidgetInk
    /// Its frame in the face's coordinate space.
    var frame: CGRect
    /// The color it draws in, when that isn't one of the system's styles.
    var color: ThemeColor?
  }

  /// How far past its frame `paint` draws an element, in points.
  static let paintMargin = SalahWidgetBackdrop.sampleMargin

  let mode: Mode
  private let lock = NSLock()
  private var recorded: [Element] = []

  init(_ mode: Mode) {
    self.mode = mode
  }

  /// The inked elements the face has drawn.
  var elements: [Element] {
    lock.withLock { recorded }
  }

  /// Notes an element the face draws, and says how to draw it.
  func record(_ ink: SalahWidgetInk, in frame: CGRect, color: ThemeColor?) -> Mode {
    let element = Element(ink: ink, frame: frame, color: color)
    lock.withLock {
      if !recorded.contains(element) { recorded.append(element) }
    }
    return mode
  }
}

private nonisolated struct SalahWidgetInkProbeKey: EnvironmentKey {
  static let defaultValue: SalahWidgetInkProbe? = nil
}

nonisolated extension EnvironmentValues {
  /// The probe that measures a face's inks in SalahTests; `nil` draws every ink as usual.
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
  /// `ratio` over `surface`; once opaque, moved toward white (`lighter`) or black if it still
  /// needs to. An ink that already reaches it comes back unchanged.
  func raisedForContrast(over surface: ThemeColor, ratio: Double, lighter: Bool) -> ThemeColor {
    var ink = self
    while ink.opacity < 1, Self.contrastRatio(ink.over(surface), surface) < ratio {
      ink.opacity = min(1, ink.opacity + 0.01)
    }
    if Self.contrastRatio(ink.over(surface), surface) >= ratio { return ink }
    return ink.movedForContrast(over: surface, ratio: ratio, lighter: lighter)
  }

  /// The color to draw, at `opacity` times its own.
  func inkColor(_ opacity: Double) -> Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: self.opacity * opacity)
  }
}
