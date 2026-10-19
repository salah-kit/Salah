import Foundation
import SalahCore
import SalahUI
import SwiftUI
import Testing
import WidgetKit

/// Measures every inked element of the widget faces against the surface SwiftUI draws under
/// its glyphs.
///
/// What it draws, in `WidgetPreviewContainer` (the in-app preview and the snapshot renderer)
/// or, for the setup and stale faces, the extension shell's message branches:
/// - every state the baselines draw (`SpecState`: idle, imminent, the three count-ups, end of
///   day, the three playing states, silent, setup and stale), the times-unavailable face, the
///   focus when the next prayer is unknown, and a day with missing prayers;
/// - in English, every size, for the five presets in light and dark, custom themes whose
///   primary just passes the Appearance tab's 3:1 check on each background base, and custom
///   themes with a white or near-white primary in dark and a near-black one in light; each
///   with and without Increase Contrast;
/// - in Arabic, right to left, the medium and large sizes for the presets in light and dark,
///   in standard contrast.
///
/// Each face renders four ways through `SalahWidgetInkProbe`: with every ink hidden, twice
/// over different inherited foreground colors (so text that isn't inked, which would keep
/// that color, shows up as a difference); as drawn; and with each inked element painted as a
/// rectangle of its resolved ink, in place, under the same modifiers as its glyphs. The pixels
/// that change between hidden and drawn are glyphs; each belongs to the one element whose
/// frame holds it. The test measures the painted pixel against the hidden one: the ink as
/// drawn over the real gradient, glows and tints, without the antialiasing a one-pixel-per-point
/// render gives the glyphs. It also checks that each element's strongest glyph pixel reaches
/// 90% of its painted ink, so nothing between the ink and its glyphs dims them.
@Suite("Widget ink contrast")
struct WidgetInkContrastTests {
  init() { TestEnvironment.configure() }

  /// The lowest contrast of a passed row's dimmed ink in standard contrast. Passed rows keep
  /// the widget's dimming there, a documented exception (`Design/README.md`, Widgets).
  static let passedRowFloor = 1.9

  /// The widget faces measured.
  nonisolated enum Face: String, CaseIterable, Sendable {
    case idle, imminent, countUp, countUpSilent, countUpImminent, endOfDay
    case playingAdhan, playingPreReminder, playingPostReminder, silent, setupNeeded, stale
    /// The schedule has nothing to show.
    case timesUnavailable
    /// Every prayer of the day passed, and tomorrow's times aren't known.
    case nextUnknown
    /// Sunrise and Isha are missing from the day.
    case missingPrayers
  }

  /// One theme in one language, and the appearances, contrasts and sizes it's drawn in.
  nonisolated struct Run: Sendable, CustomTestStringConvertible {
    var name: String
    var theme: SalahWidgetTheme
    var language: Baseline.Language = .en
    var contrasts: [ColorSchemeContrast] = [.standard, .increased]
    var sizes: [SalahWidgetSize] = [.small, .medium, .large]
    var testDescription: String { "\(name) \(language.rawValue)" }

    /// The appearances the theme shows: both for `.system`, else the pinned one.
    var schemes: [ColorScheme] {
      switch theme.appearance {
      case .system: [.light, .dark]
      case .alwaysDark: [.dark]
      case .alwaysLight: [.light]
      }
    }
  }

  /// A teal accent, well clear of the reserved hues.
  nonisolated static let customAccent = ThemeColor(0.30, 0.55, 0.55)

