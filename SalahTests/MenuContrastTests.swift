import Foundation
import SalahCore
import SalahUI
import SwiftUI
import Testing

/// A numerical regression for the passed row's former blanket opacity. This draws the
/// production row over the production sky, without depending on the ink probe that the
/// corrected menu uses. Empty labels preserve the row's fixed text columns and its 18pt
/// icon, providing the actual surface behind the two labels.
@Suite("Passed menu row contrast")
struct MenuPassedRowContrastTests {
  init() { TestEnvironment.configure() }

  @Test func passedNamesAndTimesKeepReadableInk() throws {
    let size = CGSize(width: 300, height: 400)
    let scale = 3
    let display = BaselinePipeline.display(for: .idle, language: .en)
    for scheme in [ColorScheme.light, .dark] {
      for contrast in [ColorSchemeContrast.standard, .increased] {
        let colors = SalahWidgetTheme.nocturne.colors(for: scheme)
        func face(showsText: Bool) -> some View {
          MenuScheduleRow(
            name: Text(verbatim: showsText ? "Dhuhr" : ""),
            time: Text(verbatim: showsText ? "12:34 PM" : ""), state: .passed,
            isSunrise: true, alertEnabled: false, colors: colors, labels: display.labels
          )
          .frame(width: 276)
          .frame(width: size.width, height: size.height)
          .environment(
            \.salahWidgetBackdrop,
            SalahWidgetBackdrop(
              colors: colors, tone: .normal, size: size, isRightToLeft: false)
          )
          .coordinateSpace(.named(SalahWidgetBackdrop.coordinateSpace))
          .background { SalahWidgetBackground(tone: .normal, colors: colors) }
          .environment(\.layoutDirection, .leftToRight)
          .environment(\.locale, Locale(identifier: "en"))
          .environment(\.colorScheme, scheme)
          .environment(\._colorSchemeContrast, contrast)
        }
        let shown = try #require(
          PixelComparison.rgba(BaselineRenderer.stablePNG(scale: scale) { face(showsText: true) }))
        let hidden = try #require(
          PixelComparison.rgba(BaselineRenderer.stablePNG(scale: scale) { face(showsText: false) }))
        try #require(shown.width == 900 && shown.height == 1200)
        try #require(shown.width == hidden.width && shown.height == hidden.height)

        // 12pt outer margin, 10pt row padding, 18pt icon and 10pt spacing; the
        // trailing time column is 70pt wide. The mask must stay inside these exact
        // columns, so changes to row geometry cannot silently invalidate this test.
        let columns = [
          (name: "name", area: CGRect(x: 50, y: 0, width: 56, height: size.height)),
          (name: "time", area: CGRect(x: 208, y: 0, width: 70, height: size.height)),
        ]
        var counts = [0, 0]
        var strongest = [0.0, 0.0]
        var outside = 0
        for offset in stride(from: 0, to: shown.bytes.count, by: 4) {
          guard
            (0..<3).contains(where: {
              abs(Int(shown.bytes[offset + $0]) - Int(hidden.bytes[offset + $0])) > 2
            })
          else { continue }
          let point = CGPoint(
            x: (Double(offset / 4 % shown.width) + 0.5) / Double(scale),
            y: (Double(offset / 4 / shown.width) + 0.5) / Double(scale))
          guard let column = columns.firstIndex(where: { $0.area.contains(point) }) else {
            outside += 1
            continue
          }
          counts[column] += 1
          strongest[column] = max(
            strongest[column],
            MenuContrastPixels.contrast(shown.bytes, over: hidden.bytes, at: offset))
        }
        #expect(outside == 0, "\(scheme) \(contrast): text mask changed outside its columns")
        for index in columns.indices {
          let label = "\(scheme) \(contrast) passed \(columns[index].name)"
          #expect(counts[index] > 60, "\(label): the mask must observe actual label glyphs")
          // Antialiased edge pixels are blends. At 3px/pt the fullest stroke must
          // reach the text floor. The former whole-row 0.55 opacity cannot do so.
          #expect(strongest[index] >= 4.5, "\(label): strongest ink is only \(strongest[index]):1")
          print("menu-passed-contrast \(label): \(strongest[index]) (\(counts[index]) px)")
        }
      }
    }
  }
}

