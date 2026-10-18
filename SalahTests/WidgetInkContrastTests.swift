import Foundation
import SalahCore
import SalahUI
import SwiftUI
import Testing
import WidgetKit

/// Measures every ink of every widget face against the surface SwiftUI draws under its
/// glyphs: each state the widget shows, in each size, for every preset and for custom
/// themes whose primary just passes the Appearance tab's guardrail, in light and dark, with
/// and without Increase Contrast.
///
/// For each face, `SalahWidgetInkProbe` renders it with every ink hidden (the surface), then
/// with one ink shown at a time. The pixels that change are that ink's glyphs. The test
/// paints the ink, as the face resolves it, over the hidden face, and measures the painted
/// pixel against the surface pixel: the nominal ink over the real gradient, glows and tints,
/// without the antialiasing a one-pixel-per-point render gives the glyphs themselves.
@Suite("Widget ink contrast")
struct WidgetInkContrastTests {
  init() { TestEnvironment.configure() }

  /// The lowest contrast of a passed row's dimmed ink in standard contrast. Passed rows keep
  /// the widget's dimming there, a documented exception (`Design/README.md`, Widgets).
  static let passedRowFloor = 1.9

  /// A theme the test draws, and the states it draws it in.
  nonisolated struct Theme: Sendable, CustomTestStringConvertible {
    var theme: SalahWidgetTheme
    var name: String
    var testDescription: String { name }
  }

  /// The presets, and for each background base a custom theme in each appearance whose
  /// primary reaches the guardrail's 3:1 against the base and no more.
  nonisolated static let themes: [Theme] = {
    var themes = SalahWidgetTheme.allPresets.map { Theme(theme: $0, name: $0.id) }
    // A teal accent, well clear of the reserved hues, and a blue primary.
    let accent = ThemeColor(0.30, 0.55, 0.55)
    for base in SalahWidgetBackgroundBase.allCases {
      let dark = ThemeColor(0.10, 0.12, 0.45).adjustedForContrast(against: base.darkTop, ratio: 3)
      let light = ThemeColor(0.60, 0.70, 1.00).adjustedForContrast(
        against: base.lightTop, ratio: 3)
      themes.append(
        Theme(
          theme: .custom(accent: accent, primary: dark, base: base, appearance: .alwaysDark),
          name: "custom-\(base.rawValue)-dark"))
      themes.append(
        Theme(
          theme: .custom(accent: accent, primary: light, base: base, appearance: .alwaysLight),
          name: "custom-\(base.rawValue)-light"))
    }
    return themes
  }()