  nonisolated static let runs: [Run] = {
    var runs = SalahWidgetTheme.allPresets.map { Run(name: $0.id, theme: $0) }
    for base in SalahWidgetBackgroundBase.allCases {
      // A primary that reaches the guardrail's 3:1 against the base, and no more.
      let dark = ThemeColor(0.10, 0.12, 0.45).adjustedForContrast(against: base.darkTop, ratio: 3)
      let light = ThemeColor(0.60, 0.70, 1.00).adjustedForContrast(
        against: base.lightTop, ratio: 3)
      runs.append(
        Run(
          name: "custom-\(base.rawValue)-dark",
          theme: .custom(
            accent: customAccent, primary: dark, base: base, appearance: .alwaysDark)))
      runs.append(
        Run(
          name: "custom-\(base.rawValue)-light",
          theme: .custom(
            accent: customAccent, primary: light, base: base, appearance: .alwaysLight)))
    }
    // Extremes: a white primary in dark, whose glow is white too, and a near-black one in light.
    runs.append(
      Run(
        name: "custom-white-sand-dark",
        theme: .custom(
          accent: customAccent, primary: ThemeColor(1, 1, 1), base: .sand,
          appearance: .alwaysDark)))
    runs.append(
      Run(
        name: "custom-near-white-graphite-system",
        theme: .custom(
          accent: customAccent, primary: ThemeColor(0.96, 0.96, 0.92), base: .graphite,
          appearance: .system)))
    runs.append(
      Run(
        name: "custom-near-black-graphite-light",
        theme: .custom(
          accent: customAccent, primary: ThemeColor(0.05, 0.05, 0.08), base: .graphite,
          appearance: .alwaysLight)))
    runs.append(
      Run(
        name: "custom-near-black-midnight-system",
        theme: .custom(
          accent: customAccent, primary: ThemeColor(0.04, 0.04, 0.06), base: .midnight,
          appearance: .system)))
    for preset in SalahWidgetTheme.allPresets {
      runs.append(
        Run(
          name: preset.id, theme: preset, language: .ar, contrasts: [.standard],
          sizes: [.medium, .large]))
    }
    return runs
  }()