/// Measures the real dropdown, including its header, cards, row states and controls.
/// Unlike the widget's deliberate dimming exception, every menu text ink needs 4.5:1,
/// including passed and missing prayers; every meaningful glyph needs 3:1.
@Suite("Menu ink contrast")
struct MenuContrastTests {
  init() { TestEnvironment.configure() }

  nonisolated struct Run: Sendable, CustomTestStringConvertible {
    var name: String
    var theme: SalahWidgetTheme
    var language: Baseline.Language = .en
    var states: [SpecState] = [.idle]
    var contrasts: [ColorSchemeContrast] = [.standard, .increased]
    var testDescription: String { "\(name) \(language.rawValue)" }
    var schemes: [ColorScheme] {
      switch theme.appearance {
      case .system: [.light, .dark]
      case .alwaysDark: [.dark]
      case .alwaysLight: [.light]
      }
    }
  }

  nonisolated static let runs: [Run] = {
    var runs = SalahWidgetTheme.allPresets.map { Run(name: $0.id, theme: $0) }
    runs.append(
      Run(
        name: "state-surfaces", theme: .nocturne,
        states: [
          .imminent, .countUp, .countUpSilent, .countUpImminent, .endOfDay,
          .playingAdhan, .playingPreReminder, .playingPostReminder, .silent,
        ]))
    runs.append(
      Run(
        name: "arabic", theme: .nocturne, language: .ar,
        states: [.idle, .countUp, .playingAdhan], contrasts: [.standard]))
    runs.append(
      Run(
        name: "custom-white-dark",
        theme: .custom(
          accent: ThemeColor(0.30, 0.55, 0.55), primary: ThemeColor(1, 1, 1),
          base: .sand, appearance: .alwaysDark)))
    runs.append(
      Run(
        name: "custom-near-black-light",
        theme: .custom(
          accent: ThemeColor(0.30, 0.55, 0.55), primary: ThemeColor(0.05, 0.05, 0.08),
          base: .graphite, appearance: .alwaysLight)))
    return runs
  }()

  @Test(arguments: runs)
  func inkHoldsOverTheDropdown(_ run: Run) throws {
    try AppLanguageScope.with(BaselinePipeline.appLanguage(run.language)) {
      for scheme in run.schemes {
        for contrast in run.contrasts {
          for state in run.states {
            var display = BaselinePipeline.display(for: state, language: run.language)
            display.settings.theme = run.theme
            try measure(
              MenuDropdownContent(display: display),
              label: "\(run.name) \(run.language.rawValue) \(scheme) \(contrast) \(state)",
              scheme: scheme, contrast: contrast)
          }
        }
      }
    }
  }

