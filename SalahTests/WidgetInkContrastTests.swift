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
/// that color, shows up as a difference and fails); as drawn; and with each inked element
/// painted as a rectangle of its resolved ink, in place, under the same modifiers as its
/// glyphs, over its frame and `SalahWidgetInkProbe.paintMargin` around it. The pixels that
/// change between hidden and drawn are glyphs; each belongs to the one element whose painted
/// area holds it, and a glyph pixel outside every painted area fails. The test measures the
/// painted pixel against the hidden one: the ink as drawn over the real gradient, glows and
/// tints, without the antialiasing a one-pixel-per-point render gives the glyphs.
///
/// Because the paint sits under the same modifiers as the glyphs, a layer above `salahInk`
/// that dims or blends both shows in the measurement. `glyphsReachTheirInk` catches the rest,
/// a layer inside the inked view that dims or recolors only its glyphs: at three pixels per
/// point, each element's fullest glyph pixel must reach 90% of its painted ink in every
/// channel the ink moves. It draws Nocturne in light and dark, every face and size in English
/// and the medium and large sizes in Arabic, which reaches every inked element.
///
/// `stateColorsKeepTheirHue` checks that each ink moves only as far as its own surface needs,
/// and `facesHoldOverABackdropInTheOtherDirection` draws faces over a backdrop in the other
/// direction, as the widget extension can.
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

  /// How far a glyph's fullest pixel must reach its painted ink at three pixels per point,
  /// in every channel the ink moves, where strokes cover whole pixels.
  static let glyphCoverage = 0.9

  /// Renders `face`, holds each inked element to its floor, and with `checksCoverage`, to
  /// `glyphCoverage` too.
  private func measure(
    _ face: AnyView, label: String, scheme: ColorScheme, contrast: ColorSchemeContrast,
    scale: Int = 1, checksCoverage: Bool = false
  ) throws {
    func view(_ probe: SalahWidgetInkProbe?, inherited: Color) -> some View {
      face
        .foregroundStyle(inherited)
        .environment(\.salahWidgetInkProbe, probe)
        .environment(\.colorScheme, scheme)
        .environment(\._colorSchemeContrast, contrast)
    }
    func render(_ probe: SalahWidgetInkProbe?, inherited: Color = .init(red: 1, green: 0, blue: 1))
      throws -> Pixels
    {
      try #require(
        PixelComparison.rgba(
          BaselineRenderer.stablePNG(scale: scale) { view(probe, inherited: inherited) }))
    }
    // A face's first render in a process can differ slightly while its glyphs are first
    // rasterized.
    _ = try render(nil)
    let hidden = try render(SalahWidgetInkProbe(.hide))
    // The elements as the settled layout places them: the first render can lay out slightly
    // differently.
    let listing = SalahWidgetInkProbe(.hide)
    _ = try BaselineRenderer.png(
      view(listing, inherited: .init(red: 1, green: 0, blue: 1)), scale: scale)
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
    // The paint covers each frame and this margin around it, so a glyph pixel in it has the
    // element's paint over it.
    let margin = SalahWidgetInkProbe.paintMargin
    let areas = elements.map { $0.frame.insetBy(dx: -margin, dy: -margin) }
    for offset in stride(from: 0, to: shown.bytes.count, by: 4) {
      let deltas = (0..<3).map { Int(shown.bytes[offset + $0]) - Int(hidden.bytes[offset + $0]) }
      guard deltas.contains(where: { abs($0) > 2 }) else { continue }
      let point = CGPoint(
        x: (Double(offset / 4 % shown.width) + 0.5) / Double(scale),
        y: (Double(offset / 4 / shown.width) + 0.5) / Double(scale))
      let owners = areas.indices.filter { areas[$0].contains(point) }
      guard owners.count == 1, let owner = owners.first else {
        if owners.isEmpty { unclaimed += 1 }
        continue
      }
      tallies[owner].pixels += 1
      tallies[owner].lowest = min(
        tallies[owner].lowest, Self.contrast(painted.bytes, over: hidden.bytes, at: offset))
      // How much of the painted ink this glyph pixel reaches: its lowest share over the
      // channels the ink moves, so an ink of another color can't pass on one channel.
      let inks = (0..<3).map { Int(painted.bytes[offset + $0]) - Int(hidden.bytes[offset + $0]) }
      let shares = (0..<3).filter { abs(inks[$0]) >= 24 }.map {
        Double(deltas[$0]) / Double(inks[$0])
      }
      if let share = shares.min() {
        tallies[owner].coverage = max(tallies[owner].coverage, share)
      }
    }
    #expect(unclaimed == 0, "\(label): \(unclaimed) glyph pixels outside every inked frame")

    for (element, tally) in zip(elements, tallies) {
      let name = "\(label) \(Self.describe(element))"
      let floor = element.ink.opacity < 1 ? Self.passedRowFloor : element.ink.minimumContrast
      #expect(tally.pixels > 4, "\(name): the element's glyphs must show")
      #expect(tally.lowest >= floor, "\(name): \(tally.lowest), needs \(floor)")
      if checksCoverage {
        #expect(
          tally.coverage >= Self.glyphCoverage,
          "\(name): glyphs reach \(tally.coverage) of the ink")
      }
      print(
        "widget-ink-contrast \(name): \(String(format: "%.2f", tally.lowest)) (\(tally.pixels) px, coverage \(String(format: "%.2f", tally.coverage)))"
      )
    }
  }

  /// Nothing between an ink and its glyphs dims or recolors them. At three pixels per point
  /// every glyph's strokes cover whole pixels, so its fullest pixel reaches the ink it
  /// resolves to in every channel the ink moves. Layout doesn't depend on the theme, so
  /// Nocturne in light and dark covers every element: each face and size in English, and
  /// the medium and large sizes in Arabic.
  @Test func glyphsReachTheirInk() throws {
    for language in [Baseline.Language.en, .ar] {
      let run = Run(
        name: "nocturne", theme: .nocturne, language: language,
        sizes: language == .en ? [.small, .medium, .large] : [.medium, .large])
      try AppLanguageScope.with(BaselinePipeline.appLanguage(language)) {
        for scheme in run.schemes {
          for face in Face.allCases where face != .setupNeeded || language == .en {
            for size in run.sizes {
              try measure(
                view(face, size: size, run: run),
                label: "coverage \(language.rawValue) \(scheme) \(face) \(size)",
                scheme: scheme, contrast: .standard, scale: 3, checksCoverage: true)
            }
          }
        }
      }
    }
  }

  /// The inked elements of a face, as it draws them.
  private func elements(_ face: AnyView, scheme: ColorScheme) throws
    -> [SalahWidgetInkProbe.Element]
  {
    let probe = SalahWidgetInkProbe(.show)
    _ = try BaselineRenderer.stablePNG {
      face.environment(\.salahWidgetInkProbe, probe).environment(\.colorScheme, scheme)
    }
    return Self.merged(probe.elements)
  }

  /// A state's color stays itself where the surface under it allows: each ink moves only as
  /// far as its own surface needs. Solving every ink against the hardest point of the whole
  /// face would bleach these, on the dark large count-up faces in Nocturne.
  @Test func stateColorsKeepTheirHue() throws {
    let run = Run(name: "nocturne", theme: .nocturne)
    let countUp = try elements(view(.countUp, size: .large, run: run), scheme: .dark)
    let green = SalahWidgetTone.prayerDark
    // The count-up on the large card keeps the green exactly.
    let timer = try #require(
      countUp.first {
        $0.ink.source == .tone(.playingPrayerAudio) && $0.ink.tintOpacity == SalahWidgetTint.card
      })
    #expect(timer.color == green, "\(Self.describe(timer))")
    // The Now badge on the card stays green.
    let badge = try #require(
      countUp.first {
        $0.ink.source == .tone(.playingPrayerAudio) && $0.ink.tintOpacity > SalahWidgetTint.card
      })
    try Self.expectHue(of: badge, like: green, saturation: 0.45)
    // The next prayer's name stays blue.
    let next = try #require(
      countUp.first { $0.ink.source == .tone(.normal) && !$0.ink.isGlyph && $0.frame.minX < 100 })
    try Self.expectHue(of: next, like: SalahWidgetTheme.nocturne.dark.primary, saturation: 0.7)
    // On the count-up face with an imminent next prayer, that prayer's name stays red.
    let imminent = try elements(view(.countUpImminent, size: .large, run: run), scheme: .dark)
    let isha = try #require(
      imminent.first {
        $0.ink.source == .tone(.imminent) && !$0.ink.isGlyph && $0.frame.minX < 100
      })
    try Self.expectHue(of: isha, like: SalahWidgetTone.imminentDark, saturation: 0.6)
  }

  private static func expectHue(
    of element: SalahWidgetInkProbe.Element, like expected: ThemeColor, saturation: Double
  ) throws {
    let color = try #require(element.color, "\(describe(element))")
    let (hue, chroma) = hueAndSaturation(color)
    let (expectedHue, _) = hueAndSaturation(expected)
    let apart = min(abs(hue - expectedHue), 360 - abs(hue - expectedHue))
    #expect(apart <= 10, "\(describe(element)): hue \(hue), expected \(expectedHue)")
    #expect(chroma >= saturation, "\(describe(element)): saturation \(chroma)")
  }

  /// HSV hue in degrees and saturation.
  private static func hueAndSaturation(_ color: ThemeColor) -> (Double, Double) {
    let r = color.red
    let g = color.green
    let b = color.blue
    let high = max(r, g, b)
    let low = min(r, g, b)
    let range = high - low
    guard range > 0 else { return (0, 0) }
    var hue: Double
    switch high {
    case r: hue = (g - b) / range
    case g: hue = (b - r) / range + 2
    default: hue = (r - g) / range + 4
    }
    hue = (hue * 60).truncatingRemainder(dividingBy: 360)
    return (hue < 0 ? hue + 360 : hue, range / high)
  }

  /// In the widget extension, the container background is drawn in the system's direction,
  /// outside the face's own: an Arabic face can sit over a left-to-right backdrop, or an
  /// English one over a right-to-left backdrop, with its glows mirrored. Each ink resolves
  /// against the backdrop as drawn and holds the same floors.
  @Test(arguments: [true, false])
  func facesHoldOverABackdropInTheOtherDirection(_ faceIsRightToLeft: Bool) throws {
    let language: Baseline.Language = faceIsRightToLeft ? .ar : .en
    try AppLanguageScope.with(BaselinePipeline.appLanguage(language)) {
      for theme in SalahWidgetTheme.allPresets {
        for scheme in [ColorScheme.light, .dark] {
          for state in [SpecState.idle, .imminent, .countUp, .endOfDay, .playingPreReminder] {
            for size in [SalahWidgetSize.small, .medium, .large] {
              var display = BaselinePipeline.display(for: state, language: language)
              display.settings.theme = theme
              try measure(
                AnyView(
                  MixedDirectionFace(
                    display: display, size: size, faceIsRightToLeft: faceIsRightToLeft)),
                label:
                  "mixed \(theme.id) \(language.rawValue) \(scheme) \(state.rawValue) \(size)",
                scheme: scheme, contrast: .standard)
            }
          }
        }
      }
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

/// A face drawn as the widget extension's shell draws it when the face's direction differs
/// from the system's: the content in its own direction and locale, the backdrop in the other
/// direction, with the backdrop the inks resolve against saying so.
private struct MixedDirectionFace: View {
  let display: SalahDisplay
  let size: SalahWidgetSize
  let faceIsRightToLeft: Bool
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    let colors = display.theme.colors(for: scheme)
    let point = size.desktopPointSize
    content
      .environment(\.locale, display.locale)
      .environment(\.layoutDirection, faceIsRightToLeft ? .rightToLeft : .leftToRight)
      .environment(
        \.salahWidgetBackdrop,
        SalahWidgetBackdrop(
          colors: colors, tone: display.backgroundTone, size: point,
          isRightToLeft: !faceIsRightToLeft)
      )
      .frame(width: point.width, height: point.height)
      .coordinateSpace(.named(SalahWidgetBackdrop.coordinateSpace))
      .background { SalahWidgetBackground(tone: display.backgroundTone, colors: colors) }
      .environment(\.layoutDirection, faceIsRightToLeft ? .leftToRight : .rightToLeft)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  @ViewBuilder
  private var content: some View {
    switch display.widgetFace {
    case .stop: WidgetStopContent(display: display, size: size)
    case .unavailable:
      WidgetMessageContent(
        systemImage: "exclamationmark.triangle",
        message: Text(verbatim: display.labels.timesUnavailable))
    case .schedule: WidgetContentView(display: display, size: size)
    }
  }
}

/// `salahInk` keeps text's layout: wrapping text wraps, and single-line text sits, exactly as
/// the same text styled directly.
@Suite("Widget inks keep text's layout")
struct WidgetInkLayoutTests {
  init() { TestEnvironment.configure() }

  /// Text, and widths of the face it's centered in, at which a copy laid out again at its
  /// own size broke its lines differently.
  static let wrapping: [(String, Double)] = [
    ("Prayer times aren\u{2019}t available for this location.", 141.5),
    ("Heure de la prochaine prière indisponible", 96.5),
  ]

  @Test func textLaysOutAsStyledDirectly() throws {
    for (text, width) in Self.wrapping {
      for scheme in [ColorScheme.light, .dark] {
        for wraps in [true, false] {
          func face(inked: Bool) -> some View {
            let label = Text(verbatim: text)
              .font(.callout.weight(.medium))
              .multilineTextAlignment(.center)
              .lineLimit(wraps ? nil : 1)
              .minimumScaleFactor(0.8)
            let ink = wraps ? SalahWidgetInk.primary.wrapping : .primary
            // As `WidgetMessageContent` lays out its message, in a face `width` wide.
            return VStack(spacing: 10) {
              if inked { label.salahInk(ink) } else { label.foregroundStyle(Color.primary) }
            }
            .padding()
            .frame(width: width, height: 158)
            .environment(
              \.salahWidgetBackdrop,
              SalahWidgetBackdrop(
                colors: SalahWidgetTheme.nocturne.colors(for: scheme), tone: .normal,
                size: CGSize(width: width, height: 158), isRightToLeft: false)
            )
            .coordinateSpace(.named(SalahWidgetBackdrop.coordinateSpace))
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
          }
          let inked = try BaselineRenderer.stablePNG { face(inked: true) }
          let direct = try BaselineRenderer.stablePNG { face(inked: false) }
          let result = try #require(PixelComparison.compare(inked, to: direct))
          #expect(
            result.differingPixels == 0,
            "\(text) at \(width) pt, \(scheme), wraps \(wraps): \(result)")
        }
      }
    }
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