  @Test func customPrimariesJustPassTheGuardrail() {
    for run in Self.runs where run.name.hasSuffix("-dark") || run.name.hasSuffix("-light") {
      guard
        let base = SalahWidgetBackgroundBase.allCases.first(where: {
          run.name == "custom-\($0.rawValue)-dark" || run.name == "custom-\($0.rawValue)-light"
        })
      else { continue }
      let dark = run.theme.appearance == .alwaysDark
      let palette = dark ? run.theme.dark : run.theme.light
      let ratio = ThemeColor.contrastRatio(palette.primary, dark ? base.darkTop : base.lightTop)
      #expect(ratio >= 3 && ratio < 3.6, "\(run.name): \(ratio)")
      #expect(
        ContrastCheck().problems(foreground: palette.primary, background: palette.backgroundTop)
          .isEmpty)
    }
  }

  @Test(arguments: runs)
  func everyInkReachesItsContrast(_ run: Run) throws {
    try AppLanguageScope.with(BaselinePipeline.appLanguage(run.language)) {
      for scheme in run.schemes {
        for contrast in run.contrasts {
          for face in Face.allCases {
            // The setup face has no settings, so no theme or language: it's always Nocturne.
            if face == .setupNeeded, run.theme.id != "nocturne" || run.language != .en {
              continue
            }
            for size in run.sizes {
              try measure(
                view(face, size: size, run: run),
                label: "\(run.name) \(run.language.rawValue) \(scheme) \(contrast) \(face) \(size)",
                scheme: scheme, contrast: contrast)
            }
          }
        }
      }
    }
  }

  /// The view a face draws, in the run's theme and language.
  private func view(_ face: Face, size: SalahWidgetSize, run: Run) throws -> AnyView {
    let now = BaselinePipeline.previewNow
    let lang = BaselinePipeline.previewLanguage(run.language)
    func previewed(_ display: SalahDisplay) -> AnyView {
      var display = display
      display.settings.theme = run.theme
      return AnyView(WidgetPreviewContainer(display: display, size: size))
    }
    switch face {
    case .setupNeeded:
      let message = try ExtensionCatalog.string("widget.openToSetUp", localeIdentifier: "en")
      return AnyView(
        WidgetShellMessage(
          theme: .nocturne, tone: .normal, size: size, systemImage: "moon.stars",
          message: message))
    case .stale:
      var settings = BaselinePipeline.settings(for: .stale, language: run.language)
      settings.theme = run.theme
      return AnyView(
        WidgetShellMessage(
          theme: settings.theme, tone: settings.silentMode ? .silent : .normal,
          locale: settings.locale, size: size, systemImage: "arrow.clockwise",
          message: settings.labels.openToUpdate))
    case .timesUnavailable:
      let display = WidgetPreviewData.make(prayers: [], lang: lang, now: now)
      #expect(display.widgetFace == .unavailable)
      return previewed(display)
    case .nextUnknown:
      let display = WidgetPreviewData.make(
        prayers: [
          .init(id: .fajr, offset: -16 * 60), .init(id: .sunrise, offset: -14 * 60, alert: false),
          .init(id: .dhuhr, offset: -9 * 60), .init(id: .asr, offset: -5 * 60),
          .init(id: .maghrib, offset: -2 * 60), .init(id: .isha, offset: -30),
        ], lang: lang, now: now)
      #expect(display.prayerState != nil && display.focus == nil)
      return previewed(display)
    case .missingPrayers:
      let display = WidgetPreviewData.make(
        prayers: [
          .init(id: .fajr, offset: -8 * 60), .init(id: .dhuhr, offset: -3 * 60),
          .init(id: .asr, offset: -60), .init(id: .maghrib, offset: 162, pre: 10, post: 5),
        ], lang: lang, now: now)
      #expect(display.slots.contains(.missing(.isha)))
      return previewed(display)
    default:
      let state = try #require(SpecState(rawValue: face.rawValue))
      return previewed(BaselinePipeline.display(for: state, language: run.language))
    }
  }

  typealias Pixels = (width: Int, height: Int, bytes: [UInt8])

  private func measure(
    _ face: AnyView, label: String, scheme: ColorScheme, contrast: ColorSchemeContrast
  ) throws {
    func render(_ probe: SalahWidgetInkProbe?, inherited: Color = .init(red: 1, green: 0, blue: 1))
      throws -> Pixels
    {
      try #require(
        PixelComparison.rgba(
          BaselineRenderer.stablePNG {
            face
              .foregroundStyle(inherited)
              .environment(\.salahWidgetInkProbe, probe)
              .environment(\.colorScheme, scheme)
              .environment(\._colorSchemeContrast, contrast)
          }))
    }
    // A face's first render in a process can differ slightly while its glyphs are first
    // rasterized.
    _ = try render(nil)
    let hidden = try render(SalahWidgetInkProbe(.hide))
    // The elements as the settled layout places them: the first render can lay out slightly
    // differently.
    let listing = SalahWidgetInkProbe(.hide)
    _ = try BaselineRenderer.png(
      face.environment(\.salahWidgetInkProbe, listing).environment(\.colorScheme, scheme)
        .environment(\._colorSchemeContrast, contrast))
    let elements = Self.merged(listing.elements)
    #expect(elements.count >= 2, "\(label): the probe must see the face's inks")

    // Text that isn't inked keeps the inherited color, so it shows in the hidden renders.
    let otherHidden = try render(
      SalahWidgetInkProbe(.hide), inherited: .init(red: 0, green: 1, blue: 1))
    let residue = stride(from: 0, to: hidden.bytes.count, by: 4).filter { offset in
      (0..<3).contains {
        abs(Int(hidden.bytes[offset + $0]) - Int(otherHidden.bytes[offset + $0])) > 2
      }
    }
    #expect(residue.isEmpty, "\(label): \(residue.count) pixels of text drawn without an ink")

    if contrast == .increased {
      #expect(
        elements.allSatisfy { $0.ink.opacity == 1 }, "\(label): nothing dims with Increase Contrast"
      )
    }
    let shown = try render(SalahWidgetInkProbe(.show))
    let painted = try render(SalahWidgetInkProbe(.paint))

    struct Tally {
      var pixels = 0
      var lowest = Double.infinity
      var coverage = 0.0
    }
    var tallies = [Tally](repeating: Tally(), count: elements.count)
    var unclaimed = 0
    let margin = SalahWidgetInkProbe.paintMargin
    let areas = elements.map { $0.frame.insetBy(dx: -margin, dy: -margin) }
    for offset in stride(from: 0, to: shown.bytes.count, by: 4) {
      let deltas = (0..<3).map { Int(shown.bytes[offset + $0]) - Int(hidden.bytes[offset + $0]) }
      guard deltas.contains(where: { abs($0) > 2 }) else { continue }
      let point = CGPoint(
        x: Double(offset / 4 % shown.width) + 0.5, y: Double(offset / 4 / shown.width) + 0.5)
      var owners = areas.indices.filter { areas[$0].contains(point) }
      if owners.isEmpty {
        // A swash or diacritic can reach a little further, as Arabic's do.
        owners = areas.indices.filter { areas[$0].insetBy(dx: -3, dy: -3).contains(point) }
      }
      guard owners.count == 1, let owner = owners.first else {
        if owners.isEmpty { unclaimed += 1 }
        continue
      }
      tallies[owner].pixels += 1
      tallies[owner].lowest = min(
        tallies[owner].lowest, Self.contrast(painted.bytes, over: hidden.bytes, at: offset))
      // How much of the painted ink this glyph pixel reaches, in its strongest channel.
      let inks = (0..<3).map { Int(painted.bytes[offset + $0]) - Int(hidden.bytes[offset + $0]) }
      if let channel = inks.indices.max(by: { abs(inks[$0]) < abs(inks[$1]) }),
        abs(inks[channel]) >= 24
      {
        tallies[owner].coverage = max(
          tallies[owner].coverage, Double(deltas[channel]) / Double(inks[channel]))
      }
    }
    #expect(unclaimed == 0, "\(label): \(unclaimed) glyph pixels outside every inked frame")

    for (element, tally) in zip(elements, tallies) {
      let name = "\(label) \(Self.describe(element))"
      let floor = element.ink.opacity < 1 ? Self.passedRowFloor : element.ink.minimumContrast
      #expect(tally.pixels > 4, "\(name): the element's glyphs must show")
      #expect(tally.lowest >= floor, "\(name): \(tally.lowest), needs \(floor)")
      // At one pixel per point a small glyph's strongest pixel reaches 67% of its ink or
      // more (a dash), a larger one's 90%; dimming between the ink and its glyphs stays below.
      let coverage = tally.pixels >= 100 ? 0.9 : 0.6
      #expect(
        tally.coverage >= coverage, "\(name): glyphs reach \(tally.coverage) of the ink")
      print(
        "widget-ink-contrast \(name): \(String(format: "%.2f", tally.lowest)) (\(tally.pixels) px, coverage \(String(format: "%.2f", tally.coverage)))"
      )
    }
  }

  /// The elements, with each one SwiftUI laid out more than once in a render, at slightly
  /// different frames, kept once: its last resolution, over the union of its frames.
  private static func merged(_ elements: [SalahWidgetInkProbe.Element])
    -> [SalahWidgetInkProbe.Element]
  {
    var merged: [SalahWidgetInkProbe.Element] = []
    for element in elements {
      if let index = merged.firstIndex(where: {
        $0.ink == element.ink && $0.frame.intersects(element.frame)
      }) {
        let frame = merged[index].frame.union(element.frame)
        merged[index] = element
        merged[index].frame = frame
      } else {
        merged.append(element)
      }
    }
    return merged
  }

  private static func describe(_ element: SalahWidgetInkProbe.Element) -> String {
    let ink = element.ink
    var words: [String]
    switch ink.source {
    case .primary: words = ["primary"]
    case .secondary: words = ["secondary"]
    case .tone(let tone): words = ["tone-\(tone.rawValue)"]
    case .accent: words = ["accent"]
    }
    if ink.isGlyph { words.append("glyph") }
    if let tint = ink.tint { words.append("on-\(tint.rawValue)-\(ink.tintOpacity)") }
    if ink.opacity < 1 { words.append("dimmed-\(ink.opacity)") }
    if let color = element.color {
      words.append(
        String(
          format: "#%02x%02x%02x@%.2f", Int((color.red * 255).rounded()),
          Int((color.green * 255).rounded()), Int((color.blue * 255).rounded()), color.opacity))
    }
    let frame = element.frame
    words.append(
      "at \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
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

/// Without a backdrop in the environment, an ink resolves against Nocturne in the current
/// appearance.
@Suite("Widget inks without a backdrop")
struct WidgetInkFallbackTests {
  @Test func secondaryFollowsTheAppearance() throws {
    for scheme in [ColorScheme.light, .dark] {
      let resolved = SalahWidgetInk.secondary.resolved(
        on: nil, in: nil, scheme: scheme, contrast: .standard, renderingMode: .fullColor)
      let color = try #require(resolved.color)
      let surface = SalahWidgetTheme.nocturne.colors(for: scheme).palette.backgroundTop
      #expect(ThemeColor.contrastRatio(color.over(surface), surface) >= 4.5, "\(scheme)")
    }
  }
}