  /// The playback menu fills its entire rendered bounds. Measuring its shorter
  /// content in an overlay must not leave transparent bands above and below it.
  @Test func playbackBackdropCoversTheEntireMenu() throws {
    for language in [Baseline.Language.en, .ar, .fr] {
      try AppLanguageScope.with(BaselinePipeline.appLanguage(language)) {
        for scheme in [ColorScheme.light, .dark] {
          for state in [
            SpecState.playingAdhan, .playingPreReminder, .playingPostReminder,
          ] {
            let display = BaselinePipeline.display(for: state, language: language)
            let pixels = try #require(
              PixelComparison.rgba(
                BaselineRenderer.stablePNG {
                  MenuDropdownContent(display: display).environment(\.colorScheme, scheme)
                }))
            let transparentPixels = stride(from: 3, to: pixels.bytes.count, by: 4).filter {
              pixels.bytes[$0] != 255
            }.count
            #expect(
              transparentPixels == 0,
              "\(language) \(scheme) \(state): the playback backdrop must cover every pixel")
          }
        }
      }
    }
  }

  /// Missing rows and the unknown-next/last-known messages use the same production
  /// dropdown construction, rather than a facsimile of its individual text styles.
  @Test func scheduleGapsKeepReadableInk() throws {
    let language = PreviewLang.en
    let now = BaselinePipeline.previewNow
    let partial = WidgetPreviewData.make(
      prayers: [
        .init(id: .fajr, offset: -8 * 60), .init(id: .dhuhr, offset: -3 * 60),
        .init(id: .asr, offset: -60), .init(id: .maghrib, offset: 162, pre: 10, post: 5),
      ], lang: language, now: now)
    let unknown = WidgetPreviewData.make(
      prayers: [
        .init(id: .fajr, offset: -16 * 60), .init(id: .sunrise, offset: -14 * 60, alert: false),
        .init(id: .dhuhr, offset: -9 * 60), .init(id: .asr, offset: -5 * 60),
        .init(id: .maghrib, offset: -2 * 60), .init(id: .isha, offset: -30),
      ], lang: language, now: now)
    var unavailable = partial
    unavailable.day = .unavailable(.noPublishedData)
    for scheme in [ColorScheme.light, .dark] {
      for contrast in [ColorSchemeContrast.standard, .increased] {
        for (name, display, lastKnown) in [
          ("missing", partial, Optional<PrayerDayAvailability>.none),
          ("next-unknown", unknown, nil),
          ("last-known", unavailable, partial.day),
        ] {
          try measure(
            MenuDropdownContent(display: display, lastKnownDay: lastKnown),
            label: "\(scheme) \(contrast) \(name)", scheme: scheme, contrast: contrast)
        }
      }
    }
  }

  /// A modifier inside an ink can dim only its glyphs while leaving the probe's
  /// nominal paint unchanged. Three-pixel strokes must reach 90% of that paint.
  @Test func glyphsReachTheirResolvedInk() throws {
    for language in [Baseline.Language.en, .ar] {
      try AppLanguageScope.with(BaselinePipeline.appLanguage(language)) {
        for scheme in [ColorScheme.light, .dark] {
          for state in [SpecState.idle, .countUp, .playingAdhan] {
            let display = BaselinePipeline.display(for: state, language: language)
            try measure(
              MenuDropdownContent(display: display),
              label: "coverage \(language.rawValue) \(scheme) \(state)",
              scheme: scheme, contrast: .standard, scale: 3, checksCoverage: true)
          }
        }
      }
    }
  }

  private func measure(
    _ menu: some View, label: String, scheme: ColorScheme, contrast: ColorSchemeContrast,
    scale: Int = 1, checksCoverage: Bool = false
  ) throws {
    func view(_ probe: SalahWidgetInkProbe?, inherited: Color) -> some View {
      menu.foregroundStyle(inherited)
        .environment(\.salahWidgetInkProbe, probe)
        .environment(\.colorScheme, scheme)
        .environment(\._colorSchemeContrast, contrast)
    }
    func render(_ probe: SalahWidgetInkProbe?, inherited: Color = .init(red: 1, green: 0, blue: 1))
      throws -> MenuContrastPixels.Pixels
    {
      try #require(
        PixelComparison.rgba(
          BaselineRenderer.stablePNG(scale: scale) {
            view(probe, inherited: inherited)
          }))
    }
    _ = try render(nil)
    let hidden = try render(SalahWidgetInkProbe(.hide))
    // Reusing a probe across stablePNG's settling renders also records provisional
    // menu frames. List once after the layout has settled, independently of the
    // probes that render the measurement pixels.
    let listing = SalahWidgetInkProbe(.hide)
    _ = try BaselineRenderer.png(
      view(listing, inherited: .init(red: 1, green: 0, blue: 1)), scale: scale)
    let elements = MenuContrastPixels.merged(listing.elements)
    let otherHidden = try render(
      SalahWidgetInkProbe(.hide), inherited: .init(red: 0, green: 1, blue: 1))
    try #require(hidden.width == otherHidden.width && hidden.height == otherHidden.height)
    let residue = stride(from: 0, to: hidden.bytes.count, by: 4).filter { offset in
      (0..<3).contains {
        abs(Int(hidden.bytes[offset + $0]) - Int(otherHidden.bytes[offset + $0])) > 2
      }
    }.count
    #expect(residue == 0, "\(label): \(residue) pixels inherited an unmeasured foreground")

    let shown = try render(SalahWidgetInkProbe(.show))
    let painted = try render(SalahWidgetInkProbe(.paint))
    try #require(shown.width == hidden.width && shown.height == hidden.height)
    try #require(painted.width == hidden.width && painted.height == hidden.height)
    #expect(elements.count >= 14, "\(label): the probe must observe real menu text and controls")
    #expect(elements.allSatisfy { $0.ink.opacity == 1 }, "\(label): no menu ink is dimmed")

    var pixels = [Int](repeating: 0, count: elements.count)
    var lowest = [Double](repeating: .infinity, count: elements.count)
    var coverage = [Double](repeating: 0, count: elements.count)
    let areas = elements.map {
      $0.frame.insetBy(dx: -SalahWidgetInkProbe.paintMargin, dy: -SalahWidgetInkProbe.paintMargin)
    }
    var unclaimed = 0
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
      pixels[owner] += 1
      lowest[owner] = min(
        lowest[owner], MenuContrastPixels.contrast(painted.bytes, over: hidden.bytes, at: offset))
      let inks = (0..<3).map { Int(painted.bytes[offset + $0]) - Int(hidden.bytes[offset + $0]) }
      let shares = (0..<3).filter { abs(inks[$0]) >= 24 }.map {
        Double(deltas[$0]) / Double(inks[$0])
      }
      if let share = shares.min() { coverage[owner] = max(coverage[owner], share) }
    }
    #expect(unclaimed == 0, "\(label): \(unclaimed) glyph pixels outside every measured ink")
    for index in elements.indices {
      let ink = elements[index].ink
      let name = "\(label) \(ink.source) glyph=\(ink.isGlyph) at \(elements[index].frame)"
      #expect(pixels[index] > 4, "\(name): the element's glyphs must show")
      #expect(lowest[index] >= ink.minimumContrast, "\(name): \(lowest[index]):1")
      if checksCoverage {
        #expect(
          coverage[index] >= 0.9, "\(name): glyphs reach only \(coverage[index]) of their ink")
      }
      print("menu-ink-contrast \(name): \(lowest[index]) (\(pixels[index]) px)")
    }
  }
}

private enum MenuContrastPixels {
  typealias Pixels = (width: Int, height: Int, bytes: [UInt8])

  static func merged(_ elements: [SalahWidgetInkProbe.Element]) -> [SalahWidgetInkProbe.Element] {
    var result: [SalahWidgetInkProbe.Element] = []
    for element in elements {
      if let index = result.firstIndex(where: {
        $0.ink == element.ink && $0.frame.intersects(element.frame)
      }) {
        let frame = result[index].frame.union(element.frame)
        result[index] = element
        result[index].frame = frame
      } else {
        result.append(element)
      }
    }
    return result
  }

  static func contrast(_ painted: [UInt8], over surface: [UInt8], at offset: Int) -> Double {
    #expect(painted[offset + 3] == 255 && surface[offset + 3] == 255)
    func color(_ bytes: [UInt8]) -> ThemeColor {
      ThemeColor(
        red: Double(bytes[offset]) / 255, green: Double(bytes[offset + 1]) / 255,
        blue: Double(bytes[offset + 2]) / 255)
    }
    return ThemeColor.contrastRatio(color(painted), color(surface))
  }
}