  @Test func customPrimariesJustPassTheGuardrail() {
    for base in SalahWidgetBackgroundBase.allCases {
      for theme in Self.themes where theme.name.hasPrefix("custom-\(base.rawValue)-") {
        let dark = theme.theme.appearance == .alwaysDark
        let palette = dark ? theme.theme.dark : theme.theme.light
        let ratio = ThemeColor.contrastRatio(
          palette.primary, dark ? base.darkTop : base.lightTop)
        #expect(ratio >= 3 && ratio < 3.6, "\(theme.name): \(ratio)")
        #expect(
          ContrastCheck().problems(foreground: palette.primary, background: palette.backgroundTop)
            .isEmpty)
      }
    }
  }

  @Test(arguments: themes)
  func everyInkReachesItsContrast(_ theme: Theme) throws {
    var faces = 0
    for scheme in schemes(for: theme.theme) {
      for contrast in [ColorSchemeContrast.standard, .increased] {
        for state in SpecState.allCases {
          // The setup face has no settings, so no theme: it's always Nocturne.
          if state == .setupNeeded, theme.theme.id != "nocturne" { continue }
          for size in [SalahWidgetSize.small, .medium, .large] {
            try measure(
              face(state, size: size, theme: theme.theme),
              label: "\(theme.name) \(scheme) \(contrast) \(state.rawValue) \(size)",
              scheme: scheme, contrast: contrast)
            faces += 1
          }
        }
      }
    }
    #expect(faces > 0)
  }

  /// The appearances a theme shows: both for a preset, the pinned one for a custom theme.
  private func schemes(for theme: SalahWidgetTheme) -> [ColorScheme] {
    switch theme.appearance {
    case .system: [.light, .dark]
    case .alwaysDark: [.dark]
    case .alwaysLight: [.light]
    }
  }

  /// The face a state shows, as the baselines draw it, in `theme`.
  private func face(_ state: SpecState, size: SalahWidgetSize, theme: SalahWidgetTheme) throws
    -> AnyView
  {
    switch state {
    case .setupNeeded:
      let message = try ExtensionCatalog.string("widget.openToSetUp", localeIdentifier: "en")
      return AnyView(
        WidgetShellMessage(
          theme: .nocturne, tone: .normal, size: size, systemImage: "moon.stars",
          message: message))
    case .stale:
      var settings = BaselinePipeline.settings(for: state, language: .en)
      settings.theme = theme
      return AnyView(
        WidgetShellMessage(
          theme: settings.theme, tone: settings.silentMode ? .silent : .normal,
          locale: settings.locale, size: size, systemImage: "arrow.clockwise",
          message: settings.labels.openToUpdate))
    default:
      var display = BaselinePipeline.display(for: state, language: .en)
      display.settings.theme = theme
      return AnyView(WidgetPreviewContainer(display: display, size: size))
    }
  }

  private func measure(
    _ face: AnyView, label: String, scheme: ColorScheme, contrast: ColorSchemeContrast
  ) throws {
    func render(_ probe: SalahWidgetInkProbe?, paint: SalahWidgetInkProbe.Drawn? = nil) throws
      -> (width: Int, height: Int, bytes: [UInt8])
    {
      try #require(
        PixelComparison.rgba(
          BaselineRenderer.stablePNG {
            face
              .overlay {
                if let paint {
                  Rectangle().fill(
                    paint.ink.style(
                      on: paint.backdrop, contrast: contrast, renderingMode: .fullColor))
                }
              }
              .environment(\.salahWidgetInkProbe, probe)
              .environment(\.colorScheme, scheme)
              .environment(\._colorSchemeContrast, contrast)
          }))
    }
    // Draw the face once first: a face's first render in a process can differ slightly
    // while its glyphs are first rasterized.
    _ = try render(nil)
    let hiding = SalahWidgetInkProbe()
    let hidden = try render(hiding)
    let drawn = hiding.drawn
    #expect(drawn.count >= 2, "\(label): the probe must see the face's inks")
    if contrast == .increased {
      #expect(
        drawn.allSatisfy { $0.ink.opacity == 1 }, "\(label): nothing dims with Increase Contrast")
    }
    for entry in drawn.sorted(by: { "\($0.ink)" < "\($1.ink)" }) {
      let ink = entry.ink
      let shown = try render(SalahWidgetInkProbe(showing: ink))
      let painted = try render(SalahWidgetInkProbe(), paint: entry)
      var lowest = Double.infinity
      var pixels = 0
      for offset in stride(from: 0, to: shown.bytes.count, by: 4)
      where (0..<3).contains(where: {
        abs(Int(shown.bytes[offset + $0]) - Int(hidden.bytes[offset + $0])) > 2
      }) {
        pixels += 1
        lowest = min(lowest, Self.contrast(painted.bytes, over: hidden.bytes, at: offset))
      }
      let floor = ink.opacity < 1 ? Self.passedRowFloor : ink.minimumContrast
      #expect(pixels > 4, "\(label) \(ink): the ink's glyphs must show")
      #expect(lowest >= floor, "\(label) \(ink): \(lowest), needs \(floor)")
      print(
        "widget-ink-contrast \(label) \(Self.describe(ink)): \(String(format: "%.2f", lowest)) (\(pixels) px)"
      )
    }
  }

  private static func describe(_ ink: SalahWidgetInk) -> String {
    var words: [String]
    switch ink.source {
    case .primary: words = ["primary"]
    case .secondary: words = ["secondary"]
    case .tone(let tone): words = ["tone-\(tone.rawValue)"]
    case .accent: words = ["accent"]
    }
    if ink.isGlyph { words.append("glyph") }
    if let tint = ink.tint { words.append("on-\(tint.rawValue)") }
    if ink.opacity < 1 { words.append("dimmed-\(ink.opacity)") }
    return words.joined(separator: " ")
  }

  private static func contrast(_ painted: [UInt8], over surface: [UInt8], at offset: Int) -> Double
  {
    // Both layers are opaque inside the face: SwiftUI has composited the ink, including its
    // opacity, on this exact surface.
    #expect(painted[offset + 3] == 255 && surface[offset + 3] == 255)
    func color(_ bytes: [UInt8]) -> ThemeColor {
      ThemeColor(
        red: Double(bytes[offset]) / 255, green: Double(bytes[offset + 1]) / 255,
        blue: Double(bytes[offset + 2]) / 255)
    }
    return ThemeColor.contrastRatio(color(painted), color(surface))
  }
}

/// `SalahPalette` and `SalahColor.labelSecondary` hold the design tokens' values.
@Suite("Widget inks follow the design tokens")
struct WidgetInkTokenTests {
  private func tokens(_ file: String) throws -> [String: Any] {
    let url = BaselineStore.repositoryRoot.appending(path: "Design/tokens/\(file)")
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  }

  private func value(_ root: [String: Any], _ path: [String]) -> Any? {
    var node: Any? = root
    for key in path { node = (node as? [String: Any])?[key] }
    return node
  }

  @Test func labelSecondaryMatchesTheColorFiles() throws {
    let primitives = try tokens("primitives.json")
    let modes: [(String, ColorScheme, ColorSchemeContrast)] = [
      ("color.light.json", .light, .standard),
      ("color.light-increased-contrast.json", .light, .increased),
      ("color.dark.json", .dark, .standard),
      ("color.dark-increased-contrast.json", .dark, .increased),
    ]
    for (file, scheme, contrast) in modes {
      let reference = try #require(
        value(try tokens(file), ["color", "label", "secondary", "$value"]) as? String)
      let path = reference.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        .split(separator: ".").map(String.init)
      let token = try #require(value(primitives, path + ["$value"]) as? [String: Any])
      let components = try #require(token["components"] as? [Double])
      let alpha = try #require(token["alpha"] as? Double)
      let swift = SalahColor.labelSecondaryComponents(scheme, contrast)
      #expect([swift.red, swift.green, swift.blue] == components, "\(file)")
      #expect(swift.opacity == alpha, "\(file)")
    }
  }
}
