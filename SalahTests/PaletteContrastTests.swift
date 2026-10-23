import SalahUI
import SwiftUI
import Testing

/// Salah's color tokens keep the contrast the design promises on the surfaces the widgets,
/// the dropdown and Today draw them on, in light and dark, with and without Increase
/// Contrast: text tokens 4.5:1; marks, glyphs and passed rows (`labelTertiary`) 3:1. The
/// faces draw text only in text tokens, or in one composited over the sky they sit on; the time of day's mark (`tint`) only in glyphs
/// and bars, and its text in `Phase/text`. The baselines show which token each element
/// draws in.
@Suite("Palette contrast")
struct PaletteContrastTests {
  /// Every appearance: light and dark, standard and increased contrast.
  static let appearances: [(isDark: Bool, increased: Bool)] = [
    (false, false), (true, false), (false, true), (true, true),
  ]

  /// `color` composited over the opaque `surface`.
  private static func over(_ color: ThemeColor, _ surface: ThemeColor) -> ThemeColor {
    color.composited(over: surface)
  }

  private static func ratio(_ ink: ThemeColor, on surface: ThemeColor) -> Double {
    ThemeColor.contrastRatio(over(ink, surface), surface)
  }

  /// Text and marks on each time of day's sky, as the widgets and the next-prayer card draw
  /// them.
  @Test(arguments: SalahPhase.allCases)
  func inksHoldOnTheSky(_ phase: SalahPhase) {
    for (isDark, increased) in Self.appearances {
      let palette = SalahPalette(isDark: isDark, increasedContrast: increased)
      let colors = phase.colors(isDark: isDark, increasedContrast: increased)
      let label = "\(phase) dark=\(isDark) increased=\(increased)"
      for sky in [colors.skyTop, colors.skyBottom] {
        #expect(Self.ratio(palette.labelPrimary, on: sky) >= 4.5, "\(label) primary")
        #expect(Self.ratio(palette.labelSecondary, on: sky) >= 4.5, "\(label) secondary")
        #expect(Self.ratio(palette.labelTertiary, on: sky) >= 3, "\(label) tertiary")
        #expect(Self.ratio(palette.accentText, on: sky) >= 4.5, "\(label) accent text")
        #expect(Self.ratio(colors.text, on: sky) >= 4.5, "\(label) phase text")
        #expect(Self.ratio(colors.tint, on: sky) >= 3, "\(label) phase tint")
        // The widget's next row: the accent on the track's wash over the sky.
        let nextRow = Self.over(palette.fillSecondary, sky)
        #expect(Self.ratio(palette.accentText, on: nextRow) >= 4.5, "\(label) next row")
      }
      // The current prayer's row: its wash, with its detail in the phase's text.
      let window = palette.elevated
      let wash = Self.over(colors.tintSubtle, window)
      #expect(Self.ratio(colors.text, on: wash) >= 4.5, "\(label) phase text on its wash")
      #expect(Self.ratio(palette.labelPrimary, on: wash) >= 4.5, "\(label) primary on its wash")
      #expect(Self.ratio(colors.tint, on: wash) >= 3, "\(label) glyph on its wash")
    }
  }

  /// Text and marks on the dropdown's and the window's surfaces, and on the accent fills.
  @Test func inksHoldOnTheSurfaces() {
    for (isDark, increased) in Self.appearances {
      let palette = SalahPalette(isDark: isDark, increasedContrast: increased)
      let label = "dark=\(isDark) increased=\(increased)"
      let surfaces = [
        ("elevated", palette.elevated),
        ("grouped", palette.groupedSecondary),
        ("form group", Self.over(palette.formGroup, palette.groupedSecondary)),
      ]
      for (name, surface) in surfaces {
        #expect(Self.ratio(palette.labelPrimary, on: surface) >= 4.5, "\(label) primary on \(name)")
        #expect(
          Self.ratio(palette.labelSecondary, on: surface) >= 4.5, "\(label) secondary on \(name)")
        #expect(
          Self.ratio(palette.labelTertiary, on: surface) >= 3, "\(label) tertiary on \(name)")
        #expect(Self.ratio(palette.accentText, on: surface) >= 4.5, "\(label) accent on \(name)")
        #expect(Self.ratio(palette.accent, on: surface) >= 3, "\(label) accent mark on \(name)")
      }
      // The next prayer's row and Silent when it's on: the accent's text on its wash.
      let wash = Self.over(palette.accentSubtle, palette.elevated)
      #expect(Self.ratio(palette.accentText, on: wash) >= 4.5, "\(label) accent text on the wash")
      #expect(Self.ratio(palette.labelPrimary, on: wash) >= 4.5, "\(label) primary on the wash")
      #expect(Self.ratio(palette.accent, on: wash) >= 3, "\(label) accent glyph on the wash")
      // Open Salah, Stop, Got It and the Now badge: dark ink on the gold fill.
      #expect(
        Self.ratio(palette.labelOnAccent, on: palette.accentFill) >= 4.5,
        "\(label) on-accent on the gold fill")
    }
  }

  /// Light and dark are distinct palettes, and each time of day has its own sky.
  @Test func eachAppearanceHasItsOwnColors() {
    let light = SalahPalette(isDark: false)
    let dark = SalahPalette(isDark: true)
    #expect(light.labelPrimary != dark.labelPrimary)
    #expect(
      SalahPhase.dhuhr.colors(isDark: false).skyTop != SalahPhase.asr.colors(isDark: false).skyTop)
  }

  /// The next-prayer card's secondary text is one opaque color: `labelSecondary` over the
  /// sky's nearer end, the top for the eyebrow and time, the bottom for the footer, holding
  /// 4.5:1 there. Dhuhr's dark sky pins the values themselves.
  @Test(arguments: SalahPhase.allCases)
  func theCardsSecondaryTextIsOpaqueAndHoldsItsContrast(_ phase: SalahPhase) {
    for (isDark, increased) in Self.appearances {
      let colors = SalahColors(
        phase: phase, scheme: isDark ? .dark : .light,
        contrast: increased ? .increased : .standard)
      for atTop in [true, false] {
        let label = "\(phase) dark=\(isDark) increased=\(increased) top=\(atTop)"
        let sky = atTop ? colors.phase.skyTop : colors.phase.skyBottom
        let ink = colors.secondaryOnSky(atTop: atTop)
        #expect(ink.opacity == 1, "\(label)")
        #expect(ThemeColor.contrastRatio(ink, sky) >= 4.5, "\(label)")
      }
    }
    let dhuhrDark = SalahColors(phase: .dhuhr, scheme: .dark, contrast: .standard)
    let top = dhuhrDark.secondaryOnSky(atTop: true)
    // #EBEBF5 at 0xA3/255 over #011F2E.
    #expect(abs(top.red - 0.5905) < 0.001 && abs(top.green - 0.6329) < 0.001)
    #expect(abs(top.blue - 0.6792) < 0.001)
  }
}
